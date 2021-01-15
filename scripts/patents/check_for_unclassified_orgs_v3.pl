#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#  SCRIPT DESCRIPTION:
#  Automation of much of the patent processing (formatting patent files
#  from the EPO and adding them to enapro)
#
#  MODIFICATION HISTORY:
#  $RCSfile: check_for_unclassified_orgs_v3.pl,v $
#  $Revision: 1.3 $
#  $Date: 2011/06/20 09:39:35 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/check_for_unclassified_orgs_v3.pl,v $
#  $Author: xin $
#
#===============================================================================

use strict;
use SimplePatentProcessing_v3;

my $PATENT_FTP_DIR      = "/ebi/ftp/private/epo/public";
#my $PATENT_FTP_DIR = "/homes/gemmah/epo_patent_backup";
my $PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/data";
my $PATENT_DATASUBS_DIR = $PATENT_WORKING_DIR."/datasubs";
my $PATENT_CURATOR_DIR  = $PATENT_WORKING_DIR."/curator";

my $verbose = 0;
my $testMode = 0;
my $valid_file_extension = 'seq';

################################################################################
# get the arguments from the command line

sub get_args(\@) {

    my ( $arg, $usage, $database, @inputtedFiles );

    my $args = shift;

    $usage = "\n USAGE: $0 [database] [filename] [-v(erbose)] [-test] [-h(elp)]\n\n"
	. " This script takes patent files from the ftp directory used by the EPO.\n"
	. " Stage 3: The embl file is test-loaded (putff -r) so that unclassified organisms can be spotted and added to the edddddd.$valid_file_extension.org_results file in:\n"
	. " $PATENT_WORKING_DIR/archive\n. This script can be run repeatedly until all the organisms in the .embl file have been edited.\n\n"
	. " [database]        \/\@enapro or \/\@devt\n\n"
	. " [filename]        You can add the name of a patent file you want to check the organisms in to see if they will load\n\n"
	. " [-v(erbose)]      Show extra detailed messages\n\n"
	. " [-test]           test mode - process inside /ebi/production/seqdb/embl/data/patents/test\n\n"
	. " [-h(elp)]         Display this help message\n\n";


    $database = "";

    # check the arguments for values
    foreach $arg ( @$args ) {

	if ( $arg =~ /(enapro|devt)$/i ) {
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
        elsif ( $arg =~ /(^[^-]+\.$valid_file_extension)/ ) {
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
	die "You need to enter at least one patent file name e.g. e200837.$valid_file_extension.embl\n";
    }
    else {
	if (! -e "$inputtedFiles[0].embl") {
	    die "You must enter a valid patent data file name e.g. e200835.$valid_file_extension.embl\n";
	}
    }

    return($database, $inputtedFiles[0]);
}

################################################################################
# main subroutine

sub main (\@) {

    my ($database, $LOGFILE, $logFileName, $patentFile);

    my $args = shift;

    ($database, $patentFile) = get_args(@$args);

    $logFileName = "$patentFile.log.orgcheck";
    open($LOGFILE, ">$logFileName") || die "Cannot write to $logFileName: $!\n";

    check_org_edits_are_done($patentFile, $database, $verbose, $LOGFILE);

    close($LOGFILE);
}

main(@ARGV);
