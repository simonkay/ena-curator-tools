#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#  SCRIPT DESCRIPTION:
#  Automation of much of the patent processing (formatting patent files
#  from the EPO and adding them to enapro)
#
#  MODIFICATION HISTORY:
#  $RCSfile: load_patents.pl,v $
#  $Revision: 1.4 $
#  $Date: 2011/06/20 09:39:35 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/load_patents.pl,v $
#  $Author: xin $
#
#===============================================================================

use strict;
use SimplePatentProcessing;

my $PATENT_FTP_DIR      = "/ebi/ftp/private/epo/public";
#my $PATENT_FTP_DIR = "/homes/gemmah/epo_patent_backup";
my $PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/data";
my $PATENT_DATASUBS_DIR = $PATENT_WORKING_DIR."/datasubs";
my $PATENT_CURATOR_DIR  = $PATENT_WORKING_DIR."/curator";

my $verbose = 0;
my $testMode = 0;
my $processOldFormat = 1; # expect to process old format patent files by default



################################################################################
# get the arguments from the command line

sub get_args(\@) {

    my ( $arg, $usage, $database, @inputtedFiles, $patentFile );

    my $args = shift;


    $usage = "\n USAGE: [database] [filename] [-v(erbose)] [-test] [-h(elp)]\n\n"
	. " This script takes patent files from the ftp directory used by the EPO and tries to\n"
	. " automate their processing a little. There are 5 stages to the processing and each are\n"
	. " accessed depending on the files present in the current directory.\n\n"
	. " Stage 4:  Loading is carried out on the embl entries. Any\n"
	. " errors are grouped into files by error type and stored in:\n"
	. " $PATENT_CURATOR_DIR\n"
	. " These must be fixed by the curator before being manually loaded.\n\n"
	. " [database]        \/\@enapro or \/\@devt\n\n"
	. " [filename]        You can add the names of a patent file you want to process\n\n"
	. " [-v(erbose)]      Show extra detailed messages\n\n"
	. " [-test]           test mode - process inside /ebi/production/seqdb/embl/data/patents/test\n\n"
	. " [-h(elp)]         Display this help message\n\n";


    $database = "";

    # check the arguments for values
    foreach $arg ( @$args ) {

	if ( $arg =~ /^\/?\@?(enapro|devt)$/i ) {
	    $database = $arg;
	}
        elsif ( $arg =~ /^\-v(erbose)?/ ) {
            $verbose = 1;         # verbose mode
        }
        elsif ( $arg =~ /^\-test/ ) {
            $testMode = 1;
	    $PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/test";
	    $PATENT_DATASUBS_DIR = $PATENT_WORKING_DIR."/datasubs";
	    $PATENT_CURATOR_DIR  = $PATENT_WORKING_DIR."/curator";
        }
        elsif (( $arg =~ /^\-h(elp)?/ ) || ( $arg =~ /^\-usage/ )) {
            die $usage;
        }
        elsif ( $arg =~ /(^[^-]+\.s25)/ ) {
            push(@inputtedFiles, $1);
        }
        else {
            die "Unrecognised input: $arg\n\n".$usage;
        }
    }


    # populates @patentFiles with the files to use, if all 
    # inputted files exist and are the right format (otherwise die)
    if (@inputtedFiles > 1) {
	die "You can only process one patent file at a time using this script.\n";
    }
    elsif (! @inputtedFiles) {
	die "You need to enter at least one patent file name e.g. e200837.s25 or e200837_n.s25\n";
    }
    else {
	if (! -e "$inputtedFiles[0].embl") {
	    die "You must enter a valid patent data file name e.g. e200835.s25.embl or e200835_n.s25.embl\n";
	}
    }


    $database = ask_for_database($database);

    return($database, $inputtedFiles[0]);
}

################################################################################
#

sub figure_out_format($) {
    
    my $patentFile = shift;

    if ($patentFile =~ /^e\d{6}\.s25$/) {
	$processOldFormat = 1;
    }
    elsif ($patentFile =~ /^e\d{6}_n\.s25$/) {
	$processOldFormat = 0;
    }
    elsif ($patentFile =~ /^(e\d{6}\.s25)\..+$/) {
	$patentFile = $1;
	$processOldFormat = 1;
    }
    elsif ($patentFile =~ /^(e\d{6}_n\.s25)\..+$/) {
	$patentFile = $1;
	$processOldFormat = 0;
    }
    else {
	die "Unrecognised filename format: can't work out if it's a new or an old format data file.\n"
	    . "Old format files have the pattern ".'edddddd\.s25'
	    . " and new format files have the filename pattern ".'edddddd_n\.s25'
	    . " (where d is a digit).\n\n"
    }

    return($patentFile);
}

################################################################################
# main subroutine

sub main (\@) {

    my ($database, $LOGFILE, $logFileName, @file_patterns_to_move, $patentFile);
    my (@filesToDelete, @files_to_move, @log_files_to_move, $movePatentFile);

    my $args = shift;

    ($database, $patentFile) = get_args(@$args);

    ($patentFile) = figure_out_format($patentFile);

    $logFileName = "$patentFile.log.loadpatents";
    open($LOGFILE, ">$logFileName") || die "Cannot write to $logFileName: $!\n";
    
    create_putff_load_log($patentFile, $database, $LOGFILE);
    
    group_putff_error_files($LOGFILE, $logFileName, $processOldFormat, $verbose,  $testMode);

    # move files from datasubs dir into the datasubs archive
    @files_to_move = ('.substd');
    @log_files_to_move = ('.log.loadpatents',
			  '.embl.log.unclassifiedorgs',
			  '.log.orgcheck');
    @file_patterns_to_move = ();
    
    move_files_to_another_dir($patentFile, $PATENT_DATASUBS_DIR, $PATENT_DATASUBS_DIR."/archive/", @files_to_move, @log_files_to_move, @file_patterns_to_move, $verbose);
    
    
    # move files from datasubs dir into the curators directory
    
    @files_to_move = ('.embl',
		      '.embl.log',
		      '.embl.log.unclassifiedorgs',
		      '.log.orgcheck',
		      '.log.loadpatents',
		      '.withduplicates');
    
    @log_files_to_move = ();
    @file_patterns_to_move = ('GroupedError_*');
    
    move_files_to_another_dir($patentFile, $PATENT_DATASUBS_DIR, $PATENT_CURATOR_DIR, @files_to_move, @log_files_to_move, @file_patterns_to_move, $verbose);
    
    close($LOGFILE);
}

main(@ARGV);
