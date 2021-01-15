#!/ebi/production/seqdb/embl/tools/bin/perl

use strict;
use warnings;

use DBI;

main();


sub main {

  my ( $dblogin, $set ) = @ARGV;
  unless( $set ) {
    die( "USAGE: $0 <db login> <set id>\nFlags a WGS set for distribution.\n\n" );
  }

  $set = uc( $set );
  if ( $set !~ /^[A-Z]{4}\d\d$/ ) {
    die( "ERROR: '$set' does not look like a set identifier.\ne.g. 'AAAB01' is a set identifier.\n" );
  }

  my $dbh = DBI->connect( 'dbi:Oracle:', $dblogin, '', {PrintError => 1, RaiseError => 1} );
  unless( $dbh ) {
    die( "ERROR: Cannot connect using '$dblogin'\n$!\n" );
  }

  my ( $exists ) = $dbh->selectrow_array
		( "SELECT 1 FROM dbentry WHERE primaryacc# LIKE '$set%' AND ROWNUM < 2" );
  unless( $exists ) {
    $dbh->disconnect();
    die( "ERROR: there are no entries (public or not) for '$set'.\n" );
  }

	my ( $exists_public ) = $dbh->selectrow_array
		( "SELECT 1 FROM dbentry WHERE primaryacc# LIKE '$set%' AND statusid = 4 AND ROWNUM < 2" );
  unless( $exists_public ) {
    $dbh->disconnect();
    die( "ERROR: there are no public entries for '$set'.\n" );
  }

  $dbh->do( "INSERT INTO distribution_wgs ( wgs_set) VALUES ( '$set' )" );

  print( STDERR "Done.\n" );

  $dbh->disconnect();
}
