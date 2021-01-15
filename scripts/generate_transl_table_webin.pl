#!/ebi/production/seqdb/embl/tools/bin/perl -w

#------------------------------------------------------------------------------
# generate_transl_table_webin.pl
#
# generates hash variables containing the genetic code table for WEBIN
#
# output of this script replaces genetic code table definition in the
# webin definition page
# should run after every update of cv_genetic_code (diff_genetic_code_table.pl)
#
# USAGE: generate_translationtable.pl <user/passwd@instance>
#
# 22-JAN-2001  Carola Kanz
#
#  MODIFICATION HISTORY:
#
# 19-NOV-2001  Vincent Lombard     Added hash variable for non important third 
#                                  base.   
#                                  Changed the display.
# 14-DEC-2001  Vincent Lombard     modified thirdbase hash.
#                                  The hash includs codon with 'rymksw' and 
#                                  not only 'x' 
#
#------------------------------------------------------------------------------

use strict;
use DBI;
use SeqDBUtils;
use dbi_utils;

umask (0113);

my ($path)="/ebi/services/tools/taxonomy/tmp/webin/";
my ($path_webin)="/ebi/www/web/public/Services/webin/Feature/";
my ($path_webinnew)="/ebi/www/web/internal/Services/dbgroup/webin.new/Feature/";

hide (1);

### --- read and check parameters ----------------------------------------------
@ARGV == 1 || die "\nUSAGE: $0 <user/passwd\@instance>";

### --- create all codon permutation ( must be same order as used in transltable! )
my $concat="%thirdbase = (\n";
my ($ambig_key,$bases,%table);

my @nuc = ( 't', 'c', 'a', 'g' );
my %ambig_bases=('r'=>['a','g'], 'y'=>['c','t'], 'm'=>['a','c'], 'k'=>['g','t']
		 , 's'=>['g','c'], 'w'=>['a','t'], 'h'=>['a','t','c'],
		 'x'=>['a','t','g','c']);

my @codons = ();
foreach my $n1 ( @nuc ) {
  foreach my $n2 ( @nuc ) {
    foreach my $n3 ( @nuc ) {
      push @codons, "$n1$n2$n3";
    }
  }
}

### --- login to Oracle -------------------------------------------------------

my $dbh = dbi_ora_connect ( $ARGV[0] );

$dbh->{AutoCommit}    = 0;
$dbh->{RaiseError}    = 1;
$dbh->do( "alter session set nls_date_format='DD-MON-YYYY'" );

### --- select translation table information from database --------------------

my ( @tab ) = dbi_gettable ( $dbh,
                    "SELECT table_id, table_name, aalist, start_codon
                       FROM cv_genetic_code 
                      ORDER by table_id" );

my %tab_names;

open (FILE,">".$path."ProteinDefs.pm");

print FILE "package Feature::ProteinDefs;\n\n";
foreach my $row ( @tab ) {
  my ( $table_id, $table_name, $aalist, $start_codon ) = @{$row};
 
  my @Aalist = split //, $aalist;
  my @Start_codon = split //, $start_codon;
  
  # print start codons
  print FILE "\%init_${table_id} = (\n";
  my $cnt = 0;
  for ( my $i = 0; $i < @Start_codon; $i++ ) {
    if ( $Start_codon[$i] eq 'M' ) {
      if ( $cnt != 0 ) {
	print FILE ",";
	print FILE "\n"        if ( ( $cnt % 4 ) == 0 );
      }
      $cnt++;
      print FILE "'".$codons[$i]."'=>'M'";
    }
  }
  print FILE ");\n\n";

  # print aalist
  print FILE "\%gen_code_${table_id} = (\n";

  for ( my $i = 0; $i < @Aalist; $i++ ) {
    print FILE "'".$codons[$i]."'=>'".$Aalist[$i]."'";

    # create the hash for the third base missing list
    $table{$table_id}{$codons[$i]}=$Aalist[$i];

    if ( $i != @Aalist - 1 ) {
      print FILE ",";
      print FILE "\n"    if ( ( ( $i + 1 ) % 4 ) == 0 );
    }
  }
  print FILE ");\n\n";

  $tab_names{$table_id} = $table_name;

}

### --- disconnect from Oracle ------------------------------------------------
dbi_rollback ( $dbh );
dbi_logoff ( $dbh );

### --- print third base missing (or undefined) list --------------------------

foreach my $key (sort { $a <=> $b } keys %table) {

  my $reference_aa;     # the first amino acid used as a reference
  my $cnt = 0;          # counter
  my $i;
  my $codon_result;     # codon with the 3rd base modified

  $concat .= "$key => {";
  foreach my $a (@nuc) {
    foreach my $b (@nuc) {
      while (($ambig_key, $bases)=each(%ambig_bases)) {
	my ($bad)=0;
	# initialise the amino acid reference 
	$reference_aa = $table{$key}{"${a}${b}$$bases[0]"};
	for ($i=1;$i<=$#$bases;$i++) {
	  #compare the reference with the others amino acid
	  if ($table{$key}{"${a}${b}$$bases[$i]"} ne $reference_aa) {
	    $bad=1;
	    last;
	  }
	}
	if (!$bad) {
	  $cnt++;
	  $codon_result=$table{$key}{"${a}${b}$$bases[$i-1]"};
	  $concat .= "'${a}${b}$ambig_key'=>'$codon_result',";
	  $concat .= "\n"        if ( ( ( $cnt + 1 ) % 4 ) == 0 );
	}
	
      }
    }
  }
  $concat =~ s/\n$//;
  chop ($concat);
  $concat .= "},\n"; 
}

# delete the last '},'
chop ($concat);
chop ($concat);
$concat .= ");\n";

# print third base missing (or undefined) list
print FILE $concat;

# print genetic code labels
print FILE "\n\n\%gen_codes_labels = (\n";
foreach my $k ( sort { $a <=> $b } keys %tab_names ) {
  print FILE "#" if ($k==16 or $k== 21);
  print FILE "$k=>'$tab_names{$k}',\n"; 
}
print FILE ");\n\n";

close FILE;

### --- copy the File in webin(public/internal) Feature directory -------------

#   mv the tmp File (new version) into Webin (public version) 

sys ("mv ".$path."ProteinDefs.pm"." ".$path_webin."ProteinDefs.pm", __LINE__);

#   cp the taxonomy File from Webin public version to Webin internal version 

sys ("cp ".$path_webin."ProteinDefs.pm"." ".$path_webinnew."ProteinDefs.pm", __LINE__);

print "Data processed by $0 on ". ( scalar localtime ) . "\n";
