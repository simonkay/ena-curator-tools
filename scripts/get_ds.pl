#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_ds.pl,v 1.4 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  This script gets DS number for a given accession number. It's called from
#  update_management.csh
#
#  MODIFICATION HISTORY:
#
#  21-JUL-2003 Quan Lin     Created.
#
#===============================================================================

use strict;
use DBI;
use DBD::Oracle;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Displays the following information for each entry:\n\n".                    
            " USAGE:   $0 <ac>\n";
	  
if (@ARGV ne 1){die $usage};

my $accno = $ARGV[0]; 

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $dbh = DBI->connect('dbi:Oracle:ENAPRO','/','',
			   {RaiseError => 1,
			    LongReadLen => 100000})  
   	or die ("Can't connect to database: $DBI::errstr");
  
my $sth = $dbh->prepare(q{
                          SELECT idno 
                          FROM accession_details
                          WHERE acc_no = ?
                        });

$sth->bind_param(1, $accno);

  $sth->execute || die ("Can't execute statement: $DBI::errstr");
 # die $sth->errstr if $sth->err;

  my $dsno = $sth->fetchrow_array;

$dbh->disconnect;

if ($dsno){
  print $dsno;
}
else {
  print "0";
}


