#!/ebi/production/seqdb/embl/tools/bin/perl

use strict;
use warnings;
use DBI;
use Net::FTP;

use lib '/ebi/production/seqdb/embl/tools/perllib/';
use Utils;

my $wget = "/usr/bin/wget";
my $wgetAttempts = 3; # how many times we are willing to try to retreive the file (with continue option
my $exit_status = 0;

my $USAGE = "USAGE: 
   $0 <username/password\@database> ddbj | ncbi ( skip_ftp | skip_transform | skip_load)

PURPOSE:
  Loads the livelist into the database. 

OPTIONS:
   skip_ftp        Does not ftp                    the livelist
   skip_transform  Does not ftp or transform       the livelist
   skip_load       Does not ftp, transform or load the livelist

RETURNS:
   0 if no errors were detected, otherwise 1.
";

use constant { DDBJ           => 'ddbj',
               NCBI           => 'ncbi',
               SKIP_FTP       => 'skip_ftp',
               SKIP_TRANSFORM => 'skip_transform',
               SKIP_LOAD      => 'skip_load',
               DATA_ROOT      => '/ebi/production/seqdb/embl/updates/livelist/' };

if ( @ARGV < 2 || @ARGV > 3 ) {
  die $USAGE;
}

main();

exit($exit_status);

sub main {
  eval {
    my ( $connection, $collaborator, $skip ) = @ARGV;

    if ( defined $skip ) {
      if (    $skip ne SKIP_FTP
           && $skip ne SKIP_TRANSFORM
           && $skip ne SKIP_LOAD )
      {
        die $USAGE;
      } ## end if ( $skip ne SKIP_FTP...
    } ## end if ( defined $skip )

    my ( $dbcode, $host, $directory, $file_prefix, $user, $password );

    if ( $collaborator eq DDBJ ) {
      $dbcode      = 'D';
      $host        = "ftp.ddbj.nig.ac.jp";
      $directory   = "livelist";
      $file_prefix = "ddbj_livelist.";
      $user        = "emblftp";
      $password    = "embl001";
    } elsif ( $collaborator eq NCBI ) {
      $dbcode      = 'G';
      $host        = "ftp-private.ncbi.nih.gov";
      $file_prefix = "GbLiveList.";
      $user        = "ntcollab";
      $password    = "gb_data";
    } else {
      die $USAGE;
    }

    my $work_dir = DATA_ROOT . $collaborator;
    print STDERR "INFO: working directory is $work_dir\n";

    chdir $work_dir;

    my $file;

    unless ( $skip
             && (    $skip eq SKIP_FTP
                  || $skip eq SKIP_TRANSFORM
                  || $skip eq SKIP_LOAD ) )
    {
      $file = ftp( $host, $directory, $file_prefix, $user, $password );
    } else {
      unless ( $skip
               && (    $skip eq SKIP_TRANSFORM
                    || $skip eq SKIP_LOAD ) ) {

        my @files = `ls -t $file_prefix*`;
        $file = shift ( @files );
      }
    }
    
    my $dat_file = "livelist_$collaborator.dat";

    transform( $collaborator, $file, $dat_file )
      unless ( $skip
               && (    $skip eq SKIP_TRANSFORM
                    || $skip eq SKIP_LOAD ) );

    load( $connection, $collaborator, $dat_file )
      unless ( $skip && $skip eq SKIP_LOAD );

    compare( $connection, $collaborator, $dbcode );
  };
  
  if ( $@ ) {
    die "ERROR: $@\n";
  }
} ## end sub main

sub test_zip {
  my ( $file ) = @_;

  if ( $file =~ /\.gz$/ ) {
    my $cmd = "gunzip -t $file";
    if ((system( $cmd)) == 0) { 
	return 1;
    }
    print STDERR "Gzip file $file is defective $!\n";
    return 0;    
  }
  print STDERR "$file is not a gzip file\n";
  return 0;
} ## end sub test_zip


sub uncompress {
  my ( $file ) = @_;

  if ( $file =~ /\.gz$/ ) {
    my $cmd = "gunzip -f $file";
    system( $cmd)
      && die "Can't execute $cmd, $!\n";

    $file =~ s/\.gz$//;
  } ## end if ( $file =~ /\.gz$/ )

  return $file;
} ## end sub uncompress


sub ftp {
  my ( $host, $directory, $file_prefix, $user, $password ) = @_;

  my $ftp;  
  # try 7 times before giving up
  my $i;
  for ( $i = 1; $i <= 7; ++$i ) {

    $ftp = Net::FTP->new( $host, Timeout => 3000 ) ; # NB default timeout = 120

    if ( defined ( $ftp ) ) {
      last;
    } else {
      sleep( 1 );
      next;
    }
  }

  if ( not defined ( $ftp ) ) {
    
    die( "Cannot connect to '$host' after $i attempts.\n$@" );
  }
  print STDERR "Connected to '$host' in $i attempt(s).\n" ;

  $ftp->login( $user, $password )
    || die "Can't login to $host, user: $user, password: $password\n";

  $ftp->binary()
    or die "Can't set format to binary $!\n";

  if ( defined $directory ) {
    $ftp->cwd( $directory )
      || die "Can't access directory $directory\n";
  }

  my $files = $ftp->ls( "$file_prefix*" )
    || die "Can't ls directory $directory\n";

  my %times;
  foreach my $file ( @$files ) {
    next unless( $file =~ m/\.gz$/ );# We want only compressed files
    my $time = $ftp->mdtm( $file )
      || die "Can't get the modification time for $file\n";
    $times{$time} = $file;
  }

  my @times = sort keys( %times );

  my $last_time = pop ( @times );
  my $file = $times{ $last_time };
  if ( !-f $file ) {
      print STDERR "INFO: file is $file\n";
      wgetFile ($user, $password, $host, $file, $directory) || die "Could not retrieve $file\n";
      Utils::printfile( 'last_loaded', "$file ". localtime( $last_time ) );
  } else {
      print "No new livelist\n";
      $exit_status = 4;
      exit $exit_status;
  }
  
  $ftp->quit;
  
  test_zip ($file) || die "giving up"; # need to try again
  print STDERR "INFO: uncompressing.\n";
  $file = uncompress( $file );

  $file =~ s/\.gz$//;
  system( "ln -fs $file current" );

  return $file;
} ## end sub ftp


sub transform {
  my ( $collaborator, $file, $dat_file ) = @_;

  print STDERR "INFO: transforming $file.\n";

  my %mga_sets;
  open FILE, "<$file"
    || die "Can't open file $file for reading, $!\n";

  open DAT_FILE, ">$dat_file"
    || die "Can't open $dat_file for writing, $!\n";

  while ( <FILE> ) {

    if ( !/^([A-Z]+)(\d+)\.(\d+)/ ) {
      die "Can't extract accesion number and sequence version, $_ \n";
    }

    my $accno_prefix = $1;
    my $accno_number = $2;
    my $version = $3;

    if ( length($accno_prefix) == 5 ) {# MGA, we want to retain only the set master

      $mga_sets{$accno_prefix .'0000000'} = $version;

    } elsif ( $accno_prefix ne 'AH' ) {# NCBI includes segmented sets which we don't want

      print DAT_FILE "$accno_prefix$accno_number,$version\n";
    }

  } ## end while ( <FILE> )

  # Now print all mga set ids
  while ( my($set_id, $version) = each(%mga_sets) ) {

    print DAT_FILE "$set_id,$version\n";
  }

  close FILE;
  close DAT_FILE;
} ## end sub transform

sub load {
  my ( $connection, $collaborator, $dat_file ) = @_;

  my $log_file     = "livelist_$collaborator.log";
  my $bad_file     = "livelist_$collaborator.bad";
  my $control_file = "livelist_$collaborator.ctl";

  drop_and_create_table( $connection, $collaborator );

  print STDERR "INFO: loading.\n";

  open( CONTROL_FILE, ">$control_file" )
  || die "Can't open file $control_file for writing, $!\n";

  print CONTROL_FILE <<TEXT;
LOAD DATA
TRUNCATE
INTO TABLE livelist_$collaborator
FIELDS TERMINATED BY ',' (
primaryacc# CHAR,
version INTEGER EXTERNAL)
TEXT

  close CONTROL_FILE;

  unlink $log_file;
  unlink $bad_file;

  my $cmd =
  "sqlldr userid=$connection data=$dat_file " .
  "control=$control_file log=$log_file bad=$bad_file " .
  "silent=header silent=feedback errors=0 direct=true";

  system( $cmd)
  && die "Can't execute $cmd, $!\n";

  if ( -f $bad_file ) {
    die `cat $bad_file`;
  }

  unlink $control_file;
} ## end sub load

sub compare {
  my ( $connection, $collaborator, $dbcode ) = @_;

  my $dbh = DBI->connect( 'dbi:Oracle:',
    $connection,
    '',
    { PrintError => 0,
      AutoCommit => 0,
      RaiseError => 1} )
  || die ( "ERROR: can't to connect to Oracle\n" );

  $@ = '';
  eval {

    print STDERR "INFO: cleaning tables.\n";
    clean_tables( $dbh, $collaborator, $dbcode );
    fill_missing( $dbh, $collaborator, $dbcode );
    fill_zombies( $dbh, $collaborator, $dbcode );
    # We don't do seq. ver. comparisons any more
    #fill_sequence_version( $dbh, $collaborator, $dbcode );
  };

  if ( $@ ) {

    $dbh->rollback();
    $dbh->disconnect();
    die "ERROR: compare failed\n$@\n";
  } ## end if ( $@ )

  $dbh->commit();
  $dbh->disconnect();
} ## end sub compare


sub drop_and_create_table {
  my ( $connection, $collaborator )  = @_;
  my $dbh = DBI->connect( 'dbi:Oracle:',
    $connection,
    '',
    { PrintError => 1,
      AutoCommit => 0,
      RaiseError => 1} )
  || die ( "ERROR: can't to connect to Oracle\n" );

  print STDERR "INFO: drop and create table livelist_$collaborator\n";

  eval {
    my $sql_drop_table = <<SQL;
DROP TABLE livelist_$collaborator
SQL
    $dbh->do( $sql_drop_table );

  };# we don't want tot die on this one in case the table isn't there

  my $sql_create_table = <<SQL;
create table LIVELIST_$collaborator
(
  PRIMARYACC# VARCHAR2(15) not null,
  VERSION     NUMBER(5) not null
)
tablespace DATALIB_TAB
SQL

  $dbh->do( $sql_create_table );

  my $sql_add_comment = <<SQL;
comment on table LIVELIST_$collaborator
  is 'table where the data from the latest livelist are loaded'
SQL

  $dbh->do( $sql_add_comment );

  my $sql_grant = <<SQL;
grant select on LIVELIST_$collaborator to EMBL_SELECT
SQL

  $dbh->do( $sql_grant );

  $dbh->commit();
  $dbh->disconnect();
}

sub clean_tables {
  my ( $dbh, $collaborator, $dbcode ) = @_;

  my $sql_delete = <<SQL;
DELETE 
  FROM datalib.livelist_missing ll
 WHERE ll.dbcode = '$dbcode'
SQL

  $dbh->do( $sql_delete );
  $dbh->commit();

  $sql_delete = <<SQL;
DELETE 
  FROM datalib.livelist_zombi ll
 WHERE ll.dbcode = '$dbcode'
SQL

  $dbh->do( $sql_delete );
  $dbh->commit();

  $sql_delete = <<SQL;
DELETE 
  FROM datalib.livelist_sequence_v ll
 WHERE ll.dbcode = '$dbcode'
SQL

  $dbh->do( $sql_delete );
  $dbh->commit();

  $sql_delete = <<SQL;
DELETE
  FROM livelist_$collaborator
 WHERE primaryacc# IN (SELECT primaryacc#
                         FROM ops\$datalib.livelist_exclude)
SQL

  $dbh->do( $sql_delete );
  $dbh->commit();
}


sub fill_missing {
  my ( $dbh, $collaborator, $dbcode ) = @_;

  print STDERR "LOG: fill_missing\n";

  my $sql_select = <<SQL;
INSERT INTO datalib.livelist_missing (dbcode, primaryacc#)
    SELECT '$dbcode',
           ll.primaryacc#
      FROM livelist_$collaborator ll
  MINUS
    SELECT dbe.dbcode,
           dbe.primaryacc#
      FROM datalib.dbentry dbe
     WHERE dbe.statusid = 4
       AND dbe.dbcode = '$dbcode'
SQL

  print STDERR "INFO: $sql_select\n\n";

  my $rows = $dbh->do( $sql_select );
  print STDERR "INFO: $rows missing entries.\n";
  $dbh->commit();
} ## end sub fill_missing

sub fill_zombies {
  my ( $dbh, $collaborator, $dbcode ) = @_;

  my $sql_select = <<SQL;
INSERT INTO datalib.livelist_zombi (dbcode, primaryacc#)
    SELECT dbe.dbcode,
           dbe.primaryacc#
      FROM datalib.dbentry dbe
     WHERE dbe.statusid = 4
       AND dbe.dbcode = '$dbcode'
  MINUS
    SELECT '$dbcode',
           ll.primaryacc#
      FROM livelist_$collaborator ll
SQL

  print STDERR "INFO: $sql_select\n\n";

  my $rows = $dbh->do( $sql_select );
  print STDERR "INFO: $rows zombies.\n";
  $dbh->commit();
} ## end sub fill_zombies

sub fill_sequence_version {
  my ( $dbh, $collaborator, $dbcode ) = @_;

  my $sql_select = <<SQL;
  INSERT INTO datalib.livelist_sequence_v
         (dbcode, primaryacc#, version_embl, version_collab)
  SELECT '$dbcode',
         dbe.primaryacc#,
         bs.version,
         ll.version
    FROM datalib.dbentry dbe,
         datalib.bioseq bs, 
         livelist_$collaborator ll
   WHERE dbe.statusid = 4
         dbe.dbcode = '$dbcode' AND
         dbe.primaryacc# = ll.primaryacc#  AND
         dbe.bioseqid = bs.seqid AND
         bs.version <> ll.version
SQL

  print STDERR "INFO: $sql_select\n\n";

  my $rows = $dbh->do( $sql_select );
  print STDERR "INFO: $rows mismatching sequence versions.\n";
  $dbh->commit();
} ## end sub fill_sequence_version

sub wgetFile {
    my ($user, $password, $host, $file, $directory) = @_;
    if (!(defined($file))) { 
	print STDERR "wget request for a blank filename!\n";
	return 0;
    }
	
    if (-e $file) {        
	unlink $file; # assume it is completely useless
    }
    my $wgetCommand;
    for (my $attemptNumber = 1; $attemptNumber <= $wgetAttempts; $attemptNumber++) {
	$wgetCommand = sprintf ("%s -q %s\"ftp://%s:%s\@%s/%s%s\"", 
				   $wget,
				   ((-e $file)? "-c ":""), # use continue if the file is has started to appear
				   $user, 
				   $password, 
				   $host,
				   (( defined $directory )?"$directory/":""),
				   $file);
	my $wgetReturn = system ($wgetCommand);
	if ($wgetReturn == 0) {
	    if ((-e $file) && 
		(test_zip($file))) {
		if ($attemptNumber > 1) {
		    print STDERR "Warning: Retrieving $file took $attemptNumber attempts using\n$wgetCommand:\n";
		}
		return 1;
	    }
	} else {
	    print STDERR "wget returned $wgetReturn when using\n$wgetCommand:\n";
	}
    }
    print STDERR "Warning: Retrieving $file failed even after $wgetAttempts attemps using\n$wgetCommand:\n";
    if (-e $file) {
	unlink $file;
    }
    return 0;
}

