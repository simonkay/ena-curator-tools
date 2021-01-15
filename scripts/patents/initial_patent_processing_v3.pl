#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#  SCRIPT DESCRIPTION:
#  Automation of much of the patent processing (formatting patent files
#  from the EPO and adding them to enapro)
#
#  MODIFICATION HISTORY:
#  $RCSfile: initial_patent_processing_v3.pl,v $
#  $Revision: 1.3 $
#  $Date: 2011/06/20 09:39:35 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/initial_patent_processing_v3.pl,v $
#  $Author: xin $
#
#===============================================================================

use strict;
use SimplePatentProcessing_v3;

my $PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/data";
my $PATENT_DATASUBS_DIR = $PATENT_WORKING_DIR."/datasubs";
my $PATENT_CURATOR_DIR  = $PATENT_WORKING_DIR."/curator";


my $verbose = 0;
my $testMode = 0;
my $valid_file_extension = 'seq';

################################################################################
#

sub make_sure_in_processing_directory() {

    if ($testMode && ($ENV{PWD} ne $PATENT_DATASUBS_DIR)) {
	die "You must run test mode in $PATENT_DATASUBS_DIR\n";
    }
    elsif ($ENV{PWD} ne $PATENT_DATASUBS_DIR) {
	die "You must run test mode in $PATENT_DATASUBS_DIR\n";
    }
}

################################################################################
#

sub check_output_files_do_not_exist($$$) {

    my ( $msg, $msg2, $msg3, $msg4 );

    my $patentFile          = shift;
    my $PATENT_DATASUBS_DIR = shift;
    my $PATENT_CURATOR_DIR  = shift;


    $msg = "This script cannot be run: $patentFile";
    $msg2 = "has been found in";
    $msg3 = "and is therefore already being processed.\n";
    $msg4 = "and is therefore has already been processed.\n";

    if (-e "$PATENT_DATASUBS_DIR/$patentFile.substd") {
	die "$msg.substd $msg2 $PATENT_DATASUBS_DIR $msg3";
    }
    elsif (-e "$PATENT_DATASUBS_DIR/archive/$patentFile.substd") {
	die "$msg.substd $msg2 $PATENT_DATASUBS_DIR/archive $msg3";
    }
    elsif (-e "$PATENT_CURATOR_DIR/$patentFile.embl") {
	die "$msg.embl $msg2 $PATENT_CURATOR_DIR $msg3";
    }
    elsif ((-e "$PATENT_CURATOR_DIR/../archive/$patentFile.gz") || (-e "$PATENT_CURATOR_DIR/../archive/$patentFile")) {
	die "$msg.embl $msg2 $PATENT_CURATOR_DIR $msg4";
    }
}

################################################################################
#

sub print_info() {

    print "\nRunning stage 1:  the patent files will be copied over, duplicate document numbers removed and you will be asked to edit inventor names (removing institutions and titles such as Dr and Prof), reference titles and applicant names (correcting typos, removing non-english characters and removing excess whitespace).  You will also be asked to look in archive/*.org_results for any UNKNOWN organisms and update the database with them.\n";
}

################################################################################
# get the arguments from the command line

sub get_args(\@) {

    my ( $arg, $usage, @inputtedFiles );

    my $args = shift;


    $usage = "\n USAGE: $0 [filename] [-v(erbose)] [-test] [-h(elp)]\n\n"
	. " This script takes patent files from the ftp directory used by the EPO and tries to\n"
	. " automate their processing, as much as it can. This file is the first step in a series\n"
	. " of files to run.\n\n"
	. " Stage 1: Process from scratch. Copies patent files to working directory:\n"
	. " $PATENT_DATASUBS_DIR\n"
	. " Duplicate patent numbers are removed. Bad characters and phrases are substituted for.\n"
	. " The stage completes so datasubs can edit inventor names and reference titles, if required.\n"
	. " The *.org_results files in the datasubs archive directory must be checked for UNKNOWN\n"
	. " organisms which need to be added to the database or updated in the .substd file.\n\n"
	. " [filename]        You can add the name of a single patent file to process\n\n"
	. " [-v(erbose)]      Show extra detailed messages\n\n"
	. " [-test]           test mode - process inside /ebi/production/seqdb/embl/data/patents/test\n\n"
	. " [-h(elp)]         Display this help message\n\n"
        . "NB this script must be run from $PATENT_DATASUBS_DIR\n\n";

    # check the arguments for values
    foreach $arg ( @$args ) {

        if ( $arg =~ /^\-v(erbose)?/ ) {
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
        elsif ( $arg =~ /(^[^-]+\.$valid_file_extension)/ ) {
            push(@inputtedFiles, $1);
        }
        else {
            die "Unrecognised input: $arg\n\n".$usage;
        }
    }

    if (@inputtedFiles > 1) {
	die "You can only process one patent file at a time using this script.\n";
    }
    elsif (! @inputtedFiles) {
	die "You need to enter at least one patent file name e.g. e200837.$valid_file_extension\n";
    }
    else {
	check_output_files_do_not_exist($inputtedFiles[0], $PATENT_DATASUBS_DIR, $PATENT_CURATOR_DIR);
    }

    return($inputtedFiles[0]);
}

################################################################################
#

sub remove_extra_double_quotes($$$) {

    my ($line, $editFile, $cmd, $msg, $empty_note_ctr, $dbl_quote_ctr);
    my ($newEditFile);

    my $patentFile = shift;
    my $verbose = shift;
    my $LOGFILE = shift;

    $editFile = $patentFile.".substd";
    $newEditFile = $patentFile.".substd.new";

    $dbl_quote_ctr = 0;
    $empty_note_ctr = 0;

    if (open (READPATENT, "<$editFile")) {

	open(WRITEPATENT, ">$editFile".".new");

	while ($line = <READPATENT>) {
	    if ($line =~ s/^FT\s+\/note="\s*"$//) {
		$empty_note_ctr++;
	    }
	    if ($line =~ s/"\s*"/"/g) { #"
		$dbl_quote_ctr++;
	    }
	    print WRITEPATENT $line;

	}

	close(WRITEPATENT);
    }
    close(READPATENT);

    $cmd = "mv $newEditFile $editFile";
    system($cmd); 

    $msg = "$editFile updated with $empty_note_ctr empty note qualifiers removed and $dbl_quote_ctr double double-quotes removed.\n";
    $verbose && print $msg;
    print $LOGFILE $msg;
}


################################################################################
# main subroutine

sub main (\@) {

    my ($LOGFILE, $logFileName, $patentFile, @file_patterns_to_move);
    my (@filesToDelete, @files_to_move, @log_files_to_move, $movePatentFile);

    my $args = shift;

    ($patentFile) = get_args(@$args);

    make_sure_in_processing_directory();

    $movePatentFile = 1;

    $logFileName = "$patentFile.log.initialpro";
    open($LOGFILE, ">$logFileName") || die "Cannot write to $logFileName: $!\n";

    print_info();

    copy_patent_file_into_working_dir($patentFile);

    manage_duplicate_document_nums($patentFile, $LOGFILE, $verbose, $PATENT_DATASUBS_DIR);
	
    substitute_characters($patentFile, $LOGFILE, $verbose);

    check_for_typos_in_title($patentFile, $LOGFILE, $logFileName);

    check_for_existence_of_authors($patentFile, $LOGFILE, $logFileName);
    
    remove_whitespace_in_applicant_name($patentFile, $LOGFILE, $logFileName, $PATENT_WORKING_DIR);

    check_orgs_are_ok($patentFile, $verbose, $LOGFILE);

# remove empty note qualifiers and extra double quotes in file

    remove_extra_double_quotes($patentFile, $verbose, $LOGFILE);


    @files_to_move = ('.title.log',
		      '_1.1',
		      '_2.2',
		      '.inventors.log',
		      '.substd.bkup',
		      '.org_list',
		      '.org_results');
    @log_files_to_move = ($logFileName);
    @file_patterns_to_move = ();

    # move files from datasubs dir into the datasubs archive
    move_files_to_another_dir($patentFile, $PATENT_DATASUBS_DIR, $PATENT_DATASUBS_DIR."/archive/", @files_to_move, @log_files_to_move, @file_patterns_to_move, $verbose, $movePatentFile);
    
    close($LOGFILE);
}

main(@ARGV);
