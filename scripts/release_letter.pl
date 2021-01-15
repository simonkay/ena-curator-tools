#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/release_letter.pl,v 1.33 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2001
#
#  MODULE DESCRIPTION:
#
#  Releases all pending notifications currently held for a submission - either 
#  accession advice or review, according to parameter; if review notifications
#  are released, outstanding accession advices for the same DS are cancelled; 
#  if the -release_only flag is NOT given, generate_letters is called to generate
#  all accession advice resp. review notifications for this DS, where the medium 
#  is EMAIL; notifications with medium LETTER are not created.
#
#  NOTE: every update is immediately commited to the database as ( might be )
#  needed by generate_letter.pl
#
#  MODIFICATION HISTORY:
#
#  18-JAN-2001 Nicole Redaschi     Created.
#  12-JAN-2001 Carola Kanz         modified error handling
#  06-APR-2001 Carola Kanz         added flags -advice, -review, and -release_only
#  09-AUG-2001 Peter Stoehr        usage notes
#  23-SEP-2001 Nicole Redaschi     added option -test.   
#  16-NOV-2001 Carola Kanz         review letters refering to preliminary entries
#                                  are not released
#  11-DEC-2002 Carola Kanz         added reset of letter_code for tpas
#  02-JAN-2002 Carola Kanz         -advice/-review: send "normal" and TPA advice/
#                                  review letters
#  05-JAN-2007 Quan Lin            updated sql to use the new statusid column
#  27-FEB-2007 Rasko & Quan        added code for TPX letters
#  02-MAR-2007 Quan Lin            change pending status after sending email
#  05-JUN-2007 Quan Lin            if sending failed, change letter code back to confidential
#  07-SEP-2007 Quan Lin            use bind_param in sql
#  14-NOV-2007 Quan Lin            new functions: cancel pending letters, display pending letters,
#                                  resend letters, use accno to get ds
#===========================================================================================

use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;

# global variables
my $generate_letters = '/ebi/production/seqdb/embl/tools/curators/scripts/generate_letters.pl';

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Releases all advice and review notifications linked to a DS\n".
            "          directory. If the medium is 'email', the notifications are\n".
	    "          also sent, unless the -release_only parameter is specified.\n".
	    "          If the medium is 'letter', the notifications are not sent.\n\n".
            " USAGE:   $0\n".
	    "          <user/password\@instance> -advice|-review [-ds<ds>] [-release_only] [-test] [-h]\n\n".
            "   <user/password\@instance>\n".
	    "                   where <user/password> is taken automatically from\n".
	    "                   current unix session\n".
	    "                   where <\@instance> is either \@enapro or \@devt\n".
            "   -advice         processes all pending advice notifications linked\n".
	    "                   to the DS number\n".
	    "   -review         processes all pending review notifications linked\n".
	    "                   to the DS number (and deletes outstanding advice\n".
	    "                   notifications linked to the DS number)\n".
            "   -resend         works together with either -review or -advice\n".
	    "   -ds<ds>         takes the DS number from the current DS directory by\n".
            "                   default, or from the parameter <ds>\n".
            "   -ac<acc_no>     takes the DS number that the acc_no belongs to\n".
            "   -c              cancels pending letters in the current ds\n".
            "   -c -ds<ds>      cancels pending letters in the ds provided\n".
	    "   -release_only   releases but does not send email notification\n".
            "   -u              display pending letters for the current user\n".
            "   -u<user>        display pending letters for the named user\n".
            "   -au             display pending letters for all users\n".
	    "   -test           checks for test vs. production settings\n".
            "   -h              shows this help text\n\n";

( @ARGV >= 2 && @ARGV <= 6 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide ( 1 );

my $login = $ARGV[0];
my $ltype = "";
my $ds    = 0;
my $test  = 0;
my $release_only = 0;
my $cancel = 0;
my $user = "";
my $resend = 0;

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------
my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

#------------------------------------------------------------------------------
# handle command line
#------------------------------------------------------------------------------

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\-ds(.+)$/ )
   {
      ($ds == 0) || die "DS number should be provided by either -ds or -ac option, but not together\n";
      $ds = $1;
      ( $ds =~ /\D/ ) && die "ERROR: invalid DS number: $ds\n";
   }
   elsif ( $ARGV[$i] =~ /^\-ac(.+)$/ ){

      ($ds == 0) || die "DS number should be provided by either -ds or -ac option, but not together\n";
      $ds = accession_to_ds ($1);

      (defined $ds) || die "Invalid accession number provided\n";
   }  
   elsif ( $ARGV[$i] eq '-advice' ) 
   {
      ( $ltype eq "" ) || die $usage;
      $ltype = $ARGV[$i];
   }
   elsif ( $ARGV[$i] eq '-review' ) 
   {
      ( $ltype eq "" ) || die $usage;
      $ltype = $ARGV[$i];
   }
   elsif ( $ARGV[$i] eq '-release_only' ) 
   {
      $release_only = 1;
   }
   elsif ( $ARGV[$i] eq "-test" )
   {   
      $test = 1;
   }
   elsif ( $ARGV[$i] eq "-c")
   {
       $cancel = 1;
   } 
   elsif ( $ARGV[$i] eq "-resend")
   {
       $resend = 1;
   } 
   elsif ($ARGV[$i] =~ /^\-u(.+)$/)
   {
       $user = $1;
   }
   elsif ($ARGV[$i] eq "-u")
   {
       $user = $ENV{'USER'};
   }
   elsif ($ARGV[$i] eq "-au")
   {
       $user = "all_user";
   }   
   else 
   {
      die ( $usage );
   }
}

die if ( check_environment ( $test, $login ) == 0 );


#------------------------------------------------------------------------------
# display pending letters if required
#------------------------------------------------------------------------------

if ($user ne ""){

    display_pending_letter();
    dbi_logoff ( $dbh );
    exit;
}


#-------------------------------------------------------------------------------
# get the DS number from the current working directory, if it was not specified
#-------------------------------------------------------------------------------

if ( $ds == 0 )
{
   $ds = get_ds ( $test ) || die;
}

#-------------------------------------------------------------------------------
# verify DS number 
#-------------------------------------------------------------------------------

my $sth = $dbh->prepare ("SELECT count(*) FROM submission_details WHERE idno = ?");
$sth->execute ($ds);

( $sth->fetchrow_array() ) || bail ( "invalid DS number: $ds", $dbh );


#--------------------------------------------------------------------------------
# cancel  pending letters if required
#-------------------------------------------------------------------------------

if ($cancel == 1 and $ds != 0){

    cancel_pending_letter($ds);
    dbi_commit ($dbh);
    dbi_logoff ( $dbh );
    print "all letters for DS $ds have been cancelled.\n";
    exit;
}

# letter type is mandatory
( $ltype ne "" ) || die $usage;

#-------------------------------------------------------------------------------
# resend letters if required
#-------------------------------------------------------------------------------
if ($resend == 1){
    set_pending_status ($ds);
}
    
    
#-------------------------------------------------------------------------------
# accession advice letter
#-------------------------------------------------------------------------------
my $message = '';

if ( $ltype eq "-advice" ) 
{  
   my ( @letters ) = select_pending_letters ( $dbh, $ds, 'letter' );

   if ( ! @letters ) 
   {
      print "DS$ds: no pending accession advice letters\n";
   }
   else
   {
      
      # send emails (unless -release_only option was used)
      if ( ! $release_only ) 
      {
	 foreach my $letter ( @letters ) 
	 {
	    $message = send_emails ( $dbh, $ds, $letter, $test );

            if ($message =~ /==ERROR==/){

		die ("$message\nError: no advice letter sent from DS$ds\n");
	    }
	 }
      }

      my $sql= "UPDATE letter_details 
                   SET pending = 'N' 
                 WHERE pending = 'Y'
                   AND letter# IN 
                        ( SELECT letter# FROM accession_details WHERE idno = ? )";

      my $sth = $dbh->prepare($sql);
      $sth->execute($ds);
      dbi_commit ( $dbh ); 
      print "DS$ds: released pending accession advice letter(s): @letters\n";      
   }  
}

#-------------------------------------------------------------------------------
# review letter
#-------------------------------------------------------------------------------
else 
{ 
  my ( @letters ) = select_pending_letters ( $dbh, $ds, 'review_letter' );

  if ( ! @letters ) {
    print "DS$ds: no pending review letters\n";
  }
  else {
    my ( @letters_no_prel ) = ();

    foreach my $letter ( @letters ) {
      # do not release review letter if it contains preliminary entries
      my $sth = $dbh->prepare ("SELECT count(d.primaryacc#) 
                            FROM accession_details ad, dbentry d
                           WHERE ad.idno = ?
                             AND ad.review_letter# = ?
                             AND d.primaryacc# = ad.acc_no
                             AND d.statusid = 1");
      $sth->bind_param(1, $ds);
      $sth->bind_param(2, $letter);
      $sth->execute();

      if ($sth->fetchrow_array() > 0){
	  print "DS$ds: ERROR: review letter @letters cannot be sent as entries are draft/preliminary\n";
      }      
      else {
			      
	  push ( @letters_no_prel, $letter );			      
      }
    } 

     if ( @letters_no_prel ) {
       # only proceed, if there are review letters without preliminary entries
      @letters = @letters_no_prel;


      # review letters are created as confidential per default. here
      # we check whether any confidential entries are linked to the letter,
      # and if not, we update LETTER_DETAILS.LETTER_CODE accordingly and
      # send a submission review instead of a confidential review.
      foreach my $letter ( @letters ) 
      {
	 my $sth = $dbh->prepare ("SELECT count ( d.primaryacc# )
                                            FROM dbentry d, accession_details ad
                                           WHERE ad.idno = ?
                                             AND ad.review_letter# = ?
                                             AND ad.acc_no = d.primaryacc#
                                             AND d.statusid = '2' " );
	 $sth->bind_param(1, $ds);
	 $sth->bind_param(2, $letter);
	 $sth->execute();

	 my $conf = $sth->fetchrow_array();

	 if ( ! $conf )
	 {
            # "normal" entries 3 -> 2, tpa 8 -> 7, tpx 12 -> 11
	    my $sth = $dbh->prepare ( "UPDATE letter_details 
                                          SET letter_code = decode ( letter_code, 3, 2, 8, 7, 12, 11, letter_code)
                                        WHERE letter# = ?
                                          AND letter# IN 
                                          ( SELECT review_letter# FROM accession_details WHERE idno = ? )");
            $sth->bind_param(1, $letter);
            $sth->bind_param(2, $ds);
            $sth->execute(); 
	    
	    dbi_commit ( $dbh );
	 }
      }

      # send emails (unless -release_only option was used)
      if ( ! $release_only ) 
      {
	 foreach my $letter ( @letters )
	 {
	    $message = send_emails ( $dbh, $ds, $letter, $test );
           
            if ($message =~ /==ERROR==/){
		# if error, change the letter code back to confidential
		my $sth = $dbh->prepare ("UPDATE letter_details 
                                 SET letter_code = decode ( letter_code, 2, 3, 7, 8, 11, 12, letter_code )
                               WHERE letter# = ?
                                 AND letter# IN 
                                 ( SELECT review_letter# FROM accession_details WHERE idno = ? )"); 

		$sth->bind_param(1, $letter);
		$sth->bind_param(2, $ds);
		$sth->execute();
				    
	        dbi_commit ( $dbh );
		die ("ERROR: no review letters sent: @letters");
	    }
	 }
         # if the sending is sucessful, change pending status
	 foreach my $val (@letters){

	     my $sth = $dbh->prepare ("UPDATE letter_details 
                                          SET pending = 'N' 
                                        WHERE pending = 'Y'
                                          AND letter# = ?" );
	     $sth->execute($val);	     
         }
              
         dbi_commit ( $dbh );
         print "DS$ds: released pending review letter(s): @letters\n";

      }

      # cancel outstanding accession advice letters
      ( @letters ) = select_pending_letters ( $dbh, $ds, 'letter' );
      if ( @letters > 0 ) 
      {
	 my $sql =  "UPDATE letter_details 
                        SET pending = 'N', event_result = 0, cancelled = 'Y'
                      WHERE pending = 'Y' 
                        AND event_result != 0
                        AND letter# IN 
                              ( SELECT letter# FROM accession_details WHERE idno = ? )";

	 my $sth = $dbh->prepare($sql);
	 $sth->execute($ds);
	
	 dbi_commit ( $dbh );
	 print "DS$ds: cancelled outstanding accession advice letter(s): @letters\n";
      }
    }
  }
}

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------
  
dbi_commit ( $dbh ); 
dbi_logoff ( $dbh ); 


#===============================================================================
# subroutines 
#===============================================================================

sub select_pending_letters 
{ 
   # $letter can be 'letter' or 'review_letter'
   my ( $db, $ds, $letter ) = @_;
   my @letter_nos;

   my $sth = $dbh->prepare ("SELECT distinct ad.${letter}# 
                                        FROM accession_details ad, 
                                             letter_details ld
                                       WHERE ad.idno = ?
                                         AND ad.${letter}# = ld.letter#
                                         AND ld.pending = 'Y'
                                         AND ld.cancelled = 'N'" );

   $sth->execute($ds);

   while (my $letter_no = $sth->fetchrow_array()){
 
       push (@letter_nos, $letter_no);
   }

   return (@letter_nos);
}

sub send_emails {
  my ( $db, $ds, $letter_no, $test ) = @_;  
  my $result = '';

  my ( %lettercodes );
  $lettercodes{1} = 'accession advice';
  $lettercodes{2} = 'submission review';
  $lettercodes{3} = 'confidential review';
  $lettercodes{6} = 'TPA accession advice';
  $lettercodes{7} = 'TPA submission review';
  $lettercodes{8} = 'TPA confidential review';
  $lettercodes{10} = 'TPX accession advice';
  $lettercodes{11} = 'TPX submission review';
  $lettercodes{12} = 'TPX confidential review';

  my $sth = $db->prepare ("SELECT letter_code
                          FROM letter_details
                         WHERE letter# = ?" ); 

  $sth->execute($letter_no);
  my $letter_code = $sth->fetchrow_array();
 
  print "DS$ds: sending ".$lettercodes{$letter_code}." email for letter $letter_no\n";
  my $command = "$generate_letters $login -l$letter_code -n$letter_no";
  if ( $test ) {
      $command .= " -test";
  }
  $result = `$command`;

  return $result;
} 

sub display_pending_letter{

    my $sql_p1 = "select distinct to_char(l.timestamp, 'DD-MM-YYYY'), 
                         l.userstamp, 
                         s.idno, 
                         sl.title, 
                         decode (l.pending, 'Y', 'Pending'),
                         s.letter#  
                    from submission_history s, 
                         letter_details l, 
                         standard_letters sl
                   where s.letter# = l.letter#
                     and l.letter_code = sl.letter_code
                     and l.pending = 'Y'
                     and l.cancelled = 'N'
                     and l.letter_code not in (4, 5, 9)";              
              
                    
    my $sql_p2;

    if ($user eq "all_user") {
    
	$sql_p2 = "order by s.idno desc, to_char(l.timestamp, 'DD-MM-YYYY') desc";
    }
    else {
    
     $sql_p2 = "and l.userstamp = ?
                order by s.idno, to_char(l.timestamp, 'DD-MM-YYYY') desc";
    }

    my $sql = $sql_p1 . "\n" . $sql_p2;
    my $sth = $dbh->prepare ($sql);

    if ($user eq "all_user") {
	$sth->execute();
    }
    else {
	$sth->execute($user);
    }
    
    printf "%-12s%-13s%-8s%-22s%-9s%-9s\n", "Date", "User", "DS", "Letter Type", "Status", "Letter#";
    printf "=========== ============ ======= ===================== ======== ========\n";

    while (my @row = $sth->fetchrow_array()){

	my ($date, $user_stamp, $ds, $type, $status, $letter_no) = @row;

	printf "%-12s%-13s%-8s%-22s%-9s%-9s\n" , $date, $user_stamp, $ds, $type, $status, $letter_no;  
    }
}


sub cancel_pending_letter{

    my ($ds) = @_;
    my $sth = $dbh->prepare ("UPDATE letter_details 
                                 SET pending = 'N', event_result = 16, cancelled = 'Y'
                               WHERE pending = 'Y' 
                                 AND letter# IN 
                                     ( SELECT letter# FROM submission_history WHERE idno = ? )");
    $sth->execute($ds);
    dbi_commit($dbh);
}

sub accession_to_ds {
    my ($ac) = @_;
   
    my $sth = $dbh->prepare("SELECT idno FROM accession_details WHERE acc_no = ?");

    $sth->execute(uc($ac))
       || die("selecting DS for ac $ac in database failed:\n", $dbh->errstr);

     my $ds = $sth->fetchrow_array();
     return $ds;
}

sub set_pending_status{

    my ($ds) = @_;

    my $letter;
    if ($ltype eq "-advice"){
	$letter = "letter#";
    }
    elsif ($ltype eq "-review"){
	$letter = "review_letter#";
    }

    my $sql = "update letter_details 
                      set pending = 'Y',
                          cancelled = 'N', 
                          event_result = 15
                where letter# in (select $letter from accession_details where idno = ?)";
    
    my $sth = $dbh->prepare ($sql);

    $sth->execute($ds);
    
    dbi_commit($dbh);

}
