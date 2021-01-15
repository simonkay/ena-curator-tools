#!/ebi/production/seqdb/embl/tools/bin/perl
#
use warnings;
use strict;
use DBI;
use DBLog;

use constant { DATA_ROOT => '/ebi/production/seqdb/embl/updates/livelist/' };

use lib '/ebi/production/seqdb/embl/tools/perllib/';

my $exit_status = 0;


main();

sub main {
  my ( $connection, $collaborator, $dbcode ) = read_args();
  
  my $dbh = DBI->connect( 'dbi:Oracle:',
                          $connection,
                          '',
                          { PrintError => 0,
                            AutoCommit => 0,
                            RaiseError => 1} )
    || die ( "ERROR: can't to connect to Oracle\n" );

  my $logger = DBLog->new(dsn => $connection,
			  module => 'ANTILOAD', 
			  proc   => 'LIVELIST REPORT',
			  );
  my $log_id = $logger->get_log_id();

  if( $log_id < 0 ) {
      die "Could not get log ID from database.\n";
  }

  my %data = ( missing => {number   => 0,
                           file     => "missing",
			   desc     => "entries live at $collaborator but missing from EMBL",
                           reporter => sub{write_still_missing(@_)}},
               zombies => {number   => 0,
                           file     => "zombies",
			   desc     => "entries killed by $collaborator are alive in EMBL",
                           reporter => sub{write_still_zombies(@_)}},
              # seq_ver => {number   => 0,
              #             file     => "seq_ver",
	      #	            desc     => "entries with a sequence version in EMBL < than that in $collaborator",
              #             reporter => sub{write_still_seq_ver(@_)}}
              );

  my $data_dir      = DATA_ROOT . lc( $collaborator );
  my $last_loaded   = $data_dir ."/last_loaded";

  my $livelist_file = "unknown ($last_loaded is missing)";
  if ((-e $last_loaded) && 
      (open( TXT, "< $last_loaded" ))) {
      $livelist_file = do { local $/; <TXT> };
      close(TXT);
  }

  $logger->log_info("Comparisons made with $livelist_file\n");

  my ( $day, $month, $year) = (gmtime( time() ))[3, 4, 5];
  my $suffix = "_$day-". ($month + 1) .'-'. (1900 + $year);

  eval {
    while ( my ( $name, $obj ) = each( %data ) ) {
  
      $obj->{file} = DATA_ROOT . lc( $collaborator ) . "/livelist_${collaborator}_" .
                     $name . $suffix;
      $obj->{number} = $obj->{reporter}( $dbh, $dbcode, $obj->{file});

      $logger->write_log_with_count($obj->{desc}, "INFO", $obj->{number});
      $logger->log_info("Full report in: $obj->{file}\nSummary in: $obj->{file}".".extrainfo\n");
    }
                       
  };

  if ($@) {

    print STDERR "ERROR: $@";
  }
  $logger->finish();
  $dbh->commit();
  $dbh->disconnect();
}


sub write_still_missing {
  my ( $dbh, $dbcode, $fname) = @_;

  my $sql_select = <<SQL;
SELECT ll.dbcode,
       ll.primaryacc#
  FROM datalib.livelist_missing ll
 WHERE ll.dbcode = '$dbcode'
   AND ll.primaryacc# NOT IN ( SELECT primaryacc#
                                 FROM dbentry
                                WHERE statusid = 4 )
 ORDER BY ll.primaryacc#
SQL
 
  open( REPORT_MISSING, ">$fname") or
    die "Can't open $fname for writing.\n$!";

  my $sth = $dbh->prepare( $sql_select );
  my $result = $sth->execute();

  format REPORT_MISSING =
@<<< @<<<<<<<<<<<<<<
$_->[0], $_->[1]
.
  $_ = ['DB', 'Accession'];
  write REPORT_MISSING;

  my $count = 0;
  while ( $_ = $sth->fetchrow_arrayref() ) {

    ++$count;
    write REPORT_MISSING;
  }

  close REPORT_MISSING;

  return $count;
}


sub write_still_zombies {
  my ( $dbh, $dbcode, $fname ) = @_;

  my $sql_select = <<SQL;
SELECT dbe.dbcode,
       dbe.primaryacc#
  FROM datalib.dbentry dbe
       JOIN
       datalib.livelist_zombi ll ON dbe.primaryacc# = ll.primaryacc#
 WHERE dbe.statusid = 4 AND
       dbe.first_public < sysdate - 4 AND
       ll.dbcode = '$dbcode'
 ORDER BY ll.primaryacc#
SQL

  open( REPORT_ZOMBIES, ">$fname") or
    die "Can't open $fname for writing.\n$!";
  
  
  my $sth = $dbh->prepare( $sql_select );
  my $result = $sth->execute();

  format REPORT_ZOMBIES =
@<<< @<<<<<<<<<<<<<<
$_->[0], $_->[1]
.

  $_ = ['DB', 'Accession'];
  write REPORT_ZOMBIES;
    
  my $count = 0;
  while ( $_ = $sth->fetchrow_arrayref() ) {

    ++$count;
    write REPORT_ZOMBIES;
  }

  close REPORT_ZOMBIES;
  return $count;
}


sub write_still_seq_ver {
  my ( $dbh, $dbcode, $fname) = @_;

  my $sql_select = <<SQL;
SELECT ll.dbcode,
       ll.primaryacc#,
       ll.version_embl,
       ll.version_collab
  FROM datalib.dbentry dbe
       JOIN
       datalib.bioseq bs ON dbe.bioseqid = bs.seqid
       JOIN
       datalib.livelist_sequence_v ll ON dbe.primaryacc# = ll.primaryacc#
 WHERE dbe.statusid = 4
       ll.dbcode = 'D' AND
       bs.version < ll.version_collab
 ORDER BY ll.primaryacc#
SQL

  open( REPORT_SEQ_VER, ">$fname") or
    die "Can't open $fname for writing.\n$!";

  my $sth = $dbh->prepare( $sql_select );
  my $result = $sth->execute();

  format REPORT_SEQ_VER =
@<<< @<<<<<<<<<<<<<< @<<<<<<<<<<< @<<<<<<<<<<<
$_->[0], $_->[1],   $_->[2],     $_->[3]
.

  $_ = ['DB', 'Accession', 'EMBL version', 'Ext version'];
  write REPORT_SEQ_VER;

  my $count = 0;
  while ( $_ = $sth->fetchrow_arrayref() ) {

    ++$count;
    write REPORT_SEQ_VER;
  }

  close REPORT_SEQ_VER;
  
  return $count;
}

sub read_args {
  my $usage = <<usage;
USAGE:
  $0 <user/password\@instance> ncbi | ddbj

PURPOSE:
  Creates the livelist report after the livelist has
  been loaded into the database.

RETURNS:
  0 if no errors were detected, otherwise 1.
usage

  my ( $connection, $collaborator ) = @ARGV;

  $collaborator = uc( $collaborator );
  
  unless( $collaborator && ( $collaborator eq 'NCBI' || $collaborator eq 'DDBJ' ) ) {

    die $usage;
  }

  my $dbcode;

  if ( $collaborator eq 'DDBJ' ) {

    $dbcode = 'D';
  
  } else {

    $dbcode = 'G';
  }

  return ( $connection, $collaborator, $dbcode );
}

exit($exit_status);
