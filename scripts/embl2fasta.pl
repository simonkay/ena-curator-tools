#!/ebi/production/seqdb/embl/tools/bin/perl -w

# embl2fasta.pl: converts EMBL flat file to FastA sequence 
# Author: Peter Sterk
# Usage: embl2fasta.pl inputfile  
# File extension of output file = .fasta

use strict;

unless ( $ARGV[0] ) {
    die ("Usage: embl2fasta.pl <inputfile>. Aborting ...\n");
}

my $in_no_ext = $ARGV[0];
$in_no_ext =~ s/\..*//;     #remove extension
my $de = "";

open OUT, ">${in_no_ext}.fasta" or die "Can't create output file: $!";
read_ff($ARGV[0]);
close OUT;
print "\nEMBL2FASTA output written to ${in_no_ext}.fasta\n\n";

sub read_ff {
    my $in = $_[0];
    my $ac = "";

    open FF, "$in" or die "Can't open input file: $!";
    while (<FF>) {
	if (/^AC   /) {
	    chomp($ac = $_);
	    $ac =~ s/^AC   (\w{1,2}\d{5,6})\;.*/$1/;
	    print OUT ">$ac";
	}
	if (/^DE  /) {
	    chomp;
	    s/^DE  //;
	    $de .= $_;
	}

	if (/^SQ   Sequence / .. /^\/\//) {
	    if (/^SQ   /) {
		$de = substr ($de, 0, 69);
		print OUT "$de\n";
		next;
	    }
            last if /^\/\//;
	    s/\d//g;
	    s/\s//g;
	    print OUT "$_\n";
	}
    }
    close FF;
}
