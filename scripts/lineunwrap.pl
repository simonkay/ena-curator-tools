#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# (C) EBI 2005 Nadeem Faruque
#
# script to make 2 embl files more comparable
#
# Details:-
#  Unraps EMBL files to 80 characters (NB excludes sequence and some 
#    important line types)
#  Sorts qualifiers within each feature
#  Excludes some qualifier lines
#
#  HISTORY
#  =======
#  Nadeem Faruque   04-MAR-2005 Created
#===============================================================================

use strict;

sub addQualifier(\$\@){
    my $lineRead     = shift;
    my $featureLines = shift;

    if(($$lineRead !~ m|^FT                   /protein_id=|) &&
       ($$lineRead !~ m|^FT                   /translation=|) &&
       ($$lineRead !~ m|^FT                   /transl_table=|) &&
       ($$lineRead !~ m|^FT                   /db_xref=|)){
	$$lineRead =~ s/ {[^}]+}"$/"/; # remove _GR evidence
	push (@$featureLines, $$lineRead."\n");
    }
}
sub outputFeature(\@){
    my $featureLines = shift;
   print sort {
	if(substr($a, 5, 1) ne " "){
	    return -1;}
	if(substr($b, 5, 1) ne " "){
	    return +1;}
	return $a cmp $b;
    } @$featureLines;
    undef(@$featureLines);
}

my $infile;
if ( @ARGV ) {
    $infile = $ARGV[0];
} else {
    print "\nenter file name: ";
    chomp( $infile = <STDIN> );
} 

open( IN,  $infile )           || die "cannot open file $infile: $!";

my $prevPrefix = "--";
my $lineRead   = "";
my @featureLines;
while ( <IN> ) {
    chomp;
    my $latestLine = $_;
    my $linePrefix = "";
    if (length($latestLine) < 2){
	$linePrefix = $latestLine;}
    else{
	$linePrefix = substr($latestLine, 0, 2);}

    if($linePrefix eq "FT"){
	# new qualifier - NB can't easily spot new qualifiers
	if(($latestLine =~ m|^FT                   /[a-zA-Z0-9_]+|) &&
	   (($latestLine =~ m|^FT                   /[a-zA-Z0-9_]+=|) ||
	    ($latestLine =~ m|^FT                   /[a-zA-Z0-9_]+$|))){
	    addQualifier($lineRead, @featureLines);
	    $lineRead = $latestLine;	    
	}
	# new feature
	elsif($latestLine =~ /^FT   [^ ]/){
	    if($prevPrefix eq "FT"){
		addQualifier($lineRead, @featureLines);
		outputFeature(@featureLines);}
	    else{
		print $lineRead."\n";}
	    $lineRead  = $latestLine;
	}
        # more line data
	else{
	    if($latestLine =~ /..   +(.*)/){
		$lineRead  .= " ".$1;}
	}
    }
    else{
	# just left the feature table
	if($prevPrefix eq "FT"){
	    addQualifier($lineRead, @featureLines);
	    outputFeature(@featureLines);
	    $lineRead  = $latestLine;
	}
	# new linetype
	elsif($prevPrefix ne $linePrefix){
	    print $lineRead."\n";
	    $lineRead  = $latestLine;
	} 
        # more line data
	else{
	    if($latestLine =~ /..   +(.*)/){
		$lineRead  .= " ".$1;}
	}
    }

    $lineRead =~ s/\s*$//;
    
    if(($latestLine =~ /^RL   Submitted/) ||
       ($linePrefix eq "DT") ||
       ($linePrefix eq "RX") ||
       ($linePrefix eq "DR") ||
       ($linePrefix eq "SV") ||
       ($linePrefix eq "DT") ||
       ($linePrefix eq "AS") ||
       ($linePrefix eq "FH") ||
       ($linePrefix eq "CC") ||
       ($linePrefix eq "  ")){
	$prevPrefix = "--";}
    else{
	$prevPrefix = $linePrefix;}
    
}
close (IN);
print $lineRead."\n"; ###################### 
