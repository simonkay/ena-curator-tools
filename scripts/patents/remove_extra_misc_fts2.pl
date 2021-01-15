#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/remove_extra_misc_fts2.pl,v 1.1 2008/12/19 14:35:47 gemmah Exp $
#
#####################################################################
#
# Script removes duplicate misc_feature features and adds the extra
# qualifiers to the first misc_feature with the same location
#
# Author: Gemma Hoad
#
#####################################################################


use strict;
use Data::Dumper;

sub get_args(\@) {

    my ($inputFile, $arg);

    my $args = shift;

    foreach $arg ( @$args ) {

	if (! -e $arg) {
	    die "$arg is not a recognised filename\n";
	}

	$inputFile = $arg;
    }

    return($inputFile);
}


##################

sub check_and_rearrange_misc_fts(\@\$) {


    my ($i, $j, $entry_corrected);

    my $misc_fts = shift;
    my $entry = shift;

    $entry_corrected = 0;

    #print Dumper(\@$misc_fts);

    # remove any duplicate misc_features, adding the extra notes to the first misc_feature
    # with the same location
    for ($i=0; $i<@$misc_fts; $i++) {

	for ($j=($i+1); $j<@$misc_fts; $j++) {
	    
	    if (($$misc_fts[$i]{'misc_ft'} eq $$misc_fts[$j]{'misc_ft'}) && ($$misc_fts[$i]{'misc_ft'} ne "") && ($$misc_fts[$j]{'misc_ft'} ne "")) {

		$$misc_fts[$i]{'quals'} .= $$misc_fts[$j]{'quals'};
		$$misc_fts[$j]{'misc_ft'} = "";
		$$misc_fts[$j]{'quals'} = "";
		$entry_corrected = 1;
	    }
	}
    }


    # add remaining misc_features to the entry
    for ($i=0; $i<@$misc_fts; $i++) {
	
	if ($$misc_fts[$i]{'misc_ft'} ne "") {
	    $$entry .= $$misc_fts[$i]{'misc_ft'}.$$misc_fts[$i]{'quals'};
	}
    }

    return($entry_corrected);
}

#################
sub main(\@) {

    my ($input_file, $corrected_file, $line, $entry, @misc_fts);
    my ($entry_corrected_tally, $entry_corrected, $misc_ft_num);
    my ($in_misc_ft, $misc_fts_written, $fts_reached);

    my $args = shift;

    $input_file = get_args(@$args);
    $corrected_file = $input_file.".misc_fts_corrected";
 
    open(READ, "<$input_file") || die "Cannot read $input_file";
    open(WRITE, ">$corrected_file") || die "Cannot write $corrected_file.";

    $entry = "";
    @misc_fts = ();
    $entry_corrected = 0;
    $entry_corrected_tally = 0;
    $misc_ft_num = -1;
    $in_misc_ft = 0;
    $misc_fts_written = 0;
    $fts_reached = 0;

    while ($line = <READ>) {

	if ($line =~ /^FH/) {
	    $fts_reached = 1; 
	}


	if ($line =~ /^FT   misc_feature    \d+\.\.\d+/) {
	    $misc_ft_num++;
	    $in_misc_ft = 1;
	    $misc_fts[$misc_ft_num]{'misc_ft'} = $line;
	}
	elsif (($in_misc_ft) && ($line =~ /FT                   \//)) {
	    $misc_fts[$misc_ft_num]{'quals'} .= $line;
	}
	elsif (($line =~ /^XX/) && ($fts_reached)) {  # when feature section has finished
	    $in_misc_ft = 0;
	    $entry_corrected = check_and_rearrange_misc_fts(@misc_fts, $entry);
	    $entry .= $line;
	    $misc_fts_written = 1;
	}
	elsif ($line !~ /\/\//) {
	    $in_misc_ft = 0;
	    $entry .= $line;
	}
	elsif  ($line =~ /\/\//) {

	    $entry .= $line;
	    print WRITE $entry;
	    $entry = "";
	    @misc_fts = ();
	    $misc_ft_num = -1;
	    $fts_reached = 0;

	    if ($entry_corrected) {
		$entry_corrected_tally++;
	    }

	    $entry_corrected = 0;
	}
    }

    close(READ);
    close(WRITE);

    rename($corrected_file, $input_file);

    print "$input_file has been updated with $entry_corrected_tally corrected entries (where extra misc features have been removed)\n";
 
}


main(@ARGV);
