#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;
use warnings;

my $filename = "/net/isilon3/production/panda/data/ERA/tsv/submissionaccounts.tsv";
my $search_string;
my @lines= ();
my $i;
my $answer;

print "\nPlease provide search term now:";
$search_string= <STDIN>;
chomp( $search_string );

open(INFILE, "<$filename" ) or die("Couldn't open file $filename:
$!\n" );
@lines = <INFILE>;
close( INFILE );


for $i ( 0 .. $#lines ){
    chomp( $lines[$i] );
    if( $lines[$i] =~ /$search_string/i) {
	print( "Line $i - '$lines[$i]'\n" );
    }
}
