#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/generate_letters.pl,v 1.51 2020/07/14 17:29:54 suranj Exp $
#
#  (C) EBI 2000
#
#  STANDARD_LETTERS: -> selected into hash %letter
#  =================
#  LETTER_CODE TITLE                          EVENT_ORIGIN
#  ----------- ------------------------------ ------------
#            1 Accession Advice                         13 Accession# assigned
#            2 Submission Review                        14 Assigned for Review
#            3 Confidential Review                      14 Assigned for Review
#            4 Unpublished Reminder                     18 Reminder assigned
#            5 Confidential Reminder                    18 Reminder assigned
#     	     6 TPA Accession# Advice		        13
# 	     7 TPA Submission Review		        14
#	     8 TPA Confidential Review		        14
#     	     10 TPX Accession# Advice		        13
# 	     11 TPX Submission Review		        14
#	     12 TPX Confidential Review		        14
#
#  LETTER_MEDIA: -> only email
#
#  VALID_LETTERS (view):
#  =====================
#  SELECT letter_code, title, event_origin,
#         medium#, medium_code, description
#    FROM standard_letters,
#         letter_media;
#
#   
#  LETTERS PRINTED:
#
#  - letter_details.letter_code    = $letter{$l}{code}
#  - letter_details.medium_code    = '$medium{$m}{code}'
#  - letter_details.event_result  != 0
#  - letter_details.pending        = 'N'
#  - submission_history.event_code = $letter{$l}{event_origin}
#
#  * script is called by release_letter.pl
#  * printer names hard coded!! ( $printer_letter and $printer_ff )
#
#  MODIFICATION HISTORY:
#
#  11-AUG-2000 Nicole Redaschi     Created.
#  13-FEB-2001 Carola Kanz         added strict
#  22-MAR-2001 Carola Kanz         don't print surname if '-'
#  20-APR-2001 Carola Kanz         * printer names fix
#                                  * don't create .print and .remove files for emails
#                                  * fixed errors in remark and accession number 
#                                    table printing
#                                  * %template initialized by database data
#                                  * usage information updated
#                                  * unresolved problems: flatfiles printed in 
#                                    'one-page-per-page' format even though printer
#                                    ps5-duplex-2 is used; latex does not work on
#                                    ice and mozart, *.print files must be executed
#                                    on rum or tonic
#  23-APR-2001 Carola Kanz         * temporary fixes for problems above: printer 
#                                    problem with 'sleep' command between the prints,
#                                    latex problem with setting the TEXMFCNF environment 
#                                    variable ( curator .env file )
#                                  * dvips and latex output piped to dev/null
#  24-APR-2001 Carola Kanz         works without sleep now...
#  04-JUN-2001 Carola Kanz         uses printer ps8
#  19-SEP-2001 Nicole Redaschi     added page breaks between entries in print_entries.
#                                  added missing letter number in print_tex_header.
#                                  check for host in print script as long as we have
#                                  latex problems... 
#  23-SEP-2001 Nicole Redaschi     added option -test.
#  25-SEP-2001 Nicole Redaschi     use $login in call to getff.
#  26-SEP-2001 Nicole Redaschi     send report to datasubs.
#  22-JAN-2002 Carola Kanz         commits after every single letter
#  29-JAN-2002 Carola Kanz         * deleted fax as reply medium option
#                                  * use SUBMISSION_DETAILS.REPLY_MEDIUM instead of
#                                    LETTER_DETAILS.MEDIUM_CODE
#  30-JAN-2002 Carola Kanz         * used dbi
#                                  * only fetch needed letter and medium details
#                                  * parameter -m ( medium ) takes 'L' and 'E' instead
#                                    of 1 or 3
#  07-FEB-2002 Carola Kanz         * print_tex_header de-bugged and rewritten 
#  11-DEC-2002 Carola Kanz         updated fetch_accession_details: exclude deleted 
#                                  entries
#  11-DEC-2002 Carola Kanz         added tpa specific letters
#  21-JUL-2003 Carola Kanz         send reminder emails with sender address update@ebi,
#                                  all other letter with datasubs@ebi as before
#  22-JUL-2003 Carola Kanz          "  same for reports
#  03-MAY-2006 Carola Kanz         replaced getff parameter -c by -non_public
#  23-FEB-2006 F. NArdone          Use the v_submission_details view
#  27-FEB-2007 Rasko & Quan        added code for TPX letters
#  09-MAY-2007 Quan Lin            print out "==ERROR==" before die for release_letter.pl
#  05-JUN-2007 Quan Lin            fixed the problem with printing out "==ERROR==" before
#                                  die and open file twice if it failed the first time
#  09-SEP-2007 Quan Lin            use bind_param in sql
#=======================================================================================

use strict;
use SeqDBUtils;
use DBI;
use dbi_utils;
use Mailer;

# /ebi/production/seqdb/embl/tools/bin/perl /nfs/gns/homes/xin/ENA/reviewLetter/generate_letters.pl /@enadev -l3 -n221005 -test
my ( $debug ) = 1; # debug flag
my ( $getff )          = "/ebi/production/seqdb/embl/tools/bin/javagetff";
my ( $template_dir )   = "/ebi/production/seqdb/embl/tools/forms/letters/templates";
#my ( $template_dir_xin )   = "/nfs/gns/homes/xin/ENA/reviewLetter/";

my ( $NrOfMessages ) = 0;
# accession_details
my ( @acc_no, @statusid, @hold_date, @description, @status );


#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n USAGE: $0\n".
	    "          <username/password\@instance>\n".
            "          -l<letter_code> -m<medium_code> [-n<letter#>] [-test] [-h]\n\n".
            "   <user/password\@instance>\n".
	    "                   where <user/password> is taken automatically from\n".
	    "                   current unix session\n".
	    "                   where <\@instance> is either \@enapro or \@devt\n".
            "   -l<letter_code> 1 Accession Advice\n". 
            "                   2 Submission Review\n".                   
            "                   3 Confidential Review\n".                 
            "                   4 Unpublished Reminder\n".                
            "                   5 Confidential Reminder\n".
            "                   6 TPA Accession# Advice\n".
            "                   7 TPA Submission Review\n".
            "                   8 TPA Confidential Review\n".
            "                   10 TPX Accession# Advice\n".
            "                   11 TPX Submission Review\n".
            "                   12 TPX Confidential Review\n".
            "   -n<letter# >    letter number; if omitted, all letters in category are printed\n".
	    "   -test           checks for test vs. production settings\n".
            "   -h              shows this help text\n\n";


( @ARGV >= 3 && @ARGV <= 5 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

#hide ( 1 );

my $login    = $ARGV[0];
my $letter   = 0;
my $letterno = 0;
my $test     = 0;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\-l(.+)$/ )
   {
      $letter = $1;
      ( $letter =~ /\D/ ) && die $usage;
      ( $letter >= 1 && $letter <= 8 ) || die $usage;
   }
   elsif( $ARGV[$i] =~ /^\-n(.+)$/ )
   {
      $letterno = $1;
      ( $letterno =~ /\D/ ) && die "ERROR: invalid letter number: $letterno\n";
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
die ( $usage ) if ( $letter == 0 );
die if ( check_environment ( $test, $login ) == 0 );

my $tmp_dir = ( $test ) ? $ENV{"LETTERS_TEST"} : $ENV{"LETTERS"};
my $tmp_sym = ( $test ) ? "\$LETTERS_TEST" : "\$LETTERS";
( defined $tmp_dir ) || die ( "ERROR: environment is not set\n" );


#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $login );

# fetch controlled vocabulary
my $sth = $dbh->prepare ("select title, event_origin, LOWER(TRANSLATE(title, ' ', '_')) 
                            from standard_letters 
                           where letter_code = ?" );
$sth->execute($letter);
my ($letter_title, $letter_event_origin, $xtitle ) = $sth->fetchrow_array();

my ( $template ) = $xtitle.".email";   # filename template file


# open files

umask ( 006 );
my ( $date, $time ) = dbi_getrow ( $dbh,
        "SELECT to_char ( SYSDATE, 'DD-MON-YYYY' ), 
                to_char ( SYSDATE, 'HH24:MI:SS' )
           FROM dual" );

my ( $file ) = "Email-${letter}_$date-$time";

my $success = open ( LOG, ">$tmp_dir/$file.log" );    

test_open ($success, ">$tmp_dir/$file.log", \*LOG);

my $rep_success = open ( REPORT, ">$tmp_dir/$file.report" );

test_open ($rep_success, ">$tmp_dir/$file.report", \*REPORT);

# print debug information

debug ( "letter $letter: $letter_title, event origin: $letter_event_origin" );
debug ( "$date" );

#-------------------------------------------------------------------------------
# create letters emails
#-------------------------------------------------------------------------------
compose_message ( $letter, $test );

if ( $NrOfMessages == 0 ) 
{
  print "No Emails generated\n";
  print "==ERROR==";
}


debug ( "$NrOfMessages Email(s) created" );

dbi_commit ( $dbh );
dbi_logoff ( $dbh );


# close files

close ( REPORT );
send_report ( $letter, $test );
close ( LOG );


#===============================================================================
# subroutines 
#===============================================================================

sub compose_message
{
   my ( $letter, $test ) = @_;

   print     "$letter_title Email\n";
   print LOG "$letter_title Email\n";

   # distinct needed because letter# might be recycled ( i.e. mentioned more than once in
   # submission_history )

   my $sql = "SELECT distinct ld.letter#, ld.event_result, ad.idno 
               FROM letter_details ld, submission_history sh, 
                    accession_details ad 
	      WHERE ";

   ( $letterno != 0 ) && ( $sql .= "ld.letter# = ? AND " );
    
   $sql .=         "ld.letter_code = ?
               AND ld.event_result != 0
               AND sh.letter# = ld.letter# 
               AND sh.event_code = ?
               AND ld.letter# in ( ad.letter#, ad.review_letter#, ad.reminder_letter# )
             ORDER BY ad.idno";

   my $sth = $dbh->prepare($sql);
   $sth->execute($letterno, $letter, $letter_event_origin);
   my @table;

   while (my (@row) = $sth->fetchrow_array()){    
       push ( @table, \@row );     
   }
  
   if (!@table) {
       print LOG "ERROR: no letter found using sql query:$sql\n\n";
       print "ERROR: no letter found using sql query:$sql\n\n";
   }

   foreach my $row ( @table ) {
      my ( $xletterno, $event_result, $idno ) = @{$row};

      my ( %sd ) = fetch_submission_details ( $dbh, $idno );
      my $address = ( $test ) ? "$ENV{'USER'}\@ebi.ac.uk" : $sd{email_address};
      # delete blanks from email address to avoid system call to fail...
      $address =~ s/ //g;
      if ( ! defined $address ) 
      {
	 print LOG "ERROR: DS$idno, letter $xletterno: no email address given, letter sent to datasubs\n";
	 print     "ERROR: DS$idno, letter $xletterno: no email address given, letter sent to datasubs\n";
         $address = '';
      }

      my $no_of_acc = fetch_accession_details ( $dbh, $xletterno );
      ( $no_of_acc > 0 )
	  || die "ERROR: No Accession numbers for letter $xletterno - letter is not sent";

      my $message = "DS".$idno."_Email".$xletterno;

      my $success = open ( MSG, ">$tmp_dir/$message" );
      test_open ($success,">$tmp_dir/$message", \*MSG); 
     
      if ( !$address ) {
        # No email found => send to datasubs including postal address 
        print( MSG "Submitter's email address not found.\n" );
        print( MSG "Postal address is:\n" );
        print( MSG "$sd{postal_address}\n\n" );
        $address = 'datasubs@ebi.ac.uk';
      }

      my $header;
      if ( $sd{name} ne ' ' ) 
      {
	 $header = "\n$tmp_sym/$message to: $sd{name}";
      }
      else 
      {
	 $header = "\n$tmp_sym/$message to: $sd{address}";
      }

      $header .= " at $address";
      print REPORT "$header\n\n";
      print LOG    "$header\n";
      print        "$header\n";

      my $tep_success = open ( TEMPLATE, "$template_dir/$template" );

      test_open ($tep_success, "$template_dir/$template", \*TEMPLATE);

      my $sender_address = "datasubs\@ebi.ac.uk";
      if ( $letter == 4 || $letter == 5 ) {
        # reminder letters send from different address
        $sender_address = "update\@ebi.ac.uk";
      }

      while ( <TEMPLATE> )
      {  if ( /<ACCESSION_NUMBERS>/ ){
	  my $line = $_;
	  my $acc_range = format_acc_out(\@acc_no); 
	  $line =~ s/<ACCESSION_NUMBERS>/$acc_range/;
	  print MSG $line;

	 }
	 elsif ( /<ACCESSION NUMBERS>/ )
	 {
	    for ( my $i = 0; $i < $no_of_acc; $i++ )
            {
              print MSG "Accession#:  $acc_no[$i]\n";
              print MSG "Status:      $status[$i]\n";
              print MSG format_description ( 13, $description[$i] );
              print MSG "\n\n";

              print REPORT "    Accession#:  $acc_no[$i]\n";
              print REPORT "    Status:      $status[$i]\n";
              print REPORT format_description ( 17, $description[$i] );
              print REPORT "\n\n";
            }       
	 }
	 elsif ( /<REMARK>/ )
	 {
	    # fetch remark for review letter
	    my $sth = $dbh->prepare ("SELECT nvl ( text, ' ' ) FROM letter_remarks
		           WHERE letter# = ? ORDER BY lineno" );
	    $sth->execute($xletterno);
	    my ( @remarks );

	    while (my $line = $sth->fetchrow_array()){

		push (@remarks, $line);
	    } 
            
	    my $first = 1;
	    foreach my $remark ( @remarks ) 
            {
              if ( $first == 1 ) 
              {
                print MSG "\nRemarks:\n\n";
                $first = 0;
              }
              print MSG "$remark\n";
	    }
	 }
	 elsif ( m|<SUBMISSION DATE>| ) # Reminder
	 {
	    my $sql = "SELECT to_char ( MIN ( event_date ), 'DD-MON-YYYY' ) 
                         FROM submission_history 
                        WHERE idno = ?";

            my $sth = $dbh->prepare ($sql);
            $sth->execute($idno);
            my ($event_date ) = $sth->fetchrow_array();
	   
	    $_ =~ s|<SUBMISSION DATE>|$event_date|;
	    print MSG $_;
	 }
	 else
	 {
	    print MSG $_;
	 }
      }
      close ( TEMPLATE );

      # Review: append flat files
      if ( $letter == 2 || $letter == 3 || $letter == 8 || $letter == 7 || 
           $letter == 11 || $letter == 12 ) # Review
      {
        print MSG "\n\n\n";
        print_entries ( \*MSG, $login, $no_of_acc );
      }

      close ( MSG );

      send_mail_file( {
          to => $address,
          from => "EMBL Nucleotide Sequence Database <${sender_address}>",
          subject => "RE: Your submission - Our ref: DS$idno/$xletterno/$sd{surname}",
          replyto => "$sender_address" },
          "$tmp_dir/$message" );

      $NrOfMessages++;

      # update letter_details and insert submission_history

      my $user = $ENV{"USER"};
      $user = "Sent by " . $user;

      my $sth = $dbh->prepare ("INSERT INTO submission_history ".
	       "( IDNO, EVENT_DATE, EVENT_CODE, LETTER#, COMMENTS ) ".
               "VALUES ".
               "( ?, TO_DATE ( ?, 'DD-MON-YYYY' ), ".
	       "?, ?, ? )");
     
      debug ( $sth );
      $sth->bind_param (1, $idno);
      $sth->bind_param (2, $date);
      $sth->bind_param (3, $event_result);
      $sth->bind_param (4, $xletterno);
      $sth->bind_param (5, $user);
      $sth->execute();

      $sth = $dbh->prepare ("UPDATE letter_details SET event_result = 0 WHERE letter# = ?");
      debug ( $sth);
      $sth->execute($xletterno);
     
      # commit every letter, as emails should not be sent again, if another
      # letter fails
      dbi_commit ( $dbh );
   }
}

################################################################################
sub send_report
{
   my ( $letter, $test ) = @_;

   debug ( "send_report: $letter_title" );

   my $body = "********************************************************************************\n";
   $body .= "You have sent $NrOfMessages $letter_title email(s).\n";
   $body .= "********************************************************************************\n\n";

   my $success = open ( REPORT, "$tmp_dir/$file.report" );
   test_open($success, "$tmp_dir/$file.report", \*REPORT);
   
   while ( <REPORT> )
   {
      $body .= $_;
   }
   close ( REPORT );

   my $sender_address = "datasubs\@ebi.ac.uk";
   if ( $letter == 4 || $letter == 5 ) {
     # reminder letters send from different address
     $sender_address = "update\@ebi.ac.uk";
   }
   my $address = ( $test ) ? "$ENV{'USER'}\@ebi.ac.uk" : "$sender_address";

   send_mail( {
       to => $address,
       from => "EMBL Nucleotide Sequence Database <${sender_address}>",
       subject => "REPORT: $letter_title Email",
       replyto => $sender_address,
       body => $body } );

}

################################################################################ 

sub fetch_submission_details
{
  my ( $dbh, $idno ) = @_;

  my ( %sd );

  my $sql =  "SELECT decode ( surname, '-', ' ', surname ),
                     decode ( first_name, NULL, '', first_name || ' ' ) ||
                     nvl ( middle_initials, '' ) || decode ( middle_initials, NULL, '', ' ' ) ||                        decode ( surname, '-', ' ', surname ),
                     email_address,
                     nvl(address1, '-')
                FROM v_submission_details
               WHERE idno = ?";
#   my $sql =  "SELECT decode ( v.surname, '-', ' ', v.surname ),
#                      decode ( v.first_name, NULL, '', v.first_name || ' ' ) ||
#                      nvl ( v.middle_initials, '' ) || decode ( v.middle_initials, NULL, '', ' ' ) ||                        decode ( v.surname, '-', ' ', v.surname ),
#                      v.email_address,
#                      nvl(t.address, '-')
#                 FROM v_submission_details v
#                      join
#                      submission_details t on v.idno = t.idno
#                WHERE v.idno = ?";

  my $sth = $dbh->prepare ($sql);
  $sth->execute($idno);

  ($sd{surname}, $sd{name},$sd{email_address}, $sd{postal_address} ) = $sth->fetchrow_array();
  
  ## compute the max address length
  $sd{addr_maxlen} = length ( $sd{name} );

  return %sd;
}

################################################################################
sub fetch_accession_details
{
  my ( $dbh, $letter ) = @_;
  my $sql =  "SELECT ad.acc_no,  
                      d.statusid,
                    nvl ( TO_CHAR ( d.hold_date,'DD-MON-YYYY' ), '-' ),
                     de.text  
                FROM accession_details ad, dbentry d, description de 
               WHERE ( ad.letter# = ?
                       OR ad.review_letter# = ?
                       OR ad.reminder_letter# = ? )
                 AND d.primaryacc# = ad.acc_no  
                 AND de.dbentryid (+) = d.dbentryid
                 AND d.statusid not in (3,5,6)  
            ORDER BY acc_no" ;
  my $sth = $dbh->prepare($sql);
  $sth->execute($letter, $letter, $letter);
  my @table;

  while (my (@row) = $sth->fetchrow_array()){    
       push ( @table, \@row );     
  }
  
  my ( $i ) = 0;
  
  foreach my $row ( @table ) {
    ( $acc_no[$i], $statusid[$i], $hold_date[$i], $description[$i] ) = @{$row};

    if ( $statusid[$i] == 2 ) {# private
      if ( $hold_date[$i] ne '-' ) {
	$status[$i] = "confidential until $hold_date[$i]";
      }
      else {
	$status[$i] = "confidential until publication";
      }

    } elsif ( $statusid[$i] == 1 && # draft
        $hold_date[$i] ne '-' ) {   # with hold date

      $status[$i] = "confidential until $hold_date[$i]";

    } else {

      $status[$i] = "not confidential";
    }
    $i++;
  }

  return $i;
}

################################################################################

sub print_entries
{
   my ( $OUT, $login, $no_of_acc ) = @_;

   chdir "$tmp_dir";

   for ( my $i = 0; $i < $no_of_acc; $i++ )
   {
      my $acc = $acc_no[$i];
      print "fetching entry $acc from database...\n";

      $acc = lc ( $acc );
      debug ( "$getff $login $acc -non_public" );
      sys ( "$getff $login $acc -non_public > /dev/null", __LINE__ );
      my $entry = "$tmp_dir/". lc ( $acc ) .".dat";
      my $success = open ( ENTRY, $entry );
      test_open ($success, $entry, \*ENTRY);

      while ( <ENTRY> )
      {
	 print $OUT "$_";
      }
      # add page breaks between entries for letters
      unlink ( $entry );
   }
}

################################################################################
sub format_description
{
   my ( $offset, $line ) = @_;

   my $maxlen = 80 - $offset;
   my $header = " " x ( $offset );
   my $buffer = " " x ( $offset - 13 );

   my $description = $buffer."Description: ";

   for (;;)
   {
      if ( length ( $line ) <= $maxlen )
      { 
	 $description .= $line;
	 last;
      }
      else
      {
	 my ( $i );
	 my @xline = split ( //, $line ); 
	 for ( $i = $maxlen; $i > 0 && $xline[$i] ne ' ' && $xline[$i] ne '-'; --$i ) { ; }
	 if ( !$i )
	 {
            # no blanks in line
	    $description .= substr ( $line, 0, $maxlen );
	    $description .= "\n$header";
	    $line = substr ( $line, $maxlen );
	 }
	 else
	 {
	    $description .= substr ( $line, 0, $i );
	    $description .= "\n$header";
	    $line = substr ( $line, $i+1 );
	 }
      }
   }
   return $description;
}

################################################################################
sub debug
{
   my ( $text ) = @_;
   $debug && print LOG $text."\n";
}

################################################################################

sub test_open {

    my ($success, $file, $fileh) = @_;

    if (!$success){
	sleep (1);
	$success = open ($fileh, $file);
    
	unless ($success){
	    print "==ERROR==";
	    die "==ERROR== cannot open file $file: $!";
	}
    }
}

#################################################################################

sub format_acc_out {

  my ($accArray) = @_;
  my $returnStr="";
  my %accHash;
  my %accHashF;

  foreach my $ele (@$accArray){
    
    if($ele =~ /^([a-zA-Z]+)(\d+)/){      
      push @{$accHash{$1}}, $2;
    }
    else{
      die ("$ele got wrong format\n");
    }
  }

  foreach my $key (keys %accHash){
    my @values = sort @{$accHash{$key}};
    my $values_len = scalar @values;
  
    my @subArray;
    $subArray[0][0]= $values[0];
    my $j=0;
    my $k=1;

    for (my $i = 0; $i<$values_len-1; $i++){
      if(($values[$i+1] - $values[$i])==1){
	 $subArray[$j][$k]=$values[$i+1];
	 $k++;
      }
      else{
	$j++;
	$k=0;
	$subArray[$j][$k]=$values[$i+1];
      }      
    }

    $accHashF{$key} = [@subArray];
  }
 
  foreach my $keyF (keys %accHashF){
    my @subArrayF = @{$accHashF{$keyF}};
    foreach my $row (0..@subArrayF-1)    {
      if((scalar @{$subArrayF[$row]}) ==1){
	$returnStr.=$keyF.$subArrayF[$row][0];
      }
      elsif((scalar @{$subArrayF[$row]}) >1){	
	  $returnStr.= $keyF.$subArrayF[$row][0]."-".$keyF.$subArrayF[$row][@{$subArrayF[$row]}-1];  
      }
      else{
	die "no accession found\n";
      }
      $returnStr.= ",";
    }
  }
  
  return (substr($returnStr,0,(length $returnStr)-1));
}



