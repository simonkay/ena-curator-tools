#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  SCRIPT DESCRIPTION:
#
#  This script calls a sequence of scripts.  
#  1. The first script creates blast summaries from input sequences/sequence
#     files in the current directory.  
#  2. The second script summarizes the complementary sequences found in the 
#     summary file from step 1.
#  3. The third script makes reverse complment embl-format files from existing
#     embl files, calling them <orig_embl_file>.revcomp
#
#===============================================================================

use strict;

#my $scripts_dir = "/ebi/production/seqdb/embl/developer/gemmah/seqdb/seqdb/tools/curators/scripts/";
my $scripts_dir = "/ebi/production/seqdb/embl/tools/curators/scripts/";
my $verbose = 0;

#############################################################
#

sub run_curator_blast(\@) {

    my ($quick_blast, $out_file, $arg, $cmd);

    my $args = shift;

    $cmd = $scripts_dir."curator_blast.pl -t=16S ";
    $quick_blast = 0;
    $out_file = "blast16S_sens_summary";

    foreach $arg (@$args) {
	if ($arg =~ /^-q(uick)?/) {
	    $quick_blast = 1;
	    $out_file = "blast16S_summary";
	}
	elsif ($arg =~ /^-v(erbose)?/) {
	    $verbose = 1;
	}
	else {
	    $cmd .= "$arg ";
	}
    }
    
    if ($quick_blast) {
	$cmd .= " -quick ";
    }

    if ($verbose) { print "Running: $cmd\n"; }
    
    system($cmd);

    return($out_file);
}

#############################################################
#

sub summarize_blast16S_summaries($) {

    my $summary_file = shift;

    my $cmd = $scripts_dir."summarize_blast16S_summaries.pl $summary_file";
    if ($verbose) { print "Running: $cmd\n"; }

    system($cmd);
}

#############################################################
#

sub make_reverse_comp_files($) {

    my $summary_file = shift;

    my $cmd = $scripts_dir."rev_comp_maker.pl $summary_file";
    if ($verbose) { print "Running: $cmd\n\n"; }

    system($cmd);
}

#############################################################
#

sub main(\@) {

    my $args = shift;

    my $summary_file = run_curator_blast(@$args);

    summarize_blast16S_summaries($summary_file);

    make_reverse_comp_files($summary_file);

}

#############################################################
#

main(@ARGV); 
