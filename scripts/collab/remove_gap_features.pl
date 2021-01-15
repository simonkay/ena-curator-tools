#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/collab/remove_gap_features.pl,v 1.1 2008/12/05 16:32:06 gemmah Exp $
#
#####################################################################
#
# Simple script to remove gap features of entries in the supplied file
#
# Author: Gemma Hoad
#
#####################################################################

use strict;

#--------------------------------------------------
sub remove_gaps($) {

    my ($output_file, $line, $in_gap);

    my $input_file = shift;

    $output_file = $input_file.".nogaps";

    open(READ, "<$input_file") || die "Cannot open $input_file\n";
    open(WRITE, ">$output_file");

    $in_gap = 0;

    while ($line = <READ>) {

	if ($line =~ /^     gap/) {
	    $in_gap = 1;
	}
	elsif (($in_gap) && ($line =~ /^                     /)) {
	    # do not save line
	}
	elsif (($in_gap) && ($line =~ /^ {0,7}[A-Z]+   \S/)) {
	    $in_gap = 0;  #gap feature ends
	    print WRITE $line;
	}
	else {
	    print WRITE $line;
	}
    }

    close(WRITE);
    close(READ);

    system("mv $output_file $input_file");
    print "Gap features have been removed from $input_file\n";
}
#--------------------------------------------------
sub main(\@) {

    my ($input_file, $arg);
    my $args = shift;

    foreach $arg (@$args) {
	if (-e $arg) {
	    $input_file = $arg;
	}
    }

    if (!defined($input_file)) {
	die "No input file supplied.  Please enter an input filename in the command to remove gaps from it.\n";
    }

    remove_gaps($input_file);


}

main(@ARGV);
