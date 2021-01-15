#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#  SCRIPT DESCRIPTION:
#  Automation of much of the patent processing (formatting patent files
#  from the EPO and adding them to enapro)
#
#  MODIFICATION HISTORY:
#  $RCSfile: tidy_away_patent_files.pl,v $
#  $Revision: 1.9 $
#  $Date: 2011/06/20 09:39:35 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/tidy_away_patent_files.pl,v $
#  $Author: xin $
#
#===============================================================================

use strict;
use Data::Dumper;
use SimplePatentProcessing;

my $PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/data";
my $PATENT_CURATOR_DIR  = $PATENT_WORKING_DIR."/curator";

my $verbose = 0;
my $testMode = 0;
my $processOldFormat = 1; # expect to process old format patent files by default


################################################################################
#

sub make_sure_in_processing_directory() {

    if ($testMode && ($ENV{PWD} ne $PATENT_CURATOR_DIR)) {
	die "You must run test mode in $PATENT_CURATOR_DIR\n";
    }
    elsif ($ENV{PWD} ne $PATENT_CURATOR_DIR) {
	die "You must run this stage of the script from $PATENT_CURATOR_DIR\n";
    }
}

################################################################################
# get the arguments from the command line

sub get_args(\@) {

    my ( $arg, $usage, @inputtedFiles );

    my $args = shift;


    $usage = "\n USAGE: $0 [filename] [-v(erbose)] [-test] [-h(elp)]\n\n"
	. " This script takes patent files from the ftp directory used by the EPO and tries to\n"
	. " automate their processing a little. There are 5 stages to the processing .\n\n"
	. " Stage 5: All the patent files are tidied away into the archive directory here:\n"
	. " $PATENT_WORKING_DIR\n"
	. " and are zipped up.\n\n"
	. " [filename]       You can add the names of the patent files you want to process\n\n"
	. " [-v(erbose)]      Show extra detailed messages\n\n"
	. " [-test]           test mode - process inside /ebi/production/seqdb/embl/data/patents/test\n\n"
	. " [-h(elp)]         Display this help message\n\n";


    # check the arguments for values
    foreach $arg ( @$args ) {

        if ( $arg =~ /^\-v(erbose)?/ ) {
            $verbose = 1;         # verbose mode
        }
        elsif ( $arg =~ /^\-test/ ) {
            $testMode = 1;
	    $PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/test";
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

    if ($testMode) {
	$PATENT_WORKING_DIR  = "/ebi/production/seqdb/embl/data/patents/test";
    }

    if (@inputtedFiles > 1) {
	die "You can only process one patent file at a time using this script.\n";
    }
    elsif (! @inputtedFiles) {
	die "You need to enter at least one patent file name e.g. e200837.s25 or e200837_n.s25\n";
    }
    else {
	if (! -e $inputtedFiles[0].".embl") {
	    die $inputtedFiles[0].".embl does not exist.  You must enter a valid patent data file name e.g. e200835.s25 or e200835_n.s25\n";
	}
    }

    return($inputtedFiles[0]);
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

    my ($patentFile, $distribution_cmd, $distribution_file);

    my $args = shift;

    ($patentFile) = get_args(@$args);

    make_sure_in_processing_directory();

    ($patentFile) = figure_out_format($patentFile);

    # distribute any accessions marked for distribution
    # (-s = exists and has non-zero size)
    $distribution_file = 'accs_to_distribute_'.$patentFile;

    if (-s $distribution_file) {

	$distribution_cmd = '/ebi/production/seqdb/embl/tools/curators/scripts/distribute_entry.pl /@enapro -f '.$distribution_file;

	system($distribution_cmd);
	$verbose && print "$distribution_cmd\nwas run to distribute entries with changed doctypes.\n"
    }

    tidy_away_files($patentFile, $PATENT_WORKING_DIR, $testMode, $verbose);
}

main(@ARGV);
