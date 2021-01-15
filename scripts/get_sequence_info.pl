#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_sequence_info.pl,v 1.3 2006/11/17 16:47:26 lin Exp $
#
#  (C) EBI 2001
#
#  MODULE DESCRIPTION:
#
#  Displays sequence information (see USAGE).
#
#  MODIFICATION HISTORY:
#
#  04-JUN-2001 Nicole Redaschi     Created.
#  08-NOV-2006 Quan Lin            changed sql to use the new entry status 
#===============================================================================

use strict;

use DBI;
use DBD::Oracle;
use dbi_utils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n USAGE: $0 <username/password\@instance> [-a<acc>|-f<file>|-h]\n\n".
            " This program displays the following sequence information:\n\n".
            " <AC> <SV> <seqlen> <crc32> <dbcode> <project#> <status> <last_distributed>\n\n".
            " Program options:\n".
            " -a<acc|entry_name> process the entry you specify\n".
            " -f<file>           process the entries listed in the file you specify.\n".
            " -h                 show this text\n\n";

hide ( 1 );

( @ARGV >= 1 && @ARGV <= 2 ) || die $usage;

my $login = $ARGV[0];
my $entry = "";
my $file = "";

if ( $ARGV[1] )
{
   if ( $ARGV[1] =~ /^\-a.+/ )
   {
      $entry = $ARGV[1];
      $entry =~ s/-a//;
   }
   elsif ( $ARGV[1] =~ /^\-f.+/ )
   {
      $file = $ARGV[1];
      $file =~ s/-f//;
      if ( ( ! ( -f $file ) || ! ( -r $file ) ) )
      {
	 die ( "$file is not readable" );
      }
   }
   else
   {
      die ( $usage );
   }
}

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

#-------------------------------------------------------------------------------
# fill @accnos array - either from file or via prompt.
#-------------------------------------------------------------------------------

my @accnos = ();
if ( $entry ne "" )
{
   push ( @accnos, $entry );
}
elsif ( $file ne "" )
{
   open ( IN, $file ) || bail ( "cannot open $file: $!" );
   while ( <IN> )
   {
      chomp;
      ( $_ ne "" ) && push ( @accnos, $_ );
   }
   close ( IN ) || bail ( "cannot close $file: $!" );
}

#-------------------------------------------------------------------------------
# process all accnos.
#-------------------------------------------------------------------------------

print "=====================================================================\n";
print "AC        SV     LENGTH           CRC32  DB  P     STATUS DISTRIBUTED\n";
print "---------------------------------------------------------------------\n";

foreach ( @accnos )
{
   entry_info ( $_ );
}
print "\n";

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

dbi_commit ( $dbh );
dbi_logoff ( $dbh );



#-------------------------------------------------------------------------------
# sub entry_info
#-------------------------------------------------------------------------------

sub entry_info
{
   my ( $acc ) = @_;
   $acc =~ s/\s//g;
   $acc = uc ( $acc );

   my $sql = "SELECT b.seq_accid, b.version, b.seqlen, b.chksum,
                     d.dbcode, d.project#, c.status,
                     NVL(d.ext_date, d.first_public)
                FROM dbentry d, bioseq b, cv_status c
               WHERE d.primaryacc# = '$acc'
                 AND d.statusid = c.statusid
                 AND b.seqid = d.bioseqid";

   my ( $primary, $version, $seqlen, $chksum,
	$dbcode, $project, $entry_status, $ext_date )
       = dbi_getrow ( $dbh, $sql );

   if ( !defined $primary )
   {
      printf "%-8s  not in database\n", $acc;
   }
   else
   {
      printf "%-8s %3d %10d %15d %3s %2d %10s %-s\n",
      $primary, $version, $seqlen, $chksum,
      $dbcode, $project, $entry_status, $ext_date;
   }
}
