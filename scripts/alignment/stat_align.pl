#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/stat_align.pl,v 1.4 2006/12/07 14:54:22 gemmah Exp $
#
#  (C) EBI FEB 2002
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#
# dislpay the total number of : all alignments, protein alignments, DNA 
#                               alignments,
#                               confidential alignments, confidential DNA, 
#                               alignments, confidential protein alignments.
#                               
#  USAGE: stat_align.pl <username/password@instance> [-d year]
#
#  MODIFICATION HISTORY:
# 21-FEB-2002 lombard      : - gives the total number of deleted alignments
#                            - you can have statistics for a specific year 
#                              using the optional -d flag
#                            - change the initialisation
# 21-MAY-2003 lombard      :added a variable actual_year to avoid updating 
#                           every year the script 
###############################################################################

#  Initialisation

use strict;
use DBI;
use dbi_utils;
use seqdb_utils;

#  Variable declarations
my ($sql_alntotal, $sql_dnaln, $sql_alnconf, $sql_alnconfdna,$sql_del);
# variables for display
my ($aln_total,$aln_del,$aln_dna,$aln_prot,$aln_conf,$aln_conf_dna,$aln_conf_prot);

my ($extra_request)="";
my $actual_year = (localtime())[5]+1900;
my ($year)=0;

# handle the command line. 

unless ( ($#ARGV == 0) || ($#ARGV == 2 && $ARGV[1] eq '-d') )
{
 die "\n USAGE: stat_align.pl <username/password\@instance> [-d year]\n\n";
}

if ( $#ARGV == 2){
  $year = $ARGV[2];
  $year =~ s/[a-zA-Z_]*//g;
  if ( ($year <= 2000) or ($year > $actual_year))
    {
      die "\n you should select a different year for the moment only from 2001 until $actual_year\n\n";
    }
  $extra_request = " and to_char(first_created, 'YYYY')=$year"; 
}

# --- connect to database -----------------------------------------------------
my $session = dbi_ora_connect ($ARGV[0]);

# --- sql request

$sql_alntotal = sql_alntotal();

$sql_dnaln = sql_dnaln();

$sql_alnconf = sql_alnconf();

$sql_alnconfdna = sql_alnconfdna();

$sql_del = sql_del($year);

$aln_total = dbi_getvalue($session, $sql_alntotal);
$aln_dna = dbi_getvalue($session, $sql_dnaln);
$aln_conf = dbi_getvalue($session, $sql_alnconf);
$aln_conf_dna = dbi_getvalue($session, $sql_alnconfdna);
$aln_del = dbi_getvalue($session, $sql_del);
# --- calcul
$aln_prot = $aln_total - $aln_dna;
$aln_conf_prot = $aln_conf - $aln_conf_dna;


# --- disconnect from database ------------------------------------------------

dbi_commit($session);
dbi_logoff($session);

#------------------------------------------------------------------------------
# output formats
#------------------------------------------------------------------------------
if ($year) {
print "year= $year\n";
}

format STDOUT_TOP=
aln_tot    aln_dna    aln_prot   aln_conf   conf_DNA   conf_prot  deleted
========== ========== ========== ========== ========== ========== ==========
.

format STDOUT=
@<<<<<<<<< @<<<<<<<<< @<<<<<<<<< @<<<<<<<<< @<<<<<<<<  @<<<<<<<<< @<<<<<<<<<
$aln_total, $aln_dna, $aln_prot, $aln_conf, $aln_conf_dna, $aln_conf_prot, $aln_del
.

write;


#  Subroutine declarations
### how many alignment (deleted excluded)
sub sql_alntotal{

  my $sql;

  $sql="select count(alignid) 
       from align 
       where entry_status!='D'".$extra_request;

  return $sql;
}

### how many DNA alignment (deleted excluded)
sub sql_dnaln{

  my $sql; 

 $sql ="select count(alignid) 
        from align 
        where entry_status!='D' 
        and bioseqtype!=5".$extra_request; 

  return $sql;
}

### how many confidential alignment (deleted excluded)
sub  sql_alnconf{

  my $sql; 

 
 $sql ="select count(alignid) 
        from align 
        where entry_status!='D' 
        and confidential='Y'".$extra_request; 

  return $sql;
}

### how many confidential DNA alignment (deleted excluded)
sub  sql_alnconfdna{

  my $sql; 

 $sql ="select count(alignid) 
        from align 
        where entry_status!='D' 
        and confidential='Y' 
        and bioseqtype!=5".$extra_request;

  return $sql;
}    

### how many deleted  alignment
sub  sql_del{
 
  my $sql; 
 
 $sql ="select count(alignid) 
        from align 
        where entry_status='D'".$extra_request;

  return $sql;
}
