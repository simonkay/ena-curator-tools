#!/ebi/production/seqdb/embl/tools/bin/perl -w
#  gi2ac
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/gi2ac.pl,v 1.1 2007/09/04 12:53:36 faruque Exp $
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
use LWP::Simple;   
use LWP::UserAgent;
select(STDERR); $| = 1; # make unbuffered
select(STDOUT); $| = 1; # make unbuffered

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Accepts GI numbers and returns DB:AC.version\n\n".
    " USAGE:   $0\n".
    "          GI\n\n".
    "   -h              shows this help text\n\n";

my $gi = 0;
if ((@ARGV == 1 ) && ( $ARGV[0] =~ /^(\d+)$/)){
    $gi =$1;
}
else{
    die "$usage";
}

sub gi2ac{
    my $gi = shift;
    my $type = shift;
    my $ac;
    my $ver;
    my $db;
    my $gi2acUrl = "";
    if ($type eq "n"){
	$gi2acUrl = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=Nucleotide&id=";
	$db = "INSDC";
    }
    elsif ($type eq "p"){
	$gi2acUrl = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=Protein&id=";
	$db = "INSDC"; # need to look into this
    }
    my $userAgent  = LWP::UserAgent->new;
    my $request    = HTTP::Request->new( GET => $gi2acUrl.$gi );
    my $urlDataRaw = $userAgent->request( $request );
    my $urlData    = $urlDataRaw->as_string;
    if ( $urlData =~ /Server Error/ ) {
	print STDERR $gi2acUrl.$gi."\n gave the error \n$urlData\n";
        return "UNKNOWN";
    }
    if ($urlData =~ / is not valid for db Nucleotide/){
	return gi2ac($gi,"p");
    }
    #                                                            $1       $2     $3
    if ( $urlData =~ /<Item Name="Extra" Type="String">gi\|$gi\|([^|]+)\|(\w+)\.(\d)/s ) {
	$db  = $1;
	$ac  = $2;
	$ver = $3;
	printf STDERR "NCBI answered:%s|%s.%d\n", $1, $2, $3;
	if ($db eq "ref"){
	    $db = "RefSeq";
	}
	if ($db eq "dbj"){
	    $db = "INSDC";
	}
	if ($db eq "gb"){
	    $db = "INSDC";
	}
	return sprintf("%s:%s.%d", $db, $ac, $ver);
    }
    #                                                                  $1       $2
    elsif ( $urlData =~ /<Item Name="Extra" Type="String">gi\|$gi\|([^|]+)\|\|([A-Z0-9_]+)\[$gi\]/s ) {
	$db  = $1;
	$ac  = $2;
	printf STDERR "NCBI answered:%s|%s\n", $1, $2;
	return sprintf("%s:%s", $db, $ac);
    }
    #                                                                  $1       $2          $3
    elsif ( $urlData =~ /<Item Name="Extra" Type="String">gi\|$gi\|([^|]+)\|([A-Z0-9_]+)\|([A-Z0-9_]+)\[$gi\]/s ) {
	$db  = $1;
	$ac  = $2;
	if ($db eq "sp"){
	    $db = "UniProtKB";
	}
	printf STDERR "NCBI answered:%s|%s\n", $1, $2;
	return sprintf("%s:%s", $db, $ac);
    }
    else{
	print STDERR $gi2acUrl.$gi."\n gave a reply I had not anticipated reply\n$urlData\n";
        return "UNKNOWN";
    }
    #http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=Nucleotide&id=572829134
    # http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Search&db=Nucleotide&term=AAC72193[accn]&doptcmdl=Brief

}

print gi2ac($gi,"n")."\n";
exit();
