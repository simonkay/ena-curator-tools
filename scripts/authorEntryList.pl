#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2003
#
#  MODULE DESCRIPTION:
#
#  Uses a Surname and Forename to get info on previous submissions.
#
#  MODIFICATION HISTORY:
#
#  29-OCT-2003 Nadeem Faruque      Created.
#  07-JAN-2004 Nadeem Faruque      Now uses alldbi_utils methods 
#===============================================================================

use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage =
  "\n PURPOSE: Searches the database for entries that include a named author.\n\n"
  . " USAGE:   $0\n"
  . "          <user/password\@instance>\n"
  . "          [Surname forename] -q -h -c=n -t\n\n"
  . "          Surname         case-independent, add % to if it is shortened\n"
  . "          Forename        case-independent, add % to if it is shortened\n"
  . "          -help           shows this text\n"
  . "          -q(uiet)        Quiet option\n"
  . "          -c=n            Number of columns to display\n"
  . "          -t(est)         Required when reading /\@devt\n\n";

( @ARGV >= 1 )         || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide( 1 );    # What does this do?

my $quiet      = 0;
my $login      = $ARGV[0];
my $test       = 0;
my $surname    = "";
my $forename   = "";
my $maxColumns = 9999999;

for ( my $i = 1 ; $i < @ARGV ; ++$i ) {
    if ( $ARGV[$i] =~ /^\-h(elp)?$/ ) {
        die $usage;
    } elsif ( $ARGV[$i] =~ /^\-q(uiet)?$/ ) {
        $quiet = 1;
    } elsif ( $ARGV[$i] =~ /^\-c=([0-9]+)$/ ) {
        $maxColumns = $1;
    } elsif ( $ARGV[$i] =~ /^\-t(est)?$/ ) {
        $test = 1;
    } elsif ( $surname eq "" ) {
        $surname = $ARGV[$i];
    } else {
        $forename = $ARGV[$i];
    }
}
if ($login eq "/\@devt"){
    $test=1;}
$quiet and open( STDERR, "> /dev/null" );

if ( $login =~ /\/\@enapro/ ) {
    print STDERR "Connecting to enapro\n";
} elsif ( $login =~ /\/\@devt/ ) {
    print STDERR "Connecting to devt\n";
} else {
    die ( "$login isn't a known database user/password\@instance\n" . $usage );
}

die if ( check_environment( $test, $login ) == 0 );
my $dbh = dbi_ora_connect( $login );
while ( $surname eq "" ) {
    my $response = "";
    print "which Surname (QUIT to quit): ";
    chomp( $response = <STDIN> );
    if ( $response eq "QUIT" ) {
	dbi_logoff ( $dbh ); 
        die ( "\nScript exited at user's command\n" );
    } else {
        $surname = $response;
    }

    print "which Forename (QUIT to quit): ";
    chomp( $response = <STDIN> );
    if ( $response eq "QUIT" ) {
	dbi_logoff ( $dbh ); 
        die ( "\nScript exited at user's command\n" );
    } else {
        $forename = $response;
    }
}

$forename =~ s/\%$//; # always wildcarded, remove any extra wildcard

$test and
    print "Surname=\"$surname\"\n";
$test and
    print "Forename=\"$forename\"\n";

my $sql = $dbh->prepare("SELECT d.PRIMARYACC#, de.text, d.timestamp
	     	   FROM person p, PUBAUTHOR auth, citationbioseq cb, dbentry d, description de
		   WHERE p.SURNAME = ?
                   AND UPPER(p.firstname) like UPPER(?)
		   AND p.PERSONID = auth.PERSON
		   AND auth.PUBID = cb.pubid
	           AND cb.seqid = d.bioseqid
		   AND d.dbentryid = de.DBENTRYID
		   GROUP by d.PRIMARYACC#, de.text, d.timestamp
		   ORDER by d.timestamp DESC");

$sql->bind_param(1, $surname);
$sql->bind_param(2, $forename.'%');
$sql->execute || dbi_error($DBI::errstr);

$quiet or print "Querying for $surname $forename\n";
$test and
    print "$sql (surname=$surname, forename=$forename)\n";

my $queryTable = $sql->fetchall_arrayref();

#my @queryTable = ();
#foreach my $row (@$arrayRef) {
#    push(@queryTable, $row);
#}

print scalar( @$queryTable )." Results\n";

my $sql1 = $dbh->prepare("SELECT idno FROM accession_details WHERE acc_no = ?");

my @resultsList;
foreach my $row (@$queryTable){

    $quiet or print ".";

    $sql1->bind_param(1, $$row[0]);
    $sql1->execute || dbi_error($DBI::errstr);

    my $dsNumber = $sql1->fetchrow_array();

    if (not(defined $dsNumber)){
	$dsNumber = "";}
    push ( @resultsList,
           {  'AC' => $$row[0],
              'DE' => $$row[1],
              'DS' => "$dsNumber"
           }
    );
}

$quiet or print "\n" . scalar( @resultsList ) . " entries found\n";

dbi_logoff ( $dbh ); 

if (scalar( @$queryTable )) {
    print "ds     PrimaryAC#    Description\n"
	. "--------------------------------------------------------------------------------\n";
}

my $maxDescriptionLengthOut = ( $maxColumns - 21 );

foreach my $resultItem ( @resultsList ) {
    if ( length( $$resultItem{'DE'} ) > $maxDescriptionLengthOut ) {
        $$resultItem{'DE'} =
          substr( $$resultItem{'DE'}, 0, $maxDescriptionLengthOut );
    }
    printf "%-7s%-14s%s\n", $$resultItem{'DS'}, $$resultItem{'AC'},
      $$resultItem{'DE'};
}

exit();
