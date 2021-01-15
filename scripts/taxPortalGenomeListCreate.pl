#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/taxPortalGenomeListCreate.pl,v 1.4 2011/11/29 16:33:38 xin Exp $
#
# (C) EBI 2010
#
# taxPortalGenomeListCreate.pl
# use genomes table to make tax portal files
#
#===============================================================================

use strict;
use DBI;
use ENAdb;

my $outDir = "/ebi/production/seqdb/embl/data/taxportal";
my $quiet = 0;
my $login;

foreach my $arg (@ARGV) {
    if ($arg =~ /\-q(uiet)?/) {
	$quiet = 1;
    } elsif ($arg =~ /\/\@[a-zA-Z0-9]+/) {
	$login = $arg;
    }
}

sub getOrg2AcFromDb($\%$) {
    my $dbh = shift;
    my $rh_org2Ac = shift;
    my $categories = shift;
    $quiet || print STDERR "Getting genomes of categories $categories (: shows organism when first seen, else .)\n";
    my $sth = $dbh->prepare("SELECT so.organism || decode(fq.text, NULL, '', '; ' || fq.text), g.primaryacc#
                               FROM genome_seq g
                               JOIN sourcefeature so ON (g.seqid = so.bioseqid
                                                     AND so.primary_source = 'Y')
                    LEFT OUTER JOIN feature_qualifiers fq ON (so.featid = fq.featid
                                                          AND fq.fqualid = 47)
                              WHERE g.category IN $categories")
	|| die "database error: $DBI::errstr\n ";
    $sth->execute()
	|| die "database error: $DBI::errstr\n ";
    while (my ($org, $ac) = $sth->fetchrow_array) {
	if (exists(${$rh_org2Ac}{$org})) {
	    $quiet || print STDERR ".";
	    ${$rh_org2Ac}{$org} .= ',' . $ac;
	} else {
	    $quiet || print STDERR ":";
	    ${$rh_org2Ac}{$org} = $ac;
	}
    }
    $sth->finish();
    $quiet || print STDERR "\nCompleted\n";
    return;
}

sub printGenomeList($\%){
    my $listName = shift;
    my $rh_org2Ac = shift;

    my $filename_temp = "$outDir/.$listName";
    my $filename      = "$outDir/$listName";
    $quiet || print STDERR "Writing to $filename_temp\n";
    open(my $out,">$filename_temp") 
	or die "Can't create outfile $filename_temp: $!";
    foreach my $org (sort keys %{$rh_org2Ac}) {
	printf $out "\"%s\",<startlob>%s <endlob>\n", $org,${$rh_org2Ac}{$org};
    }
    close $out 
	or die "Can't close outfile $filename_temp: $!";
    $quiet || print STDERR "Replacing $filename\n";
    rename( $filename_temp, $filename) 
	or die "Can't rename $filename_temp to $filename: $!";
    return;
}
    
sub main($) {
    my $database = shift;
    
    if (!(defined($database))) {
	$database = '/@enapro';
    }
    my %attr   = ( PrintError => 0,
		   RaiseError => 0,
		   AutoCommit => 0 );
    
    $quiet || print STDERR "Connecting to database $database\n";
    my $dbh = ENAdb::dbconnect($database,%attr)
	|| die "Can't connect to database: $DBI::errstr";

    my %types = ( 'genomic_replicons' => '(2,4,5,6,8,12,13)',
		  'peripheral_replicons' => '(11,10,9,7,3)');
    foreach my $type (keys %types) {
	my %org2Ac;
	getOrg2AcFromDb($dbh, %org2Ac, $types{$type});
	printGenomeList($type, %org2Ac);
    }
    $dbh->disconnect;
    $quiet || print STDERR "Completed\n";
}

#----------------------------------------------------------------------------------

main($login);



