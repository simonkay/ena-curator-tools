#!/ebi/production/seqdb/embl/tools/bin/perl -w
#  gi2ac
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/getFromNCBI.pl,v 1.1 2008/02/15 14:22:05 szilva Exp $
#
#  DESCRIPTION:
#
#  takes a GI and resolves it to an AC.version
#
#  MODIFICATION HISTORY:
#
#  10-04-2006 Nadeem Faruque   Created
# 
#===============================================================================

use strict;
use Getopt::Long;

use LWP::Simple;   
use LWP::UserAgent;
#select(STDERR); $| = 1; # make unbuffered
#select(STDOUT); $| = 1; # make unbuffered

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $ac2giUrl1 = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=Nucleotide&term=";
my $ac2giUrl2 = "[accn]&email=".$ENV{USER}."\@ebi.ac.uk&tool=collabBatchRetreival_ac2gi";

my $gi2gbUrl1 = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=Nucleotide&retmode=txt&rettype=gb&id=";
my $gi2gbUrl2 = "&email=".$ENV{USER}."\@ebi.ac.uk&tool=collabBatchRetreival_ac2gi";

my $userAgent  = LWP::UserAgent->new;

my $usage = "\n PURPOSE: Fetch entries from NCBI\n\n".
    " USAGE:   $0 [-f=file] [AC1 AC2 ...]\n".
    "          \n".
    "          where the file contains GI or AC\n".
    "          or AC\n".
    "   -h              shows this help text\n\n";

my $idFile = 0;
my @acs    = ();
my @gis    = ();

GetOptions("filename=s" => \$idFile);
foreach (@ARGV) {
    parseId ($_, \@acs, \@gis) || print STDERR "Cannot understand identifier $_\n";
}
# Read in any files
if ( (defined ($idFile)) &&
     (-f $idFile) ) {
    readFile ($idFile, \@acs, \@gis);
} 
if ((scalar @acs == 0) &&
    (scalar @gis == 0)) {
    die "No identifiers provided \n$usage\n";
}

if (scalar(@acs) > 0) {
    if (scalar(@acs) > 100) {
	waitUntil9EST();
    }
    
    acList2giList(\$userAgent, $idFile, \@acs, \@gis);
    undef(@acs);
    if (scalar @gis > 0) {
	print STDERR "Saving a new file of all gi's so you can use that instead if you need to rerun\n";
	my $giFile = $idFile;
	while (-e $giFile) {
	    $giFile .= ".gi";
	}
	open (OUTFILE, ">$giFile") || die "Could not write gis to $giFile\n";
	foreach my $gi (@gis) {
	    print OUTFILE "$gi\n";
	}
	close OUTFILE;
	print STDERR " Saved ".scalar @gis." gi numbers to $giFile\n";
    }
}

if (scalar @gis == 0) {
    die "No identifiers found\n";
}
if (scalar(@gis) > 100) {
    waitUntil9EST();
}
getGiEntries(\$userAgent, $idFile, \@gis);


# actually get entries
exit;

sub waitUntil9EST {
    my $hour = (localtime)[2];
    while(($hour < 2) ||
	  ($hour >= 10)) {
	print STDERR "Need to delay job until 9pm EST <http://eutils.ncbi.nlm.nih.gov/entrez/query/static/eutils_help.html#DemonstrationPrograms>\nWaiting ..."; # available between 21:00 and 5:00 EST == localtime 2:00-10:00
	sleep (60 * 15); # sleep for 15 minutes;
	print STDERR ".";
	$hour = (localtime)[2];
    }
}

sub readFile {
    my ($idFile, $acs, $gis) = @_;
    if (!(open (INFILE, "<$idFile"))) {
	print STDERR "Cannot open input file $idFile\n";
	return;
    }
    print STDERR "Taking ids from file $idFile\n"; 
    while(<INFILE>) {
	chomp;
	parseId ($_, $acs, $gis) || print STDERR "Cannot understand identifier $_ on line $.\n";
    }
    close INFILE;
    return;
}

sub parseId {
    my ($id, $acs, $gis) = @_;
    if ($id =~ /^\s*([0-9]+)\s*$/) {
	push (@$gis, $1);
	return 1;
    } elsif ($id =~ /^\s*([A-Z]{1,4}\d+)(\.\d+)?$/i) {
	push (@$acs, $1);
	return 1;
    } else {
	return 0;
    }
}


sub acList2giList {
    my ($userAgent, $filename, $acs, $gis) = @_;
    my @acsUnresolved_NoResult = (); # should use a anonymous hash to hold the filename extension + list of ACs
    my @acsUnresolved_Result0  = ();
    my @acsUnresolved_MultiResult = ();
    my @acsUnresolved_Else     = ();
    foreach my $ac (@$acs) {
	my $request    = HTTP::Request->new( GET => $ac2giUrl1.$ac.$ac2giUrl2 );
	my $urlDataRaw = $$userAgent->request( $request );
	my $urlData    = $urlDataRaw->as_string;
	if ( $urlData =~ /Server Error/ ) {
	    print STDERR $ac2giUrl1.$ac.$ac2giUrl2."\n gave the error \n$urlData\n";
	} elsif ($urlData =~ /<ERROR>No result<\/ERROR>/s) {
	    print STDERR "! AC had no result $ac\n";
	    push (@acsUnresolved_NoResult, $ac);
	} elsif ($urlData =~ /<Count>0<\/Count>/i) {
	    print STDERR "! AC had result of 0 GIs for $ac\n";
	    push (@acsUnresolved_Result0, $ac);
	}
	elsif ($urlData =~ /<Count>1<\/Count>/i) {
	    if ($urlData =~ /<Id>(\d+)<\/Id>/i) {
		push (@$gis, $1);
	    }
	    else {
		print STDERR "! AC->GI ambiguity for $ac\n";
		push (@acsUnresolved_MultiResult, $ac);
	    }
	} else {
	    print STDERR "!! Unknown response for ".$ac2giUrl1.$ac.$ac2giUrl2.":\n" .
		"$urlData\n---------------------------------------------\n";
	    push (@acsUnresolved_Else, $ac);
	}
# Have to space out requests by 3 secs, see http://eutils.ncbi.nlm.nih.gov/entrez/query/static/eutils_help.html#DemonstrationPrograms
	sleep 3; 
    }
    if (scalar(@acsUnresolved_NoResult)) {
	open (OUT, ">$filename.NoGI.NoResult")  || die "Could not open $filename.NoGI.NoResult for writing\n";
	foreach (@acsUnresolved_NoResult) {
	    print OUT "$_\n";
	}
	close OUT;
	print STDERR "wrote unresolved ACs to $filename.NoGI.NoResult\n";
    }
    if (scalar(@acsUnresolved_Result0)) {
	open (OUT, ">$filename.NoGI.Result0")  || die "Could not open $filename.NoGI.Result0 for writing\n";
	foreach (@acsUnresolved_Result0) {
	    print OUT "$_\n";
	}
	close OUT;
	print STDERR "wrote unresolved ACs to $filename.NoGI.Result0\n";
    }
    if (scalar(@acsUnresolved_MultiResult)) {
	open (OUT, ">$filename.NoGI.MultiResult")  || die "Could not open $filename.NoGI.MultiResult for writing\n";
	foreach (@acsUnresolved_MultiResult) {
	    print OUT "$_\n";
	}
	close OUT;
	print STDERR "wrote unresolved ACs to $filename.NoGI.MultiResult\n";
    }
    if (scalar(@acsUnresolved_Else)) {
	open (OUT, ">$filename.NoGI.Else")  || die "Could not open $filename.NoGI.Else for writing\n";
	foreach (@acsUnresolved_Else) {
	    print OUT "$_\n";
	}
	close OUT;
	print STDERR "wrote unresolved ACs to $filename.NoGI.Else\n";
    }
	    
# step through unresolved and put them in files 
    return;
}

sub getGiEntries {
    my ($userAgent, $filename, $gis) = @_;
    while (-e $filename) {
	$filename .= ".ncbi";
    }
    open (NCBIOUTFILE, ">$filename") || die "Could not open $filename for writing the entries to\n";
    print "writing NCBI entries to $filename\n";
    open (NCBICONOUTFILE, ">$filename.con") || die "Could not open $filename.con for writing the entries to\n";
    print "writing NCBI CON entries to $filename.con\n";
    foreach my $gi (@$gis) {
	if(scalar(@$gis) > 100) {
	    waitUntil9EST(); # in case this fetching goes on too long
	}
	my $request    = HTTP::Request->new( GET => $gi2gbUrl1.$gi.$gi2gbUrl2 );
	my $urlDataRaw = $$userAgent->request( $request );
	my $urlData    = $urlDataRaw->as_string;
	if ( $urlData =~ /Server Error/m ) {
	    print STDERR $gi2gbUrl1.$gi.$gi2gbUrl2."\n gave the error \n$urlData\n";
	} else {
	    my @lines = split(/[\n\r]+/, $urlData);
	    my $isCon = 0;
	    foreach my $line (@lines) {
		if ($line =~ /^LOCUS       / .. $line =~ /^\/\/\s*$/) {
		    if ($line =~ /^LOCUS .* CON .*$/) {
			$isCon = 1;
		    }
		    if ($isCon) {
			print NCBICONOUTFILE $line."\n";
		    } else {
			print NCBIOUTFILE $line."\n";
		    }
		} 
	    }
	}
# Have to space out requests by 3 secs, see http://eutils.ncbi.nlm.nih.gov/entrez/query/static/eutils_help.html#DemonstrationPrograms
	sleep 3; 
    }
    close NCBIOUTFILE;
    close NCBICONOUTFILE;
    print STDERR scalar(@$gis)." written to $filename\n";
    return;
}


