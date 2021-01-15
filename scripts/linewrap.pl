#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# (C) EBI 2004 Nadeem Faruque
#
# Wraps EMBL files to 80 characters (NB exclused ID, SQ and sequence lines.
#
#  HISTORY
#  =======
#  Nadeem Faruque   16-NOV-2004 Created
#  Nadeem Faruque   25-JAN-2006 enhanced to deal with join/order and 
#                               report unwrapped lines
#===============================================================================

use strict;
use Text::Wrap;
$Text::Wrap::columns = 80; # text wrap at 80 columns
$Text::Wrap::unexpand = 0; # don't use tabs when wrapping
#local($Text::Wrap::break) = '\d'; 
my $usage = "\n PURPOSE: Wraps an embl flatfile to 80 characters and sends output to stdout\n\n".
    " USAGE:   $0  <sourcefile>\n\n";

my $infile;
if ( @ARGV ) {
    $infile = $ARGV[0];
} else {
    print $usage;
    exit();
#"\nenter file name: ";
#    chomp( $infile = <STDIN> );
} 

open( IN,  $infile )           || die "cannot open EMBL file $infile: $!";
while ( <IN> ) {
    my $latestLine = $_;
    if ((length($latestLine) <= 81) or 
	($latestLine =~ /(^SQ)|(^ID)|(^  )/)){
	print $latestLine;
	next;
    }
    else{
	my $leader = "";
        # wrapped line start is either 21 char (in the FT) or 5
	if ($latestLine =~ /^FT   /){
	    $leader = "FT                   ";}
	else{
	    $leader = substr($latestLine, 0, 5);}

# The wrap function will fail with lines such as 
#FT   misc_feature    join(317..469,1..333333333333,1..333333333333,1..333333,1..333333333333,1..333333)
#->
#FT   misc_feature
#FT                   join(317..469,1..333333333333,1..333333333333,1..333
#FT                   333,1..333333333333,1..333333)
# so we pretreat them with extra spaces ...
	if ($latestLine =~ /^FT   [^ ].+(order)|(join)/){
	    $latestLine =~ s/, */, /g;}

	$latestLine = wrap ("", $leader, $latestLine);

# ... then remove the extra spaces
	if ($latestLine =~ /^FT   [^ ].+(order)|(join)/){
	    $latestLine =~ s/, */,/g;}


# FT                   /product="2,5-diamino-6-hydroxy-4-(5-phosphoribosylamino)pyrimidine
# -> 
# FT                   /product="2,5-diamino-6-hydroxy-4-(5-phosphoribosylamino)p
# FT                   yrimidine
# :-(
        #unfortunately this may find lines it won't break
	if ($latestLine =~ /^[^\n\r\f]{81}/s){
	    print STDERR "longline\n".$latestLine;
	}
#	if ($latestLine =~ /^.{81}/m){
#	    print STDERR "s long\n".$latestLine;
#	}
	$latestLine =~ s/^FT                  \n//;
	print $latestLine;
    }
}
close (IN);
