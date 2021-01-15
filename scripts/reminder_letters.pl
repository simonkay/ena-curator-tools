#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/reminder_letters.pl,v 1.16 2011/04/26 11:03:12 mjang Exp $           
# 
#  (C) EBI 2001
#
#  MODULE DESCRIPTION:
#
#  Creates confidential/unpublished reminders: 
#  They are created every 6 months for any DS with confidential accession 
#  numbers without holddate or unpublished references; unpublished reminders 
#  are only created up to 24 months after pubdate, confidential reminders as 
#  long as there are confidential entries without holddate for the particular DS.
#
#  * Different from VMS: only the accession numbers of a DS appear in the
#    reminder that are either confidential or unpublished and not all
#    accession numbers assigned to this DS. Letters are not created with
#    'pending' status, but ready to be sent.
#  * It might be possible that both reminders are created for one DS in the 
#    same run of this script, but accession numbers cannot overlap as they are
#    either confidential or not confidential.
#    As there is only one event code ( 18 ) for both types of reminders in 
#    the submission_history, only one reminder letter is sent every six
#    month even if an unpublished reminder for one DS should be sent e.g.
#    only 3 months after a confidential reminder is sent for the same DS.
#    Two different event codes are needed, if this should be changed.
#  * Accession numbers with only unpublished references where the author has 
#    'no plans to publish' are not regarded in the unpublished reminders. In
#    entries migrated from VMS 'no plans to publish' is indicated in the
#    submission_history with event code 20 ( i.e. this applies to ALL 
#    unpublished references for one DS ), for references inserted after
#    migration the pubstatus is 'nop'. The query in this script regards both
#    possibilities; as reminders are only sent up to two years after the
#    submission, event code 20 does not need to be regarded two years after
#    migration any more.
#  * If a ( second/third ) reminder should be sent for the same accession
#    numbers of a DS as listed in the last reminder, the letter# is 'recycled',
#    i.e. accession_details does not need to be updated but only the letter_
#    details, e.g. the letter must be set 'pending' again.
#    If the accession number list differs, a new letter# is assigned ( as for
#    the first reminder ), i.e. it is difficult to trace which accession numbers
#    are listed in previous reminders.
#
#  MODIFICATION HISTORY:
#
#  25-JUN-2001  Carola Kanz        Created.
#  24-SEP-2001  Nicole Redaschi    added some comments and a bit of reformatting.
#                                  factored out insert into submission history
#                                  and select of reply_medium.
#                                  removed 'use seqdb_utils'.
#  10-JAN-2002  Carola Kanz        traded rollback for commit - in production
#                                  mode now               
#  15-JAN-2002  Nicole Redaschi    fixed bug with $letterno.
#                                  removed 'pending' status on request by karyn:
#                                  the outstanding letters form picks up all letters
#                                  where event_result != 0 and cancelled != 'N'
#  29-JAN-2002  Carola Kanz        deleted reply medium from letter_details
#  24-JUL-2003  Carola Kanz        letter_code = 4 for unpublished reminders
#                                  ( letter_code = 5 was set for all reminders so far )
#  27-OCT-2004  Quan Lin           use temp table to hold accession number list
#  05-JAN-2007  Quan Lin           updated sql to use the new column statusid
#  06-NOV-2007  Quan Lin           use bind_param in sql
#===============================================================================

use strict;
use DBI;
use dbi_utils;

my $exit_status = 0;
my $usage = "\nUSAGE: $0 <user/password\@instance>\n\n";
@ARGV == 1 || die $usage;

hide ( 1 );

# $interval defines the time period in months between two reminder letters.
# it should be 6 for the production system, but it might be useful
# to reduce it for testing ( together with switching 'commit' for 'rollback' 
# and some printing ... )
my $interval = 6;

my ( %conf, %unp );

print STDERR "\n\n\n==================================================================================\n";
print STDERR "REPORT ". ( scalar localtime ) . "\n";
print STDERR "==================================================================================\n";

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $ARGV[0] );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

#------------------------------------------------------------------------------
# create a temp table to hold accession number list
#------------------------------------------------------------------------------

my $table_name = "accno_list_temp";
my $sql = "CREATE TABLE $table_name 
           (acc_no VARCHAR2(15))";
         
dbi_do ($dbh, $sql);

#-------------------------------------------------------------------------------
# confidential reminder:
# event codes 17 - Letter activated
#             18 - Reminder assigned 
#             19 - Submitter is no longer contactable 
#-------------------------------------------------------------------------------

my ( @tab ) = dbi_gettable ( $dbh,
	     
"SELECT DISTINCT ad.idno, ad.acc_no 
   FROM accession_details ad,
        dbentry d
  WHERE d.primaryacc#  = ad.acc_no
    AND d.statusid = '2'
    AND d.hold_date IS NULL 
    AND NVL (d.first_created, d.timestamp) < ADD_MONTHS ( SYSDATE, - $interval )
    AND NOT EXISTS
      ( SELECT 1 
          FROM submission_history sh
         WHERE sh.idno = ad.idno
           AND sh.event_code in (17,18)
           AND sh.event_date > ADD_MONTHS ( SYSDATE, - $interval ) )
    AND NOT EXISTS
      ( SELECT 1 
          FROM submission_history sh
         WHERE sh.idno = ad.idno
           AND sh.event_code = 19 )" );

foreach my $row ( @tab ) 
{
   my ( $idno, $acc ) = @{$row};
   push ( @{ $conf{$idno} }, $acc );
}

#-------------------------------------------------------------------------------
# unpublished reminder 
# event codes 18 - Reminder assigned 
#             19 - Submitter is no longer contactable
#             20 - No plans to publish
#-------------------------------------------------------------------------------

( @tab ) = dbi_gettable ( $dbh,
         
"SELECT DISTINCT ad.idno, ad.acc_no 
   FROM accession_details ad,
        dbentry d, 
        citationbioseq c, 
        publication p
  WHERE d.primaryacc# = ad.acc_no
    AND d.statusid = '4'
    AND d.first_public is not null
    AND c.seqid = d.bioseqid
    AND p.pubid = c.pubid
    AND p.pubtype IN (1,7) -- Unpublished / Accepted
    AND p.pubdate < ADD_MONTHS ( SYSDATE, - $interval )
    AND p.pubdate > ADD_MONTHS ( SYSDATE, -25 )  
                                    -- 25 instead of 24 in order not to miss the last one
    AND p.pubstatus != 'nop'
    AND NOT EXISTS
      ( SELECT 1 
          FROM submission_history sh
         WHERE sh.idno = ad.idno
           AND sh.event_code = 18
           AND sh.event_date > ADD_MONTHS ( SYSDATE, - $interval ) )
    AND NOT EXISTS
      ( SELECT 1 FROM submission_history sh
         WHERE sh.idno = ad.idno
           AND sh.event_code IN ( 19, 20 ) ) " );

foreach my $row ( @tab ) 
{
   my ( $idno, $acc ) = @{$row};
   push ( @{ $unp{$idno} }, $acc );
}

#-------------------------------------------------------------------------------
# create reminders
#-------------------------------------------------------------------------------

print "\n----------------------------------------------------------------------------------\n";
print "unpublished reminders\n";
print "----------------------------------------------------------------------------------\n";

# unpublished reminders: letter code = 4
create_reminder_letters ( $dbh, 4, %unp );

print "\n----------------------------------------------------------------------------------\n";
print "confidential reminders\n";
print "----------------------------------------------------------------------------------\n";

# confidential reminders: letter code = 5
create_reminder_letters ( $dbh, 5, %conf );

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

dbi_do ($dbh,"DROP TABLE $table_name");
dbi_commit ( $dbh );
dbi_logoff ( $dbh );


#===============================================================================
# subroutines 
#===============================================================================

sub create_reminder_letters 
{
   my ( $dbh, $letter_code, %idnos ) = @_;

	my $sth_insert_acc = $dbh->prepare ("INSERT INTO $table_name
                                 (acc_no)
                                VALUES (?)");
    my $sth_count = $dbh->prepare ("SELECT COUNT ( idno ),
                                     COUNT ( reminder_letter# ),
                                     COUNT ( DISTINCT reminder_letter# )
                                      FROM accession_details
                                     WHERE idno = ?
                                       AND acc_no IN ( SELECT acc_no FROM $table_name)" );
	my $sth_get_letterno = $dbh->prepare (
                    "SELECT DISTINCT reminder_letter#
                       FROM accession_details
                      WHERE idno = ?
                        AND acc_no IN ( SELECT acc_no FROM $table_name )" );
	my $sth_update_letter = $dbh->prepare("UPDATE letter_details 
                                  SET letter_code = ?, 
                                      event_result = 12, 
                                      pending = 'N', 
                                      cancelled = 'N'
                                WHERE letter# = ?" );
	my $sth_insert_letter = $dbh->prepare( "INSERT INTO letter_details 
                    ( letter#, letter_code, event_result, pending, cancelled )
                                   VALUES ( ?, ?, 12, 'N', 'N' )" );
	my $sth_update_acc = $dbh->prepare( "UPDATE accession_details ad
                            SET reminder_letter# = ?
                          WHERE idno = ?
                            AND acc_no IN ( SELECT acc_no FROM $table_name ) " );
    my $sth_insert_subhis = $dbh->prepare( "INSERT INTO submission_history 
                                ( idno, event_date, event_code, letter# )
                             VALUES ( ?, SYSDATE, 18, ? )" );
   # loop over all DS numbers
   foreach my $idno ( keys %idnos ) 
   {
      print "\nDS$idno - ";
      
      # write all accession numbers of this DS in the $table_name table
      # so that the accession numbers can be used in the select statement
     
      dbi_do ($dbh, "TRUNCATE TABLE $table_name");
      
      foreach my $acc (@{$idnos{$idno}}){
	      $sth_insert_acc->execute($acc);
      }
 	      
      # check whether all accession numbers
      # 1. have a reminder_letter# ( $count2 == $count1 )
      # 2. share the same reminder_letter# ( $count3 == 1 )
      $sth_count->execute($idno);
      my ( $count1, $count2, $count3 )= $sth_count->fetchrow_array(); 

      my $letterno = 0;

      # if all accession numbers share the same reminder_letter#, we recycle it
      # NOTE: we also recycle the number, if there are accession numbers that are
      # not confidential resp. don't contain unpublished citations any more ->
      # these accession numbers will be printed unnecessarily in the letter as well
      if ( $count2 == $count1 && $count3 == 1 )
      {
		$sth_get_letterno->execute($idno);
		$letterno = $sth_get_letterno->fetchrow_array();

		print "recycling letter $letterno for accession numbers:\n";
		print join "\n", @{$idnos{$idno}}, "\n";

         $sth_update_letter->execute($letter_code, $letterno);
      }
      # ... otherwise we have to assign a new reminder_letter# for them.
      # NOTE: THIS CAN LEAVE ORPHANED LETTER RECORDS!!!
      else 
      {
		$letterno = dbi_getvalue ( $dbh,
				    "SELECT dirsub_letter#.nextval FROM dual" );

		print "creating new letter $letterno for accession numbers:\n";
		print join "\n", @{$idnos{$idno}}, "\n";

		$sth_insert_letter->execute($letterno, $letter_code);

		$sth_update_acc->execute($letterno, $idno);
	 
      }
      
      # add a record to the history...
      $sth_insert_subhis->execute($idno,$letterno);
   }
}

exit($exit_status);
