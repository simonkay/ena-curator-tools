#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/unload_align.pl,v 1.12 2011/06/20 09:39:35 xin Exp $
#
#  (C) EBI 2000
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#
#  Unload alignment Data from the database 
#  USAGE:
#  unload_align.pl <username/password\@instance> <accession number> [-clustal]
#
#  create .dat files and .aln files (CLUSTAL) 
#
#  MODIFICATION HISTORY:
#
# 15-NOV-2000 lombard      : change the database devt -> enapro 
# 09-JAN-2001 lombard      : add bioseqtype=2 => RNA 
# 15-JAN-2001 lombard      : change bioseqtype 5=PRT 1=DNA 4=RNA  
# 06-FEB-2001 lombard      : add perllib path, gives the right to the 
#                            public to use dbi_utils and SeqDBUtils(I need it
#                            for webin update)
# 21-MAY-2003 lombard      : added the option -u. the flag "-u" indicates that
#                            the flatfile is an update. Therefor the script 
#                            writes 'Last updated' instead of 'Created' 
#                            in the DT line
# 07-OCT-2004 lombard      : - unload_align accepts wgs accession number
#                            - changed DNA and RNA to NUC 
###############################################################################

#  Initialisation
use strict 'vars';
use dbi_utils;
use SeqDBUtils;
use DBI;

my $usage = "\n USAGE: unload_align.pl <username/password\@instance> <accession number> [-clustal|-u]\n\n";

# handle the command line.
( @ARGV >= 2 && @ARGV <= 3 )
    || die ($usage);

my ($alignid) = $ARGV[1];
$alignid = uc ($alignid);
if ($alignid =~/ALIGN_\d+/ ) {
  $alignid =~ s/ALIGN_//;
  $alignid =~ s/^0*//;
}else {
  print " Error invalid: accession number\n";
  exit; 
}

my (%abbrev,%type,%primary,%description);
my ($order,$abbrev,$type,$organisme,$primary,$description);
my ($acc,$alignacc,$bioseqtype,$symbols,$numseq,$first_crea);
my @row;
my ($annot,$bioseq,$features,$embl,$clustal,$option);
my $update = "";
my $aln_file = "";
my $counter = 0;
my $DT_text="";

# handle the command line.

if ( @ARGV == 3){
  $option = $ARGV[2];
  $option = lc ($option);
  if ($option eq "-clustal") {
    $aln_file=$option;
  }elsif ($option eq "-u") {
    $update=$option;
  }elsif ($option ne "-clustal" and $option ne "-u"){
    print " Error: wrong argument";
    print "$usage";
    exit;
  }
}

# --- connect to database --------------------------------------------------------
#my $session = dbi_ora_connect ($ARGV[0],{AutoCommit => 0, PrintError => 1, LongReadLen=> 1048575});
# added for large alignments
my $session = dbi_ora_connect ($ARGV[0],{AutoCommit => 0, PrintError => 1, LongReadLen=> 3000000});

my $sql ="select order_in,
                 seqname,
                 alignseqtype,
                 nvl (primaryacc#, '*'),
                 nvl (description,'*')
          from align_dbentry 
          where alignid = $alignid" ;

my $sql2 ="select a.alignacc,
                  a.bioseqtype,
                  a.symbols,
                  a.numseq,
                  to_char(a.first_public,'DD-MON-YYYY'),
                  f.annotation,
                  f.features,
                  f.seqalign,
                  f.clustal
           from align a,align_files f
           where a.alignid = f.alignid
           and a.alignid = $alignid" ;

my $cursor = dbi_open $session, $sql;
  
while ( (@row=dbi_fetch $cursor) ) {
  $counter++;
  ($order,$abbrev,$type,$primary,$description) = @row;
  $abbrev{$order} = $abbrev;
  $type{$order}= $type;
  $primary{$order}=$primary;
  $description{$order}=$description;

};
dbi_close $cursor;

$cursor = dbi_open $session, $sql2;
($alignacc,$bioseqtype,$symbols,$numseq,$first_crea,$annot,$features,$embl,$clustal) = dbi_fetch $cursor;
dbi_close $cursor;

# --- disconnect from database ---------------------------------------------------
dbi_rollback($session);
dbi_logoff($session);

# --- print the flat file  -------------------------------------------------------
# create the EMBL file

if (!$aln_file) {
  open (EMBL,">$alignacc.dat") || die "cannot write file: $!";
  if ($bioseqtype==1) {
    $bioseq='NUC' ;
  }elsif ($bioseqtype==4) {
    $bioseq='NUC' ;
  }else {
    $bioseq='PRT'; #protein
  }
  print EMBL "ID   $alignacc; $bioseq;  $symbols symbols ($numseq sequences)\nXX\n";
  print EMBL "AC   $alignacc\nXX\n";
  if (!defined $first_crea){
    $first_crea='';
#    print "alignment not public\n";
  }

  if ($update) {
    print EMBL "DT   $first_crea (Last updated)\nXX\n";  
  }else {
    print EMBL "DT   $first_crea (Created)\nXX\n"; 
  }
 
  $annot=~s/''/'/g;
  print EMBL "$annot";
  print EMBL "SH   No. Abbrev.          Acc.Num.     Description\nSH\n"; 
  my $i;
  for ($i=1;$i<=$counter;$i++) {
    $acc = 'CONSTRUCTED' if ($type{$i} eq "C");
    $acc = 'CONSENSUS' if ($type{$i} eq "Z");
    $acc = $primary{$i} if ($type{$i} eq "S");

    #protein case 
    $acc=$primary{$i} if ($type{$i} eq 'P'); 
    $acc="" if (($type{$i} eq 'P') and ($acc eq '*'));
    $abbrev{$i}=~s/''/'/g;
    printf EMBL "SO   %-3s ",$i;
    printf EMBL "%-15s  ",$abbrev{$i};
    printf EMBL "%-12s ",$acc;
    $description{$i}=~s/''/'/g;
    print EMBL "$description{$i}\n";
  }
  if ($features) {
    print EMBL "XX\nFH   Key             Location/Qualifiers\nFH\n";
    $features=~s/''/'/g;
    print EMBL $features."XX\n";
  }else {
    print EMBL "XX\nFH   Key             Location/Qualifiers\nFH\nXX\n";
  }
  print EMBL "AL   Alignment (".$numseq." sequences)  $symbols  symbols;\n";
  print EMBL "$embl\n";
  close EMBL || die ("can't close file: $!");
}else {
  open (ALN,">$alignacc.aln") || die "cannot write file: $!";
  print ALN "$clustal";
  close ALN || die ("can't close file: $!");
}





