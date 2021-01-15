#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/add_ec_number.pl,v 1.4 2010/10/04 13:11:43 faruque Exp $
#
#  add_ec_number.pl
#  add ec_number to table cv_ec_numbers
#
#  MODIFICATION HISTORY:
#  19-DEC-2002 Carola Kanz         Created.
#  01-AUG-2003 Quan Lin            for ec numbers that exist, check if they are
#                                  valid, if not, update to valid
#===============================================================================

use strict;
use DBI;
use ENAdb;


my $usage = "\nPURPOSE: insert new EC number into table cv_ec_numbers".
            "\n\nUSAGE: $0 <user/password\@instance> <ec_number>\n\n";

@ARGV == 2 || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

my $database = $ARGV[0];
my $ecno = $ARGV[1];

$ecno =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
if ( !defined $1 || !defined $2 || !defined $3 || !defined $4 ) {
  die "not a correct ec number: $ecno\n";
}

my ( $pos1, $pos2, $pos3 ) = ( $1, $2, $3 );

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------
defined($database) || die $usage;
my %attr   = ( PrintError => 0,
	       RaiseError => 0,
               AutoCommit => 0 );

my $dbh = ENAdb::dbconnect($database,%attr)
    || die "Can't connect to database: $DBI::errstr";


#-------------------------------------------------------------------------------
# check if ec number already exists, if it does, check if it's valid, if not, 
# update to valid
#-------------------------------------------------------------------------------

my ($count) =  exists_ec_number($dbh, $ecno);
my ($valid) = check_valid ($dbh, $ecno);

if ($count == 1 ){
   print "*** $ecno does already exist.\n";

   if ($valid eq "N"){
     update_valid ($dbh, $ecno);
   }
   $dbh->disconnect;
   exit;
}

#-------------------------------------------------------------------------------
# get code and insert new ec number
#-------------------------------------------------------------------------------

insert_ec_number ( $dbh, $ecno );

#-------------------------------------------------------------------------------
#  check for 'dash' numbers
#-------------------------------------------------------------------------------
if ( ! exists_ec_number ( $dbh, "$pos1.$pos2.$pos3.-" ) ) {
  insert_ec_number ( $dbh, "$pos1.$pos2.$pos3.-" );

  if ( ! exists_ec_number ( $dbh, "$pos1.$pos2.-.-" ) ) {
    insert_ec_number ( $dbh, "$pos1.$pos2.-.-" );

    if ( ! exists_ec_number ( $dbh, "$pos1.-.-.-" ) ) {
      insert_ec_number ( $dbh, "$pos1.-.-.-" );
    }
  }
}

$dbh->commit();
$dbh->disconnect();



################################################################################

sub exists_ec_number {
    my ( $dbh, $ecNo ) = @_;

    my $sth = $dbh->prepare("SELECT count(*) FROM cv_ec_numbers where ec_number = ?");
    $sth->execute($ecNo)
      || die "finding existence of $ecNo in database failed: $DBI::errstr";
    my ($result) = $sth->fetchrow_array();
    $sth->finish();
    return $result;
}


sub check_valid {
    my ($dbh, $ecNo) = @_;

    my $sth = $dbh->prepare("SELECT valid FROM cv_ec_numbers WHERE ec_number = ?");
    $sth->execute($ecNo)
      || die "finding validity of $ecNo in database failed: $DBI::errstr";
    my ($result) = $sth->fetchrow_array();
    $sth->finish();
    return $result;
}

sub insert_ec_number {
    my ( $dbh, $ecNo ) = @_;
    
    my $sth = $dbh->prepare("INSERT into cv_ec_numbers ( code, ec_number ) 
              VALUES ( (select max(code)+1 from cv_ec_numbers), ? )" );
    $sth->execute($ecNo)
	|| die "inserting $ecNo in database failed: $DBI::errstr";
    $sth->finish();
    print "inserted $ecNo\n";
    return 1;
}

sub update_valid {
    my ($dbh, $ecNo) = @_;
    
    my $sth = $dbh->prepare("UPDATE cv_ec_numbers
           SET valid = 'Y'
           WHERE ec_number =  ?" );
    $sth->execute($ecNo)
	|| die "updating validity of $ecNo in database failed: $DBI::errstr";
    $sth->finish();
    print "EC number $ecNo has been updated to valid\n";
    return 1;
}
