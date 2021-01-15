#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/remove_extra_misc_fts.pl,v 1.2 2008/12/19 14:33:31 gemmah Exp $
#
#####################################################################
#
# This scripts removes extra misc_features which share he same location 
# ONLY if they are next to the duplicate misc_feature.  If they are 
# separated from the duplicate misc_feature by other features, use 
# remove_extra_misc_fts2.pl
#
# Author: Gemma Hoad
#
#####################################################################

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


#################
sub main(\@) {

    my ($input_file, $corrected_file, $line, $entry, %misc_fts);
    my ($misc_ft, $entry_corrected_tally, $entry_corrected);

    my $args = shift;

    $input_file = get_args(@$args);
    $corrected_file = $input_file.".misc_fts_corrected";
 
    open(READ, "<$input_file") || die "Cannot read $input_file";
    open(WRITE, ">$corrected_file") || die "Cannot write $corrected_file.";

    $entry = "";
    %misc_fts = ();
    $entry_corrected = 0;
    $entry_corrected_tally = 0;

    while ($line = <READ>) {

	if ($line =~ /^FT   misc_feature    (\d+)\.\.(\d+)/) {

	    $misc_ft = $1.'..'.$2;

            # don't add misc feature to entry if it's already been caught
	    if (!defined ($misc_fts{$misc_ft})) {
		$entry .= $line;
		$misc_fts{$misc_ft} = 1;
	    }
	    else {
		$entry_corrected = 1;
	    }
	}
	elsif ($line !~ /\/\//) {
	    $entry .= $line;
	}
	else {
            # line = "//"

	    $entry .= $line;
	    print WRITE $entry;
	    $entry = "";
	    %misc_fts = ();

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
