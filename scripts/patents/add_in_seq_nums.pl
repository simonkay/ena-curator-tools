#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/add_in_seq_nums.pl,v 1.1 2009/01/19 15:50:04 gemmah Exp $
#
#
#===============================================================================

use strict;



#---------------------------------------------------------------

sub main($) {

    my ($line, $ac_line_start, $ac_line_end, $seqlen, $ac, $newfile);
    my ($ac_line_seqlen, $rest_of_entry, $corrected_entries, $whole_ac_line);

    my $emblfile = shift;

    if (!defined($emblfile)) {
	die "This script requires the input of an embl file to add sequence length to the ID line\n";
    }

    open(EMBLFILE, "<$emblfile") || die "Cannot open $emblfile\n";

    $newfile = $emblfile.".withseqnums";
    open(WRITEEMBLFILE, ">$newfile") || die "Cannot open $newfile\n";


    $corrected_entries = 0;

    while ($line = <EMBLFILE>) {

	if ($line =~ /^\/\//) {
	    if ($ac_line_seqlen == 0) {
		print WRITEEMBLFILE $ac_line_start.$seqlen.$ac_line_end;
		print "Fixing $ac\n";
		$corrected_entries++;
	    }
	    else {
		print WRITEEMBLFILE $whole_ac_line;
	    }

	    print WRITEEMBLFILE $rest_of_entry.$line;
	    $rest_of_entry = "";
	}
	elsif ($line =~ /^((ID   ([A-Z]{2}\d+); ([^;]+;){5} )(\d+)( (BP|AA)\.\n))/) {

	    $whole_ac_line = $1;
	    $ac_line_start = $2;
	    $ac = $3;
	    $ac_line_seqlen = $5;
	    $ac_line_end = $6;
	}
	elsif ($line =~ /^FT   source          1\.\.(\d+)/) {
	    $seqlen = $1;
	    $rest_of_entry .= $line;
	}
	else {
	    $rest_of_entry .= $line;
	}
    }


    close(EMBLFILE);
    close(WRITEEMBLFILE);


    print "\n$corrected_entries entries have been corrected inside $newfile\n";
}

main($ARGV[0]);
