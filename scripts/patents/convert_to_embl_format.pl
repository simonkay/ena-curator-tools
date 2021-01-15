#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#  SCRIPT DESCRIPTION:
#  Automation of much of the patent processing (formatting patent files
#  from the EPO and adding them to enapro)
#
#  MODIFICATION HISTORY:
#  $RCSfile: convert_to_embl_format.pl,v $
#  $Revision: 1.8 $
#  $Date: 2011/06/20 09:39:35 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/convert_to_embl_format.pl,v $
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
#

sub make_sure_in_processing_directory() {

    if ($testMode && ($ENV{PWD} ne $PATENT_DATASUBS_DIR)) {
	die "You must run test mode in $PATENT_DATASUBS_DIR\n";
    }
    elsif ($ENV{PWD} ne $PATENT_DATASUBS_DIR) {
	die "You must run this stage of the script from $PATENT_DATASUBS_DIR\n";
    }
}

################################################################################
#

sub check_output_files_do_not_exist($$$) {

    my ( $msg, $msg2, $msg3, $msg4 );

    my $patentFile           = shift;
    my $PATENT_DATASUBS_DIR  = shift;
    my $PATENT_CURATOR_DIR   = shift;


    $msg = "This script cannot be run: $patentFile";
    $msg2 = "has been found in";
    $msg3 = "and is therefore already being processed.\n";
    $msg4 = "and is therefore has already been processed.\n";

    if ((-e "$PATENT_DATASUBS_DIR/$patentFile.embl") || (-e "$PATENT_CURATOR_DIR/$patentFile.embl")) {
	die "$msg.embl $msg2 $PATENT_CURATOR_DIR $msg3";
    }
    elsif ((-e "$PATENT_CURATOR_DIR/../archive/$patentFile.gz") || (-e "$PATENT_CURATOR_DIR/../archive/$patentFile")) {
	die "$msg.embl $msg2 $PATENT_CURATOR_DIR $msg4";
    }
}

################################################################################
#

sub check_previous_edits_are_done($) {

    my ($response);

    my $patentFile = shift;

    print "\nHave you updated the (XI) APPLICANT NAME, (XII)  INVENTOR NAME and (XIII) TITLE fields?\n(y/n)? ";

    $response = <STDIN>;
	
    if ($response !~ /^y/i) {
	die "Exiting script.\n";
    }

    $response = "n";

    print "\nHave you checked the organisms in archive/*.org_results and edited any UNKNOWN and UNCLASSIFIED organisms inside $patentFile.substd?\n(y/n)? ";

    $response = <STDIN>;
	
    if ($response !~ /^y/i) {
	die "Exiting script.\n";
    }
	
    print "\nRunning stage 2:  the patent data will be converted to embl format (with assigned accessions) and loading the entries into the database will be attempted to show any load errors that need correcting.\n\n";
}

################################################################################
# get the arguments from the command line

sub get_args(\@) {

    my ( $arg, $usage, $database, @inputtedFiles );

    my $args = shift;


    $usage = "\n USAGE: $0 username/password\@db [filename] [-v(erbose)] [-test] [-h(elp)]\n\n"
	. " This script takes patent files from the ftp directory used by the EPO.\n"
	. " Stage 2: Convert patent data to embl format. \n\n"
	. " [database]  \/\@enapro or \/\@devt\n\n"
	. " [filename]        You can add the name of a patent file you want to process\n\n"
	. " [-v(erbose)]      Show extra detailed messages\n\n"
	. " [-test]           test mode - process inside /ebi/production/seqdb/embl/data/patents/test\n\n"
	. " [-h(elp)]         Display this help message\n\n"
        . "NB this script must be run from $PATENT_DATASUBS_DIR\n\n";

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
	check_output_files_do_not_exist($inputtedFiles[0], $PATENT_DATASUBS_DIR, $PATENT_CURATOR_DIR);
    }


    return($database, $inputtedFiles[0]);
}

################################################################################
#

sub figure_out_format($) {

    my $patentFile = shift;

    if ($patentFile =~ /^(e\d{6}\.s25)/) {
	$patentFile = $1;
	$processOldFormat = 1;

    }
    elsif ($patentFile =~ /^(e\d{6}_n\.s25)/) {
	$patentFile = $1;
	$processOldFormat = 0;
    }
    else {
	die "Unrecognised filename format: can't work out if it's a new or an old format data file.\n"
	    . "The script is expecting a file name like edddddd.s25.substd or edddddd_n.s25.substd "
	    . " (where d is a digit).\n\n";
    }

    return($patentFile);
}

################################################################################
#

sub add_source_and_organism_and_moltype($$$) {

    my ($editFile, $correctedEditFile, $msg);

    my $patentFile = shift; 
    my $verbose = shift;
    my $LOGFILE = shift;

    $editFile = $patentFile.".embl";
    $correctedEditFile = $editFile.".corrected";

    $msg = "Adding missing source features, organisms and mol_types.\n";
    $verbose && print $msg;
    print $LOGFILE $msg;

    system("/ebi/production/seqdb/embl/tools/curators/scripts/patents/emblentry_fix_source.pl $editFile");
    system("/ebi/production/seqdb/embl/tools/curators/scripts/patents/emblentry_fix_organism_sc.pl $correctedEditFile");
    system("/ebi/production/seqdb/embl/tools/curators/scripts/patents/emblentry_fix_moltype.pl $correctedEditFile");
    system ("mv $correctedEditFile $editFile");

    $msg = "Source features, organisms and mol_types have all been updated so none should be missing.\n";
    $verbose && print $msg;
    print $LOGFILE $msg;

}

################################################################################
#

sub remove_duplicate_misc_features($$$) {

    my ($editFile, $msg);

    my $patentFile = shift; 
    my $verbose = shift;
    my $LOGFILE = shift;

    $editFile = $patentFile.".embl";

    system("/ebi/production/seqdb/embl/tools/curators/scripts/patents/remove_extra_misc_fts2.pl $editFile");

    $msg = "Removing duplicate misc features.\n";
    $verbose && print $msg;
    print $LOGFILE $msg;
}

################################################################################
#

sub remove_embedded_double_quotes($$$) {

    my ($editFile, $msg);

    my $patentFile = shift; 
    my $verbose = shift;
    my $LOGFILE = shift;

    $editFile = $patentFile.".embl";

    system("/ebi/production/seqdb/embl/tools/curators/scripts/patents/remove_embedded_double_quotes.pl $editFile");

    $msg = "Removing double quotes embedded in qualifiers.\n";
    $verbose && print $msg;
    print $LOGFILE $msg;
}

################################################################################
# main subroutine

sub main (\@) {

    my ($database, $LOGFILE, $logFileName, $patentFile, @files_to_move);
    my (@log_files_to_move, @file_patterns_to_move, $movePatentFile);

    my $args = shift;

    ($database, $patentFile) = get_args(@$args);

    make_sure_in_processing_directory();

    ($patentFile) = figure_out_format($patentFile);


    $logFileName = "$patentFile.log.emblconversion";
    open($LOGFILE, ">$logFileName") || die "Cannot write to $logFileName: $!\n";
    
    check_input_file_exists_in_datasubs_dir($patentFile, $PATENT_DATASUBS_DIR, $processOldFormat);
    
    check_previous_edits_are_done($patentFile);
    
    $database = ask_for_database($database);
    
    convert_to_embl_format($patentFile, $database, $LOGFILE, $processOldFormat);
    
    if ($processOldFormat) {
	remove_duplicate_features($patentFile, $LOGFILE, $verbose);
    }
    
    check_org_edits_are_done($patentFile, $database, $verbose, $LOGFILE);

    add_source_and_organism_and_moltype($patentFile, $verbose, $LOGFILE);

    remove_duplicate_misc_features($patentFile, $verbose, $LOGFILE);

    #remove_embedded_double_quotes($patentFile, $verbose, $LOGFILE);
    

    @files_to_move = ('.log.emblconversion');
    @log_files_to_move = ('patents.log');
    @file_patterns_to_move = ();
    $movePatentFile = 0;

    # move files from datasubs dir into the datasubs archive
    move_files_to_another_dir($patentFile, $PATENT_DATASUBS_DIR, $PATENT_DATASUBS_DIR."/archive/", @files_to_move, @log_files_to_move, @file_patterns_to_move, $verbose, $movePatentFile);
    
    close($LOGFILE);
}

main(@ARGV);
