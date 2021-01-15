#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/remove_embedded_double_quotes.pl,v 1.3 2008/12/12 16:37:59 gemmah Exp $
#
#####################################################################
#
# Simple script to quick-fix lack of organism qualifier in patent entries.
# FT    /organism="synthetic construct" is added by default.
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

    my ($input_file, $corrected_file, $line, $entry, $num_quotes, $i);
    my ($entry_corrected_tally, $entry_corrected, $rebuilt_line);

    my $args = shift;

    $input_file = get_args(@$args);
    $corrected_file = $input_file.".double_quotes_corrected";
 
    open(READ, "<$input_file") || die "Cannot read $input_file";
    open(WRITE, ">$corrected_file") || die "Cannot write $corrected_file.";

    $entry = "";
    %misc_fts = ();
    $entry_corrected = 0;
    $entry_corrected_tally = 0;

    while ($line = <READ>) {


	$num_quotes = ($line =~ tr/"//); #"
#	print "line = $line ($num_quotes)\n";


	if ($num_quotes > 2) {

	    #print "num_quotes = $num_quotes\n";

	    @line_parts = split('"', $line);

	    #print "line = $line\nscalar(line_parts) = ".scalar(@line_parts). "\n";

	    $rebuilt_line = $line_parts[0].'"';

	    for ($i=1; $i<@line_parts; $i++) {
		#$line_parts[$i] =~ s/"//g;
		$rebuilt_line .= $line_parts[$i];
	    }

	    $rebuilt_line =~ s/\n$//;
	    $rebuilt_line .= '"'."\n";

	    $entry .= $rebuilt_line;
	    $entry_corrected = 1;
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

    #rename($corrected_file, $input_file);

    print "$input_file has been updated with $entry_corrected_tally corrected entries (where unquoted double quotes embedded in a field have been removed)\n";
 
}


main(@ARGV);
