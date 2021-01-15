#!/ebi/production/seqdb/embl/tools/bin/perl -w


use warnings;
use strict;
use Utils;
use Data::Dumper;

my $PATTERN_FILE = '../pattern_matching/patterns';

my ( $patent_data_file ) = @ARGV;

if (! $patent_data_file ) {
    die "USAGE: $0 <file name>\n"
	. " Translitterate extended ASCII characters plus patterns in ../pattern_matching/patterns and swaps them for the substitutions defined in the 'patterns' file.\n\n";
}

my %subs = (
	    chr(0x80) => 'C',
	    chr(0x81) => 'ue',
	    chr(0x82) => 'e',
	    chr(0x83) => 'a', 
	    chr(0x84) => 'ae',
	    chr(0x85) => 'a',
	    chr(0x86) => 'aa',
	    chr(0x87) => 'c',
	    chr(0x88) => 'e', 
	    chr(0x89) => 'ee',
	    chr(0x8A) => 'e',
	    chr(0x8B) => 'ie',
	    chr(0x8C) => 'i',
	    chr(0x8D) => 'i', 
	    chr(0x8E) => 'AE',
	    chr(0x8F) => 'AA',
	    chr(0x90) => 'E',
	    chr(0x91) => 'ae',
	    chr(0x92) => 'AE', 
	    chr(0x93) => 'o', 
	    chr(0x94) => 'oe',
	    chr(0x95) => 'o',
	    chr(0x96) => 'u',
	    chr(0x97) => 'u',
	    chr(0x98) => 'ye', 
	    chr(0x99) => 'OE', 
	    chr(0x9A) => 'UE',
	    chr(0xA0) => 'a',
	    chr(0xA1) => 'i',
	    chr(0xA2) => 'o',
	    chr(0xA3) => 'u',
	    chr(0xA4) => 'n',
	    chr(0xA5) => 'N');

open( PATTERN_FILE, "<$PATTERN_FILE" );
my ( $patt, $new_patt );

while (<PATTERN_FILE>) {

    ( $patt, $new_patt ) = split( /===+/ );

    if ( $patt ) {
	if ($new_patt) {
	    chomp($new_patt);
	}
	chomp($patt);

	$subs{$patt} = $new_patt;
    }
}
close(PATTERN_FILE);



open( DATA_FILE, "<$patent_data_file" );
my ($line, $pattern, $substitution);

while ($line = <DATA_FILE> ) {
	    
    while ( ( $pattern, $substitution ) = each( %subs ) ) {
	
	$line =~ s/$pattern/$substitution/;
    }

    print $line;
}

close(DATA_FILE);
