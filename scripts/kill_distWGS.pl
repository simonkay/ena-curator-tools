#!/ebi/production/seqdb/embl/tools/bin/perl
use strict;
use Wgs;
use Putff;
use DBI;
if (@ARGV != 2){
    print "USAGE $0 CONN PREFIX\n"
	."         CONN = database eg /\@enapro\n"
	."         PREFIX = WGS set prefix eg CAAA02 that is the latest\n";
    die();
}
my $conn_str = lc($ARGV[0]);
my $prefix = $ARGV[1];
my $wgsset = "";
my $wgsver;
if (($conn_str ne "/\@enapro") && ($conn_str ne "/\@devt1")){
    print "Database connection $conn_str not recognised; should be /\@enapro or \@devt1\n";
    die();
}
my $dbh = DBI->connect ('dbi:Oracle:', $conn_str, '',
			{AutoCommit => 0,
			 PrintError => 1,
			 RaiseError => 1} );

if ($prefix =~ /([A-Z][A-Z][A-Z][A-Z])(\d\d)/){
    $wgsset = uc($1);
    $wgsver = $2;
}
else{
    print "WGS prefix should be that of the latest set, eg CAAM02.\n"
         ." I don't recognise $prefix\n";
    die();
}
Wgs::kill_previous_set($dbh, $prefix);
Wgs::add_to_distribution_table($dbh, $prefix);
$dbh->disconnect();
