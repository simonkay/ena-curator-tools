#!/ebi/production/seqdb/embl/tools/bin/perl

#===============================================================================
# (C) EBI 2004 Nadeem Faruque
#
# Check EMBL/NCBI files for features with more than one instance of a given qualifier.
#
#  HISTORY
#  =======
#  Nadeem Faruque   08-NOV-2004 Created
#===============================================================================

use strict;

#---------------------------------------------------
# query for input
#-------------------------------------------------------------------------------

my $infile;
my $qualifierString;

if ( scalar(@ARGV) == 2 ) {
    $infile = $ARGV[0];
    $qualifierString = $ARGV[1];
#} elsif ( scalar(@ARGV) == 1 ) { # Would like to make it able to spot all duplicate qualifier values in an entry
#    $infile = $ARGV[0];          # probably need to make a separate script
#    $qualifierString = "";
} else {
    print "\nenter qualifier name: ";
    $qualifierString = chomp ($qualifierString = <STDIN>);
    print "\nenter file name: ";
    chomp( $infile = <STDIN> );
} 
$qualifierString = quotemeta($qualifierString);
print "Qualifier = $qualifierString\t file=$infile\n";

open( IN,  $infile )           || die "cannot open file $infile: $!";
my $qualifier = 0;
my $feature   = "";
my $errors    = 0;
#my %qualifierFirstLines;
while ( <IN> ) {
    my $line = $_;
    # ensure you are within a feature table
    if ($line =~ /^.{21}Location\/Qualifiers/ .. /^\/\//){
	if($line =~ /^((FT)|(  ))   [^ ]/){ # new key or end of FT
	    if($qualifier > 1){
		$errors++;
		print "###StartFeature###\n$feature###EndFeature#####\n";
	    }
	    $qualifier = 0;
	    $feature   = $line;
	}
	else{
	    $feature .= $line;
	    if($line =~ /^((FT)|(  )) {19}\/$qualifierString/){
		$qualifier++;
	    }
	}
    }
    elsif ($line =~ /^VERSION     ([^ ]*)/){
	print "Entry $1\n";}
    elsif ($line =~ /^SV   (.*)^/){
	print "Entry $1\n";}
}
if($qualifier > 1){
    $errors++;
    print "$feature\n";
}
close (IN);
print "\n$errors errors\n";
