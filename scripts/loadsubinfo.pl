#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/deprecated/loadsubinfo.pl,v 1.11 2007/02/06 12:34:49 lin Exp $
#
#  (C) EBI 1999
#
#  MODULE DESCRIPTION:
#
#  Loads contents of submittor info file into SUBMISSION_DETAILS table.
#
#  SUBMISSION_DETAILS                                          FILE-PREFIX
#
#  IDNO                            NOT NULL NUMBER(8)
#  FIRST_NAME                               VARCHAR2(20)       FNM:
#  MIDDLE_INITIALS                          VARCHAR2(10)       INI:
#  SURNAME                         NOT NULL VARCHAR2(40)       SUR:
#  ADDRESS1                                 VARCHAR2(40)       AD1:
#  ADDRESS2                                 VARCHAR2(40)       AD2:
#  ADDRESS3                                 VARCHAR2(40)       AD3:
#  ADDRESS4                                 VARCHAR2(40)       AD4:
#  ADDRESS5                                 VARCHAR2(40)       AD5:
#  ADDRESS6                                 VARCHAR2(40)       AD6:
#  EMAIL_ADDRESS                            VARCHAR2(80)       EML:
#  TEL_NO                                   VARCHAR2(30)       TEL:
#  REPLY_MEDIUM                    NOT NULL VARCHAR2(1)        REP:
#  SUBMISSION_TOOL                 NOT NULL VARCHAR2(1)        SBT:       
#
#  MODIFICATION HISTORY:
#
#  11-JUN-1999 Nicole Redaschi     Created.
#  25-APR-2001 Carola Kanz         * escape single quotes for loading into Oracle
#                                  * added strict
#                                  * database login as parameter
#                                  * deleted confidential and holddate
#                                  * check on max field length
#  27-APR-2001 Carola Kanz         check if new dsno is not already in use
#                                  ( if from dirsub_dsno sequence try some more )
#                                  changed from oraperl to dbi
#  04-JUN-2001 Carola Kanz         deleted submission_medium and contactable
#  14-JUN-2001 Carola Kanz         ignore certain tags in .info file
#  19-JUN-2001 Carola Kanz         added line SBT ( submission tool )
#  03-JUL-2001 Carola Kanz         check country ( address 6 ) on cv
#  23-SEP-2001 Nicole Redaschi     added option -test. modified command line syntax.   
#  13-DEC-2001 Carola Kanz         ignore empty lines
#  29-JAN-2002 Carola Kanz         deleted fax number
#  09-APR-2002 Carola Kanz         delete leading blanks
#  16-APR-2003 Carola Kanz         added CNF, HLD to ignored tags again ( still
#                                  used in sequin submissions )
#  06-FEB-2007 Quan Lin            replaced table countries with cv_submitter_country
#===============================================================================

use strict;
use DBI;
use dbi_utils;
use seqdb_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n USAGE: $0 <user/password\@instance> -f<file> [-ds<ds>] [-test] [-h]\n\n";

( @ARGV >= 1 && @ARGV <= 4 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide ( 1 );

my $login = $ARGV[0];
my $file  = "";
my $ds    = 0;
my $test  = 0;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\-f(.+)$/ )
   {
      $file = $1;
      if ( ( ! ( -f $file ) || ! ( -r $file ) ) )
      {
	 die ( "ERROR: $file is not readable\n" );
      }
   }
   elsif ( $ARGV[$i] =~ /^\-ds(.+)$/ )
   {
      $ds = $1;
      ( $ds =~ /\D/ ) && die "ERROR: invalid DS number: $ds\n";
   }
   elsif ( $ARGV[$i] eq "-test" )
   {   
      $test = 1;
   }
   else
   {
      die ( $usage );
   }
}

die if ( check_environment ( $test, $login ) == 0 );

# initialize the global hash with the tags of the submittor info file.

my %line;
$line{"FNM:"} = "";
$line{"INI:"} = "";
$line{"SUR:"} = "";
$line{"AD1:"} = "";
$line{"AD2:"} = "";
$line{"AD3:"} = "";
$line{"AD4:"} = "";
$line{"AD5:"} = "";
$line{"AD6:"} = "";
$line{"EML:"} = "";
$line{"TEL:"} = "";
$line{"REP:"} = "";
$line{"SBT:"} = "";

# tags in the .info files that should be ignored
my @ignore_tags = ( "WID:", "WIP:", "FAX:", "CNF:", "HLD:" );

# max length for some of the fields
my %len = ( "FNM:", 20, "INI:", 10, "SUR:", 40, 
	    "AD1:", 40, "AD2:", 40, "AD3:", 40, "AD4:", 40, "AD5:", 40, "AD6:", 40, 
	    "EML:", 80, "TEL:", 30 );

#-------------------------------------------------------------------------------
# parse the submittor info file.
#-------------------------------------------------------------------------------

open ( IN, $file ) || die "ERROR: cannot open file: $!";
while ( <IN> )
{
   chomp;
   next if ( /^\s*$/ );   # ignore empty lines
   my $tag   = substr ( $_, 0, 4 );
   my $value = substr ( $_, 4 );
   $value =~ s/\s*$//; # get rid of trailing whitespaces
   $value =~ s/^\s*//; # ... and of leading ones

   if ( !elem_of ( $tag, @ignore_tags ) ) 
   {
      defined ( $line{$tag} ) || die "ERROR: unknown line type: $_";
      $line{$tag} eq "" || die "ERROR: more than 1 $tag line: $_";
      $line{$tag} = $value;

      # check length
      defined $len{$tag} && $len{$tag} < length($value) && 
	  die "ERROR: $tag exceeds max length of $len{$tag}";
   }
   elsif ( $tag eq "HLD:" || $tag eq "CNF:" ) {
     print "WARNING: ignored line $tag$value\n";
   }
}
close ( IN ) || die "ERROR: cannot close file: $!";

### check if mandatory field surname is given
die "ERROR: SUR: no surname given"  if ( $line{"SUR:"} eq "" );

#-------------------------------------------------------------------------------
# set the reply medium.
#-------------------------------------------------------------------------------

if ( $line{"EML:"} ne "" ) # email
{
   $line{"REP:"} = "E";
}
else # letter                        
{ 
   $line{"REP:"} = "L"; 
}

#-------------------------------------------------------------------------------
# escape single quotes for loading into Oracle
#-------------------------------------------------------------------------------

foreach my $key ( keys ( %line ) ) 
{
   $line{$key} =~ s/'/''/g;
}

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

# check if country ( address6 ) is valid

dbi_getvalue ( $dbh, 
       "select count(*) from cv_submitter_country where country = '$line{\"AD6:\"}'" )
|| bail ( "country '$line{\"AD6:\"}' ( AD6 line ) is invalid", $dbh );


# select a new DS number if necessary.

if ( ! $ds )
{
   my $cnt = 1;
   my $i = 0;

   while ( $cnt != 0 && $i < 100 ) # to prevent an endless loop
   {
      $ds = dbi_getvalue ( $dbh, "SELECT dirsub_dsno.nextval FROM dual" );
      # make sure DS number is not already in use
      $cnt = dbi_getvalue ( $dbh, 
			    "select count(*) from submission_details where idno = $ds" );
      $i++;
   }
   ( $cnt == 0 ) ||
       bail ( "cannot get next DS number from sequence DIRSUB_DSNO", $dbh );
}
else 
{
   # check if given dsno does not already exist in database
   my $cnt = dbi_getvalue ( $dbh, 
			    "select count(*) from submission_details where idno = $ds" );
   ( $cnt == 0 ) || bail ( "DS $ds already exists in database", $dbh );
}

my $sql = "INSERT INTO submission_details
                     ( IDNO,
		       FIRST_NAME,
                       MIDDLE_INITIALS,
		       SURNAME,
                       ADDRESS,
                       COUNTRY,
		       EMAIL_ADDRESS,
		       TEL_NO,
		       REPLY_MEDIUM,
		       SUBMISSION_TOOL )
              VALUES ( $ds,
		       '$line{\"FNM:\"}',
		       '$line{\"INI:\"}',
		       '$line{\"SUR:\"}',
                       NVL2('$line{\"AD1:\"}','$line{\"AD1:\"}' || CHR(10),NULL) ||
                       NVL2('$line{\"AD2:\"}','$line{\"AD2:\"}' || CHR(10),NULL) ||
                       NVL2('$line{\"AD3:\"}','$line{\"AD3:\"}' || CHR(10),NULL) ||
                       NVL2('$line{\"AD4:\"}','$line{\"AD4:\"}' || CHR(10),NULL) ||
                       NVL2('$line{\"AD5:\"}','$line{\"AD5:\"}' || CHR(10),NULL),
		       '$line{\"AD6:\"}',
		       '$line{\"EML:\"}',
		       '$line{\"TEL:\"}',
		       '$line{\"REP:\"}',
		       nvl ( '$line{\"SBT:\"}', 'O' ) )"; 

dbi_do ( $dbh, $sql );

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

dbi_commit ( $dbh );
dbi_logoff ( $dbh );

print "Created record for DS $ds\n\n";
