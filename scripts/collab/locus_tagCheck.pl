#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# (C) EBI 2006 Nadeem Faruque
#
# Check EMBL files for features with duplicate feature-value combinations
#
#  HISTORY
#  =======
#  Nadeem Faruque   27-APR-2006 Created
#                               only works on non-wrapped qualifier values files
#===============================================================================

use strict;

#---------------------------------------------------
# query for input
#-------------------------------------------------------------------------------

my $infile = "infile goes here";
my $verbose = 0;
my $stringent = 0;
my $usage =
    "\n PURPOSE: Check for potential inconsistent use of locus_tag and gene.\n\n"
    . " USAGE:   $0 -v <filename>\n"
    . "          v[e]rbose]   gives output\n"
    . "          filename     name of the file to be checked\n\n";

for ( my $i = 0 ; $i < @ARGV ; ++$i ) {
    if ( $ARGV[$i] =~ /^\-/ ) {
        if ( $ARGV[$i] =~ /^\-v(erbose)?$/ ) {
	    print "Verbose mode\n";
	    $verbose = 1;
	}
	elsif($ARGV[$i] =~ /^\-s(tringent)/){
	    $stringent = 1;
	}	    
	else{
	    die "flag $ARGV[$i] is not recognise\n$usage";
	}
    }
    else{
	$infile = $ARGV[$i];
    }
}

while (!(-e $infile)) {
    print "\nenter file name (Q to exit): ";
    chomp( $infile = <STDIN> );
    if ($infile =~ /^q$/i){
	exit;
    }
} 

my %conflicts; # global just to make this subroutine readable
sub checkCombinations($$\@\%\%){
    my $featureNumber  = shift;
    my $latestLocusTag = shift;
    my $latestGenesList= shift;
    my $locusTagsHash  = shift;
    my $genesHash      = shift;
    my $latestGeneString = "";
    if(!(defined($latestLocusTag))){
	$latestLocusTag = "";
    }
    if(($latestLocusTag eq "") && (!(defined(@$latestGenesList)))){
	return;
    }
    # make latest gene list into tab delimited string to ease comparison.
    if (defined(@$latestGenesList)){
	$latestGeneString = join("\t", sort @$latestGenesList);
    }
    
    $verbose && printf " Checking FT %d:before line%d:locus_tag=\"%s\"\t gene(s)=\"%s\"\n",$featureNumber,$.,$latestLocusTag,$latestGeneString;
    
    if ($latestLocusTag ne ""){
	# Has the locus tag been seen before?
	if (defined($$locusTagsHash{$latestLocusTag})){
#	    print "Locus_tag $latestLocusTag already seen\n";##
	    if($$locusTagsHash{$latestLocusTag} ne $latestGeneString){
		my $error = sprintf("ERROR: locus_tag \"%s\" had gene(s) \"%s\" but now \"%s\"\n", 
				    $latestLocusTag,
				    $$locusTagsHash{$latestLocusTag},
				    $latestGeneString);
		if(defined($conflicts{$error})){
		    $conflicts{$error} .= ", FT#".$featureNumber." (feature ends on line $.)";
		}
		else{
		    $conflicts{$error} = "FT#".$featureNumber." (feature ends on line $.)";
		}
	    }
	}
	else{
	    $$locusTagsHash{$latestLocusTag} = $latestGeneString;
	}
    }
    if (defined(@$latestGenesList)){
	foreach my $gene(@$latestGenesList){
	    if (defined($$genesHash{$gene})){
#		print "gene $gene already seen\n";##
		if ($stringent && ($$genesHash{$gene} ne $latestLocusTag)){
		    my $error = sprintf("WARNING: gene \"%s\" had locus_tag \"%s\" but now \"%s\"\n", 
					$gene,
					$$genesHash{$gene},
					$latestLocusTag);
		    if(defined($conflicts{$error})){
			$conflicts{$error} .= ", FT#".$featureNumber;
		    }
		    else{
			$conflicts{$error} = "FT#".$featureNumber;
		    }
		}
	    }
	    else{
		$$genesHash{$gene} = $latestLocusTag;
	    }
	}
    }
}

my %genes;
my %locusTags;
my $featureNumber = 0;
my $entryStart;
my @latestGenes;
my $latestLocusTag;
my $sequenceNumber = 0;
open( IN,  $infile )           || die "cannot open file $infile: $!";
while ( my $line = <IN> ) {
    #read until the ID
    if ($line =~ /^ID   /){
	$verbose && print "Starting entry at line $.\n";
	my $ac = "";
	undef(%genes);
	undef(%locusTags);
	undef(%conflicts);
	$featureNumber = 0;
	$entryStart = $.;
	
	#read until the AC
      GETAC: while (<IN>){ 
	  if ($_ =~ /^AC/){
	      $ac = $1;
	      print "\n\nAC:$ac at line $entryStart\n";
	      last GETAC;
	  }
	  if ($_ =~ /^AC[^ ]* +([A-Z0-9]+)/){
	      $ac = $1;
	  } else {
	      $ac = "unassigned".++$sequenceNumber;
	  }
	      print "\n\nAC:$ac at line $entryStart\n";
	      last GETAC;
      }
      GETREST: while (<IN>){
	  my $line = $_;
	  if ($line =~ /^\/\//){ 
	      $verbose && print "End of entry checking combinations for ".scalar(keys %locusTags)." locus tags\n";
	      checkCombinations($featureNumber, $latestLocusTag,  @latestGenes, %locusTags, %genes);
	      #output results
	      foreach my $error (sort keys %conflicts){
		  print $error." in ".join("", $conflicts{$error})."\n";
	      }
	      undef($entryStart);
	      last GETREST;
	  }
	  if ($line =~ /^.{21}Location\/Qualifiers/ .. /^SQ/){
	      if($line =~ /^((FT)|(  )) {3}[^ ]/){ # new key or end of FT
		  if($featureNumber > 0){
		      checkCombinations($featureNumber, $latestLocusTag,  @latestGenes, %locusTags, %genes);
		  }
		  
		  $featureNumber++;
		  undef(@latestGenes);
		  undef($latestLocusTag);
	      }
	      elsif($line =~ /^[F ][T ] {19}\/gene=\"([^\"]+)\"/){
		  push (@latestGenes,$1);
	      }
	      elsif($line =~ /^[F ][T ] {19}\/locus_tag=\"([^\"]+)\"/){
		  if(defined($latestLocusTag)){
		      printf "ERROR: Feature %d has locus_tag \"%s\" and \"%s\"\n", $featureNumber, $latestLocusTag, $1;
		  }
		  else{
		      $latestLocusTag = $1;
		  }
	      }
	  }
      }
    }
}
close IN;


