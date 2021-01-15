#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_entry_info.pl,v 1.20 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Displays entry information (see USAGE).
#
#  MODIFICATION HISTORY:
#
#  31-AUG-2000 Nicole Redaschi     Created.
#  31-JAN-2001 Carola Kanz         * deleted entry name from output
#                                  * print hold date only for confidential entries
#                                  * select dsno separately as there are entries
#                                    in the database connected to more than one dsno
#  09-AUG-2001 Peter Stoehr        usage notes
#  22-SEP-2001 Nicole Redaschi    added option -test.  
#  28-NOV-2006 Quan Lin            changed entry_status to statusid due to schema change
#======================================================================================

use strict;
use DBI;
use DBD::Oracle;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Displays the following information for each entry:\n\n".
	    "          <ac> <status> <hold_date> <project#> [<ds>]\n\n".
	    "          Output:\n".
	    "          ac is accession number\n".
	    "          status is draft, private, cancelled, public, pre-public suppressed, killed\n".
	    "          hold date in DD-MON-YYYY format\n".
	    "          project number (0 for direct submissions)\n".
            "          ds is ds number\n\n".
            " USAGE:   $0\n".
	    "          <user/password\@instance> [-ds<ds>|-a<ac>|-f<file>] [-test] [-h]\n\n".
            "   <user/password\@instance>\n".
	    "                   where <user/password> is taken automatically from\n".
	    "                   current unix session\n".
	    "                   where <\@instance> is either \@enapro or \@devt\n\n".
	    "   -ds<ds>         runs in the current DS directory by default, or in\n".
	    "                   the DS directory given as the parameter <ds>\n".
            "   -a<ac>          where <ac> is any accession number\n".
            "   -f<file>        where <file> contains a list of accession numbers\n".
	    "   -test           checks for test vs. production settings\n".
	    "   -h              shows this help text\n\n";

( @ARGV >= 1 && @ARGV <= 3 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

my $database = $ARGV[0];
my $entry = "";
my $file  = "";
my $ds    = 0;
my $test  = 0;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\-a(.+)$/ )
   {
      $entry = uc ( $1 );
   }
   elsif ( $ARGV[$i] =~ /^\-f(.+)$/ )
   {
      $file = $1;
      if ( ( ! ( -f $file ) || ! ( -r $file ) ) ) {
	  die "ERROR: $file is not readable\n";
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
      die $usage;
   }
}

die if ( check_environment ( $test, $database ) == 0 );

#-------------------------------------------------------------------------------
# get the DS number from the current working directory, if it was not specified
#-------------------------------------------------------------------------------

if ( $entry eq "" && $file eq "" && $ds == 0 ) {
   $ds = get_ds ( $test ) || die;
}

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------
my %attr   = ( PrintError => 0,
	       RaiseError => 0,
               AutoCommit => 0 );
$database =~ s/^\/\@//;
my $dbh = DBI->connect( 'dbi:Oracle:'.$database, '/', '', \%attr )
    || die "Can't connect to database: $DBI::errstr"; 
$dbh->do(q{ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY'});


#-------------------------------------------------------------------------------
# fill @accnos array - either from file or via prompt.
#-------------------------------------------------------------------------------

my @accnos = ();
my $accno1;
if ( $entry ne "" )
{
   push ( @accnos, $entry );
}
elsif ( $file ne "" )
{
   open ( IN, $file ) || die "cannot open $file: $!";
   while ( <IN> )
   {
      chomp;
      ( $_ ne "" ) && push ( @accnos, $_ );
   }
   close ( IN ) || die "cannot close $file: $!";
}

#-------------------------------------------------------------------------------
# output for a ds or using the list
#-------------------------------------------------------------------------------

if (scalar(@accnos) == 0) {
    ds_2_entry_info($ds);
} else {
    entry_info ( \@accnos);
}

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

$dbh->disconnect;

#-------------------------------------------------------------------------------
# sub entry_info
#-------------------------------------------------------------------------------

sub entry_info {
    my $accnos_r = shift;
   my $header = sprintf "%-13s  %-10s  %-11s   %-3s %-5s   ", 
                        "AC", "Status", "HOLD DATE", "P", "DS";
   print "=" x length($header)."\n"
       . $header."\n"
       . "=" x length($header)."\n";
    my $ac2info_sql = $dbh->prepare("SELECT d.primaryacc#, cv.status,
			                    NVL ( to_char ( d.hold_date, 'DD-MON-YYYY' ), '-' ),
			                    d.project#, NVL ( ad.idno, 0 ), NVL (d.ext_ver, '0')
				       FROM dbentry d, accession_details ad, cv_status cv
		         	      WHERE d.primaryacc# = ?
				        AND d.primaryacc# = ad.acc_no (+)
				        AND d.statusid = cv.statusid");
    foreach my $acc (@$accnos_r) {
	$acc =~ s/\s//g;
	$acc = uc ( $acc );
	$ac2info_sql->execute($acc)    
	    || die "database error: $DBI::errstr";

	if (my ($primary, $entry_status, $hold_date, $project, $idno, $public) = $ac2info_sql->fetchrow_array()) {   
	    if (($entry_status eq "public") &&
		($public == 0)) {
		$entry_status = "pre-public";
	    }
	    printf "%-13s  %-10s  %-11s   %-3d %-5s\n",
	    $primary, $entry_status, 
	    ( $hold_date eq "-" ) ? "" : $hold_date, $project,
	    $idno;
	} else {
	    printf "%-13s  not in database\n", $acc; 
	}
	$ac2info_sql->finish();
    }
   print "\n";
}

sub ds_2_entry_info {
   my $dsno = shift;
   my $accCount = 0;

   my $ds2acCount = $dbh->prepare("SELECT count(*)
			     	     FROM accession_details
				    WHERE idno = ?");
   $ds2acCount->execute($dsno)
       || die "database error: $DBI::errstr";
   ($accCount) = $ds2acCount->fetchrow_array();
   if ($accCount == 0) {
       print "ERROR: No entries linked to DS $ds\n\n";
       $ds2acCount->finish();
       return;
   }
   print "$accCount entries linked to DS $ds\n\n";
   
   my $header = sprintf "%-13s  %-10s  %-11s   %-3s   ", 
                        "AC", "Status", "HOLD DATE", "P";
   print "=" x length($header)."\n"
       . $header."\n"
       . "=" x length($header)."\n";

   my $ds2info_sql = $dbh->prepare("SELECT d.primaryacc#, cv.status,
			                   NVL ( to_char ( d.hold_date, 'DD-MON-YYYY' ), '-' ),
			                   d.project#, NVL (d.ext_ver, '0')
			     	      FROM dbentry d, accession_details ad, cv_status cv
				     WHERE ad.idno = ?
                                       AND d.primaryacc# = ad.acc_no
			   	       AND d.statusid = cv.statusid
			          ORDER BY d.primaryacc#");

   $ds2info_sql->execute($dsno)    
       || die "database error: $DBI::errstr";
   while (my ($primary, $entry_status, $hold_date, $project, $public) = $ds2info_sql->fetchrow_array()) {   
       if (($entry_status eq "public") &&
	   ($public == 0)) {
	   $entry_status = "pre-public";
       }
       printf "%-13s  %-10s  %-11s   %-3d \n",
       $primary, $entry_status, 
       ( $hold_date eq "-" ) ? "" : $hold_date, $project;
   } 
   $ds2info_sql->finish();
}
