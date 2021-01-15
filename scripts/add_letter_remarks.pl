#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/add_letter_remarks.pl,v 1.14 2010/10/04 14:25:04 faruque Exp $
#
#  add_letter_remarks.pl
#  can be used to add/update letter_remarks. 
#  An emacs with the existing remark - if there is one - is opened for the 
#  curator to insert/modify. The remark is loaded/reloaded into the database 
#  as soon is the emacs is closed.
#  The remarks are added to the review letter of the ds number given as
#  parameter or the current ds directory.
#  NOTE: remarks can only be updated if the letter has not already been sent
#
#  MODIFICATION HISTORY:
#  20-NOV-2002 Carola Kanz         Created.
#===============================================================================

use strict;
use DBI;
use SeqDBUtils;
use ENAdb;


my $tmpfile = $ENV{'USER'}.time();
my $emacs = '/usr/bin/emacs +4:0 -geometry 81x24+80+50';


my $usage = "\nPURPOSE: to add/update letter remarks". 
            "\n\nUSAGE: $0 <user/password\@instance> [-ds<ds>] [-test] [-h]\n\n".
            "           -ds<ds>   takes the DS number from the current DS directory by\n".
            "                     default, or from the parameter <ds>\n".
            "           -test     checks for test vs. production settings\n".
            "           -h        shows this help text\n\n";


( @ARGV >= 1 && @ARGV <= 4 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

my $database = $ARGV[0];
my $ds    = 0;
my $letterno = 0;
my $test  = 0;

for ( my $i = 1; $i < @ARGV; ++$i ) {
  if ( $ARGV[$i] =~ /^\-ds(.+)$/ ) {
    $ds = $1;
    ( $ds =~ /\D/ ) && die "ERROR: invalid DS number: $ds\n";
  }
  elsif ( $ARGV[$i] eq "-test" ) {   
    $test = 1;
  }
  else {
    die ( $usage );
  }
}

die if ( check_environment ( $test, $database ) == 0 );

#-------------------------------------------------------------------------------
# if ds not specified, use ds from current directory
#-------------------------------------------------------------------------------
if ( $ds == 0 ) {
  $ds = get_ds ( $test ) || die "ERROR: you are not in a DS directory\n";
}

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
# verify DS number 
#-------------------------------------------------------------------------------
my $sql = "SELECT count(*) FROM submission_details WHERE idno = ?";
my $sth = $dbh->prepare ($sql);
$sth->execute($ds);

( $sth->fetchrow_array ) || mybail ( $dbh, "invalid DS number: $ds", $tmpfile );

#-------------------------------------------------------------------------------
# select letter# - remarks are connected to the review letter
#-------------------------------------------------------------------------------

$sth = $dbh->prepare ("SELECT nvl ( max ( review_letter# ), 0 )
                         FROM accession_details
                        WHERE idno = ?");
$sth->execute($ds);
$letterno = $sth->fetchrow_array;

( $letterno != 0 ) || mybail ( $dbh, "review letter for ds $ds not yet created", $tmpfile );

#-------------------------------------------------------------------------------
# retrieve letter remarks from db ( if any )
#-------------------------------------------------------------------------------
my ( $remarks_exist ) = retrieve_letter_remarks ( $dbh, $tmpfile, $letterno );

#-------------------------------------------------------------------------------
# remarks can only be edited, if letter is not already sent 
# ( event_code 12: Letter sent )
#-------------------------------------------------------------------------------

$sth = $dbh->prepare(" SELECT 1
                         FROM submission_history
                        WHERE letter# = ?
                          AND event_code = 12");
$sth->execute($letterno);
my $sent = $sth->fetchrow_array;

#--------------------------------------------------------------------------------
# if the letter has already been sent display the remarks ( if any )
# otherwise open emacs for the curator to edit and store the inserted/updated
# remarks in the database
#--------------------------------------------------------------------------------
if ( $sent ) {
  display_remarks_only ( $dbh, $remarks_exist, $tmpfile );
}

else {
  edit_and_store_remarks ( $dbh, $tmpfile );
}

unlink ( <$tmpfile*> ) || warn "cannot remove $tmpfile: $!\n";

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------
$dbh->commit(); 
$dbh->disconnect();


################################################################################

sub retrieve_letter_remarks {
  my ( $dbh, $tmpfile, $letterno ) = @_;
  my $exists = 0;

  open ( REM, ">$tmpfile" ) || mybail ( $dbh, "cannot open file $tmpfile: $!", $tmpfile );

  print REM "********************************************************************************\n";
  print REM "*****             Please, do not exceed 80 characters per line!            *****\n";
  print REM "********************************************************************************\n";

  my $sth = $dbh->prepare ("SELECT nvl(text, ' ')
                              FROM letter_remarks
                             WHERE letter# = ?
                             ORDER BY lineno");
  $sth->execute($letterno);

  my @remarks;
  while (my $row = $sth->fetchrow_array){
      push (@remarks, $row);
  }

  if ( @remarks ) {
    foreach ( @remarks ) {
      print REM "$_\n";
    }
    $exists = 1;
  }
  close ( REM ) || mybail ( $dbh, "cannot close file $tmpfile: $!", $tmpfile );

  return $exists;
}


sub display_remarks_only {
  my ( $dbh, $exist, $tmpfile ) = @_;

  # remarks cannot be updated and are only printed to the screen
  print "Letter has already been sent\n";
  print "REMARK:\n********************************************************************************\n";
  if ( $exist ) {
    open ( REM, "$tmpfile" ) || mybail ( $dbh, "cannot open file $tmpfile: $!", $tmpfile );
    while ( <REM> ) {
      print   if ( substr ( $_, 0, 5 ) ne "*****" );
    }
    close ( REM );
  }
  print "********************************************************************************\n";
}


sub edit_and_store_remarks {
  my ( $dbh, $tmpfile ) = @_;

  #-----------------------------------------------------------------------------
  # open emacs for curator to add/update remarks
  #-----------------------------------------------------------------------------
  sys ( "$emacs $tmpfile" );
  open ( REM, "$tmpfile" ) || mybail ( $dbh, "cannot open file $tmpfile: $!", $tmpfile );

  #-----------------------------------------------------------------------------
  # insert/update remarks in database
  #-----------------------------------------------------------------------------
  my $lineno = 0;
 
  my $sth = $dbh->prepare ( "SELECT nvl(max(lineno), 0 )
                               FROM letter_remarks 
                              WHERE letter# = ?");
  $sth->execute($letterno);  
  my $maxlineno = $sth->fetchrow_array;

  print "REMARK:\n********************************************************************************\n";
  while ( <REM> ) {
    chomp ( my $rem = $_ );
    # ignore empty lines and the autogenerated ones
    if ( $rem &&  substr ( $rem, 0, 5 ) ne "*****" ) {
      # split lines longer than 80 chars
      if ( length ( $rem ) > 80 ) {
        my ( @pieces ) = cut_line ( $rem );
        foreach my $piece ( @pieces ) {
          $lineno = insert_or_update_rem ( $dbh, $piece, $lineno, $maxlineno );
        }
      }
      else {
        $lineno = insert_or_update_rem ( $dbh, $rem, $lineno, $maxlineno );
      }
    }
  }

  if ( $lineno < $maxlineno ) {
    # delete surplus lines
    
    my $sth = $dbh->prepare ("DELETE from letter_remarks
                              WHERE letter# = ?
                                AND lineno > ?" );
    $sth->execute($letterno,  $lineno);
  }

  print "********************************************************************************\n";
  close ( REM );
}


sub insert_or_update_rem {
  my ( $dbh, $rem, $lineno, $maxlineno ) = @_;
  print "$rem\n";
  # don't bother retreiving empty lines (mainly artifects of mixing manual + automatic line wrapping
  if ($rem =~ /^\s*$/) {
      return $lineno;
  }
      
  $lineno++;
  # update, if lineno is already in db
  if ( $lineno <= $maxlineno ) {
   
    my $sth = $dbh->prepare ("UPDATE letter_remarks
                                 SET text = ?
                               WHERE letter# = ?
                                 AND lineno = ?
                                 AND text != ?" );
    $sth->execute($rem,$letterno,$lineno, $rem);
  }
  else {  # insert
    
    my $sth = $dbh->prepare ("INSERT INTO letter_remarks ( letter#, lineno, text )
                              VALUES ( ?, ?, ? )" );
    $sth->execute($letterno,$lineno,$rem);
  }
  return $lineno;
}


#--------------------------------------------------------------------------------

sub cut_line {
  my ( $line ) = @_;

  # cut into pieces <= 80;
  my $maxlen = 80;
  my @bits = ();

  for (;;) {
    if ( length ( $line ) <= $maxlen ) { 
      push ( @bits, $line );
      last;
    }
    else {
      my ( $i );
      my @xline = split ( //, $line ); 
      for ( $i = $maxlen; $i > 0 && $xline[$i] ne ' ' && $xline[$i] ne '-'; --$i ) { ; }
      if ( !$i ) {
        # no blanks in line
        push ( @bits, substr ( $line, 0, $maxlen ));
        $line = substr ( $line, $maxlen );
      }
      else {
        push ( @bits, substr ( $line, 0, $i ));
        $line = substr ( $line, $i+1 );
      }
    }
  }
  return @bits;
}

#--------------------------------------------------------------------------------

sub mybail {
  my ( $dbh, $msg, $fname ) = @_;

  # disconnect from Oracle
  $dbh->rollback();
  $dbh->disconnect(); 
  
  unlink ( <$tmpfile*> );

  print "ERROR: $msg\n";
  exit;
}
