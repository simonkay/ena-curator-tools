#!/ebi/production/seqdb/embl/tools/bin/perl -w

####################################################################
#    $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/parsem.pl,v $ 
#    $Revision: 1.4 $
#    $Date: 2006/10/31 16:07:59 $ 
#    $Author: gemmah $  
#    $State: Exp $    $Lock: $
###################################################################
#              parser for EMBL nuc seq submission forms
#
#                   Pascal Hingamp June 1999
#
##########################################################################
# This script takes in 'new model' email forms (since Dec 98) and creates
# an EMBL flat file using the WEBIN flat flat generator. To this effect, the 
# script reads in data from the email form and translates it into a WEBIN 
# style 'global' file which is then used by the FlatFile.pm module to create 
# the actual flat file output.

# Although the number of email form submissions are dwindling fast, this script 
# was useful to test the idea that WEBIN subs can be regenerated from data coming from 
# sources other than the pure WEBIN CGI forms. In particular this script could be useful
# to study with a view to creating WEBIN submissions from existing db entries to allow 
# WEBIN based updates directly by submitters. The main differences will be 1) the data source 
# accessed either via a modified 'getff' C++ code which writes WEBIN data rather than
# standard flat files, or using the BioPerl EMBL flat file parser (see Ewan Birney or
# Henning Hermajacob) and 2) instead of writting just one global file, the update software
# should write the data in all the relevant individual CGI files (eg pI, pII, pIII, FEATURES,
# and each feature in an appropriately named file such as CDS_simple1 etc.). In this way it
# should be possible to create a WEBIN submission directory primed with data as if the seq had
# been submitted through WEBIN and send the submitter directly to a derivative of the SUMMARY page.
# From there the submitter can make his updates and send us an updated flat file, however he should be
# barred from editing things like the submitter reference (which is way I say SUMMARY page *derivative*).
# Attention should be put into assuring that confidential data is only accessed by the original 
# submitter (eg by asking him for the sequence as it stands or for the corresponding DS number which 
# only he should have...).
# Fianlly some mechanism should be implemented to take care of WEBIN unsupported features/qualifiers!
# Indeed not all legal qualifiers that might appear in a database flat file will find their corresponding 
# data tag in a WEBIN form. However these *must* be preserved and displayed in the flat file FT even if they
# can't be edited!
# That's it for now and good luck! - PH July 1999

use lib '/ebi/www/web/public/Services/webin';
use FlatFile;  
use Page;  
use Defs;  
use CGI;
use strict;
use vars qw/$OUTFILE @QUESTIONS %TRANSLATE %PROMPT $FORM $FILE $r_REPORT/;
$FILE = '/ebi/production/seqdb/embl/tools/curators/scripts/data/parsem.dta';
open REPORT, '>email_parser.cmt';
$r_REPORT = \*REPORT;
############################ MAIN ########################################
init_const();
my @files = get_files();
my $nb;
my $comments;
my $base;

foreach my $file (@files) {
  print $r_REPORT "=========================================================================\nProcessing $file:\n";
  (my $header, my @forms) = init($file);
  my ($form, $r_webin_feats, $seq, $length ,$outfile, $contamin);
  ($base) = ($file =~ /^(\w+)\./);

  foreach $form (@forms) {
    $nb++;
    if ($OUTFILE) {$outfile = $OUTFILE} else {$outfile = "$base".($nb>1?$nb:'').".sub"};
    print $r_REPORT "\nsequence $nb: flat file in < $outfile >\n";
    ($form, $seq, $length) = get_seq ($form);
    ($form,$contamin) = form_extract($form,"contamination        [");
    print $r_REPORT "  Vector contamination check: ";if ($contamin eq 'on') {print $r_REPORT "YES\n"} else {print $r_REPORT "NO\n"};
    $form = unwrap ($form);
    ($r_webin_feats, $form) = webin_transform ($seq, $length, $form, $nb);
    open OUT, ">$outfile";
    my $flat_file = new FlatFile (\*OUT, 
 				  '.',
				  "/WEBINdata$nb.tmp",0,0,0,0,
				  $r_webin_feats);
    $flat_file->print();
    close OUT;

    open (OUT, "> $base.info");
    $flat_file = new FlatFile (\*OUT, 
			       '.',
			       "/WEBINdata$nb.tmp",0,0,0,0,
			       $r_webin_feats);
    $flat_file->print_author(\*OUT);
    close OUT;

    unlink "WEBINdata$nb.tmp";
    $form = display_bad_lines($form);
    $comments .= $form;
  }
  write_out ("$base.report", $header.$comments);
  print $r_REPORT "\nCommented email form available in < $base.report >\n";
};
close REPORT;
# also write a copy of the parsing report to screen
open REPORT, 'email_parser.cmt';
open (RENAME ,'>'.$base.'.parsercmt');
foreach (<REPORT>) 
  {
    print $_;
    print RENAME "$_";
  }
close REPORT;
close RENAME;
unlink ('email_parser.cmt');
############################ SUBROUTINES #############################################
#get nuc seq from email form and reformat using WEBIN Page.pm method
sub get_seq {
  my $form = shift;
  my ($seq, $sequence, $real_length, $declared_length);
  ($seq) = ($form =~ /BEGINNING OF SEQUENCE:\s*(.*)END OF SEQUENCE/s);
  ($form,$declared_length) = form_extract($form,"Sequence length (bp) :");
  $declared_length =~ s/\D+//g; 
  $declared_length = 0 if $declared_length eq '';
  unless ($declared_length =~ /^\d+$/) {($declared_length) = ($declared_length =~ /(\d+)/)};
  # the following is to salvage fasta formats (starting with > sign) ruined by parser which
  # strips out > at lign start!
  if (defined ($seq) and !Page::reformat_static('.',$seq)) {
    $seq = '>'.$seq if Page::reformat_static('.','>'.$seq);print $r_REPORT "FASTA format!\n";
  };

  unless (defined ($seq) and $sequence = Page::reformat_static('.',$seq)) {
    print $r_REPORT "  * Warning * nucleotide sequence format not recognised, manual fiddling required!\n";
    if ($declared_length > 0) {$seq = ('N' x $declared_length)} else {$seq = '?'};
    return ($form, $seq, $declared_length);
  };
  $real_length = $sequence =~ tr/[ATGCMRWSYKVHDBN]//;
  if (!defined $declared_length or $declared_length < 1) {
    print $r_REPORT "  * Warning * no nucleotide sequence length in email form, using real seq. length ($real_length bp)!\n";
  }
  elsif ($real_length != $declared_length) {
    print $r_REPORT "  * Warning * real length of nucleotide sequence ($real_length bp) differs from declared length ($declared_length bp)!\n";
  };
  return ($form, $sequence, $real_length);
}
################################################################################
#create WEBIN data structures necessary for flat file generator
sub webin_transform {
  my $seq = shift;
  my $length = shift;
  my $form = shift;
  my $nb = shift;
  my (%data,$r_features,$r_FEATURES,$de,$r_authors,$organelle,$nuc,$pub,$conf_date,$clone,$virion);
 
  foreach my $key (keys %TRANSLATE) {#for data that map directly
    ($form,$data{$TRANSLATE{$key}}) = form_extract($form,$key);
  };
  ($form,$clone) = form_extract($form,"Clone (if >1)        :");
  if ($clone =~ /\w+/) {$data{'clone'} .= ' and ' . $clone};
  ($form,$r_authors) = get_authors  ($form);
  ($form,$organelle) = get_organelle($form);
  ($form,$nuc)       = get_nuc_type ($form);
  ($form,$pub)       = get_pub_type ($form);
  ($form,$conf_date) = get_conf     ($form);
  ($form,$virion)    = get_virion   ($form);
  ($form,$r_features,$r_FEATURES)= get_features ($form,$length);
  if (defined $data{'organism'}) {$de = $data{'organism'}.' '} else {$de = '? '};
  if (defined $data{'plasmid'} and $data{'plasmid'} eq 'on') {$data{'plasmid'} = '"**! submitter has ticked plasmid !**"'};

  open DATA, ">WEBINdata$nb.tmp";
  foreach (keys %data) {
    if (defined $data{$_} and $data{$_} =~ /\S+/) {print DATA $_.'='.CGI::escape($data{$_})."\n"}
    else {print DATA $_."=\n"}
  };
  print DATA "sequence=".CGI::escape($seq)."\n";
  print DATA "seq_length=$length\n";
  print DATA "1data_type=$pub\n";
  print DATA "sequenced_mol=$nuc\n";
  print DATA "$conf_date\n";
  print DATA "common=\n";
  print DATA "classification=unavailable through email parser\n";
  print DATA "organelle_type=$organelle\n";
  print DATA "viral_kind=$virion\n";
  print DATA "description=".CGI::escape($de)."\n";
  foreach (keys %$r_authors)  {print DATA $_."=".$$r_authors{$_}."\n"};
  foreach (keys %$r_features) {print DATA $_."=".$$r_features{$_}."\n"};
  close DATA;

  return ($r_FEATURES,$form);
}
##############################################################################
#get features out of email form and translate into WEBIN data
sub get_features {
  my $form = shift;
  my $seq_length = shift;
  my ($r_features,$r_FEATURES);
  my @list;
  $$r_FEATURES{'Citation'} = 1;
  return ($form,$r_features,$r_FEATURES) if $form !~ /Feature key\s+:/;
  #my $f; while ($form =~ /Feature key\s+:/g) {$f++}; my $e; while ($form =~ /Experimental evidence\s*\[.*?\]/g) {$e++};
  #if ($f != $e) {
    (my $feats) = ($form =~ /(Feature key\s+:.+)VII\. SEQUENCE INFORMATION/s);
    @list = split /Feature key/gs, $feats;foreach (@list) {$_ = 'Feature key'. $_};shift @list;
    $form =~ s/Feature key\s+:.+VII\. SEQUENCE INFORMATION/>>>>FEATURES<<<<\nVII. SEQUENCE INFORMATION/s;
  #} else {
  #  (@list) = ($form =~ /(Feature key\s+:.+?Experimental evidence\s*\[.*?\]\s*\n?)/gs);
  #  $form =~ s/Feature key\s+:.+Experimental evidence\s*\[.*?\]\s*\n?/>>>>FEATURES<<<<\n/s;
  #};
  FEATURE:foreach my $feat (@list) {
    my $note = ''; my ($nb,$key,@from,@to,$gene,$product,$codon,$EC,$comp,$exp);
    ($feat,$nb)      = form_extract($feat,"FEATURE NO.") if $feat =~ /FEATURE NO./;
    ($feat,$key)     = form_extract($feat,"Feature key           :");
    ($feat,@from)    = form_extract($feat,"From                  :");
    ($feat,@to)      = form_extract($feat,"To                    :");
    ($feat,$gene)    = form_extract($feat,"Gene name             :");
    ($feat,$product) = form_extract($feat,"Product name          :");
    ($feat,$codon)   = form_extract($feat,"Codon start 1, 2 or 3  :");
    ($feat,$EC)      = form_extract($feat,"EC number             :");
    ($feat,$comp)    = form_extract($feat,"Complementary strand  [");
    ($feat,$exp)     = form_extract($feat,"Experimental evidence [");
    $form =~ s/>>>>FEATURES<<<</$feat>>>>FEATURES<<<</s;
    my $orig = $key;
    if ($key =~ /\s+/) {
      $note .= "\"**! feature key given in email: $key !**\"";
      foreach (split /\s+/, $key) {if (defined $Defs::kind{$_}) {$key = $_; last}}
    };
    if (defined $Defs::kind{$key}) {print $r_REPORT "  Adding feature: $key".($orig eq $key?'':' (guess from "'.$orig.'"!)')."\n"} else {
      $note .= "\"**! feature key given in email: $key !**\"";
      print $r_REPORT "  Adding feature: misc_feature (unrecognised feature key \"$key\"!)\n";
      $key = 'misc_feature';
    };
    if ($key eq 'CDS') {
     ($r_features,$r_FEATURES) = make_CDS     ($r_features,$r_FEATURES,$nb,$key,\@from,\@to,$gene,$product,$codon,$EC,$comp,$exp,$note,$seq_length);
     }
    else {
     ($r_features,$r_FEATURES) = make_feature ($r_features,$r_FEATURES,$nb,$key,\@from,\@to,$gene,$product,$codon,$EC,$comp,$exp,$note,$seq_length);
    }
  };
  $form =~ s/>>>>FEATURES<<<<\n//s;
  return ($form,$r_features,$r_FEATURES);
}
##############################################################################
#create non CDS features for WEBIN
sub make_feature {
 my ($r_features,$r_FEATURES,$nb,$key,$r_from,$r_to,$gene,$product,$codon,$EC,$comp,$exp,$note,$seq_length) = @_;
 my (@from) = (@$r_from);
 my (@to) = (@$r_to);
 my $type = $Defs::kind{$key};
 $key =~ s/\'//;#WEBIN feature names like 5'UTR become 5UTR
 $$r_FEATURES{$key}++;
 my $prefix = $key.$$r_FEATURES{$key};
 my $exon_nb = 0;
 my ($to,$partial5,$partial3,$from)=('','','','');
 foreach $from (@from) {
   $exon_nb++;
   $to = shift @to;
   ($from,$to,my $partial5i,my $partial3i) = get_range ($from,$to,$comp,$seq_length);
   $partial5 = $partial5i if $exon_nb == 1;
   $partial3 = $partial3i if !@to;
   $$r_features{$prefix."exon$exon_nb"."5end"}=$from;
   $$r_features{$prefix."exon$exon_nb"."3end"}=$to;
 };
 $$r_features{$prefix.'exon_number'}=$exon_nb if $type eq 'exons';
 $$r_features{$prefix.'5end not complete'}=$partial5;
 $$r_features{$prefix.'3end not complete'}=$partial3;
 $$r_features{$prefix.'complementary'}=$comp;
 $$r_features{$prefix.'product'}=$product;
 $$r_features{$prefix.'gene'}=$gene;
 $$r_features{$prefix.'evidence'}= ($exp eq 'on'?'experimental':'non_experimental');
 $$r_features{$prefix.'note'}=$note;
 $$r_features{$prefix.'replace_truly'}='on' if $type eq 'replace';
 $$r_features{$prefix.'replace'}='"**! sequence? !**"' if $type eq 'replace';

 return ($r_features,$r_FEATURES);
}
##############################################################################
#create CDS features for WEBIN
sub make_CDS {
 my ($r_features,$r_FEATURES,$nb,$key,$r_from,$r_to,$gene,$product,$codon,$EC,$comp,$exp,$note,$seq_length) = @_;
 my (@from) = (@$r_from);
 my (@to) = (@$r_to);
 if (@from == 1) {$key = 'CDS_simple'} else {$key = 'CDS_segmented'};
 $$r_FEATURES{$key}++;
 my $prefix = $key.$$r_FEATURES{$key};
 my ($to,$partial5,$partial3,$from)=('','','','');
 if ($key eq 'CDS_simple') {
   $to = shift @to;
   $from = shift @from;
   ($from,$to,$partial5,$partial3) = get_range ($from,$to,$comp,$seq_length);
   $$r_features{$prefix."trans_region_from"}=$from;
   $$r_features{$prefix."trans_region_to"}=$to;
   $$r_features{$prefix.'trans_region_5end'}=$partial5;
   $$r_features{$prefix.'trans_region_3end'}=$partial3;
 } else {
   my $exon_nb = 0;
   foreach $from (@from) {
     $exon_nb++;
     $to = shift @to;
     ($from,$to,my $partial5i,my $partial3i) = get_range ($from,$to,$comp,$seq_length);
     $partial5 = $partial5i if $exon_nb == 1;
     $partial3 = $partial3i if !@to;
     $$r_features{$prefix."exon$exon_nb"."5end"}=$from;
     $$r_features{$prefix."exon$exon_nb"."3end"}=$to;
     $$r_features{$prefix."start_codon_from"}=$from if $exon_nb == 1;
     $$r_features{$prefix."start_codon_to"}=($from+2) if $exon_nb == 1;
     $$r_features{$prefix."stop_codon_from"}=($to-2) if !@to;
     $$r_features{$prefix."stop_codon_to"}=$to if !@to;
   };
   $$r_features{$prefix.'exon_number'}=$exon_nb;
   $$r_features{$prefix.'5end not complete'}=$partial5;
   $$r_features{$prefix.'3end not complete'}=$partial3;
   $$r_features{$prefix.'no_start_codon'}=$partial5;
   $$r_features{$prefix.'no_stop_codon'}=$partial3;
 };
 $$r_features{$prefix.'complementary'}=$comp;
 $$r_features{$prefix.'product'}=$product;
 $$r_features{$prefix.'gene'}=$gene;
 $$r_features{$prefix.'trans_region_experimental'}=$exp;
 $$r_features{$prefix.'note'}=$note;
 $$r_features{$prefix.'codon_start'}=$codon;
 (my $EC1, my $EC2, my $EC3, my $EC4) = ($EC =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/);
 $$r_features{$prefix.'EC_number_1'}=($EC1?$EC1:'');
 $$r_features{$prefix.'EC_number_2'}=($EC2?$EC2:'');
 $$r_features{$prefix.'EC_number_3'}=($EC3?$EC3:'');
 $$r_features{$prefix.'EC_number_4'}=($EC4?$EC4:'');
 return ($r_features,$r_FEATURES);
}

##############################################################################
#get locations and make validations
sub get_range {
  my ($from,$to,$comp,$length) = @_; 
  my ($partial5,$partial3);
  if ($comp ne 'on') {
    $partial5 = ($from =~ /\</ ?'on':'off');
    $partial3 = ($to   =~ /\>/ ?'on':'off');
  }
  else {
    $partial5 = ($from =~ /\>/ ?'on':'off');
    $partial3 = ($to   =~ /\</ ?'on':'off');    
  }
  ($from) = ($from =~ /(\d+)/);my $f = ($from?$from:'');
  ($to) = ($to =~ /(\d+)/);my $t = ($to?$to:'');
  if (!defined $from or $from<0 or $from>$length) {
    $from = ($comp eq 'on'?$length:1);
    print $r_REPORT "  * Warning * 'From' location out of range ('$f')! Using $from\n";
  }
  if (!defined $to or $to<0 or $to>$length) {
    $to = ($comp eq 'on'?1:$length);
    print $r_REPORT "  * Warning * 'To' location out of range('$t')! Using $to\n";
  };
  return ($from,$to,$partial5,$partial3);
}
##############################################################################
#init confidential date
sub get_conf{
   my $form = shift;
   my ($conf_lines,$day,$month,$year) = ('','01','JAN','1900');
   my %lmon = ('JANUARY'=>'JAN','FEBRUARY'=>'FEB','MARCH'=>'MAR','APRIL'=>'APR','MAY'=>'MAY','JUNE'=>'JUN',
	    'JULY'=>'JUL','AUGUST'=>'AUG','SEPTEMBER'=>'SEP','OCTOBER'=>'OCT','NOVEMBER'=>'NOV','DECEMBER'=>'DEC');
   ($form, my $date) = form_extract($form,'If confidential write the release date here :');
   ($form, my $conf) = form_extract($form,'Enter an X if you want these data to be confidential    [');
   
   if ($conf eq 'on' or $date =~ /\w+/) {
     if (($day,$month,$year) =    ($date =~ /(\d{1,2})[^\da-zA-Z]*([a-zA-Z]{3})[^\da-zA-Z]*(\d{2,4})/)) { } 
     elsif (($day,$month,$year) = ($date =~ /(\d{1,2})[^\da-zA-Z]*([a-zA-Z]{4,})[^\da-zA-Z]*(\d{2,4})/)) { $month = $lmon{uc $month}} 
     elsif (($day,$month,$year) = ($date =~ /(\d{1,2})[^\da-zA-Z]+(\d{1,2})[^\da-zA-Z]+(\d{2,4})/)) { $month = $Defs::month{$month-1}} 
     elsif (($month,$year) = ($date =~ /\D*([a-zA-Z]{3}).*(\d{2,4})/)) { $day = 1};
     $month = uc $month if defined $month;
     if (defined ($year) and $year<10) {$year += 2000} elsif (defined ($year) and $year == 99) {$year += 1900};
     unless (defined ($day) and defined ($month) and defined ($year) and 
	     $day>0 and $day<32 and 
	     defined ($Defs::mon_nr{$month}) and 
	     $year>1998 and $year<2010) {
       print $r_REPORT "  * Warning * confidential but can't make out the date! Using 31-DEC-2001...\n";
       ($day,$month,$year) = ('31','DEC','2001');
     }
     print $r_REPORT "  Confidential until $day-$month-$year (email form date: \"$date\")\n";
   };
   $conf_lines = "confidential_day=$day\nconfidential_month=$month\nconfidential_year=$year";
   return ($form,$conf_lines);
}
##############################################################################
#init publication type
sub get_pub_type{
   my $form = shift;
   my $type;
   my $pub;
   my @list = ('In preparation       [','Accepted             [',
	       'Published            [','Thesis/Book          [','No plans to publish  [');

   foreach (@list) {
     ($form,$type) = form_extract($form,$_);
     if ($type eq 'on') {($pub) = (/^([ \w]+)/)};
   };
   unless ($pub) {
     print $r_REPORT "  * Warning * publication type not explicitely ticked! Assuming Unpublished...\n";
     $pub ='Unpublished';
   };
   $pub =~ s/\s+$//;
   return ($form,$pub);
}
##############################################################################
#init organelle type
sub get_organelle{
   my $form = shift;
   my $type;
   my $organelle;
   my @list = (#old list need to delete it later
	       'Chloroplast         [',
	       'Mitochondrion       [',
	       'Chromoplast         [',
	       'Kinetoplast         [',
	       'Cyanelle            [',
	       #new list after migration
	       'mitochondrion               [',
	       'nucleomorph                 [',
	       'plastid                     [',
	       'mitochondrion:kinetoplast   [',
	       'plastid:chloroplast         [',
	       'plastid:apicoplast          [',
	       'plastid:chromoplast         [',
	       'plastid:cyanelle            [',
	       'plastid:leucoplast          [',
	       'plastid:proplastid          [');

   foreach (@list) {
     ($form,$type) = form_extract($form,$_);
     if ($type eq 'on') {($organelle) = (/^([\w:]+)/)};
   };
   $organelle = 'not an organelle' unless $organelle;
   return ($form,lc $organelle);
}
##############################################################################
#init virus type
sub get_virion{
   my $form = shift;
   my $type;
   my $virion;
   my @list = ('Proviral             [','Virion               [');
   foreach (@list) {
     ($form,$type) = form_extract($form,$_);
     if ($type eq 'on') {($virion) = (/^(\w+)/)};
   };
   $virion = 'non-viral' unless $virion;
   return ($form,lc $virion);
}
##############################################################################
#init nucleotide type
sub get_nuc_type {
   my $form = shift;
   my $type;
   my $nuc;
   my %hash = ('Genomic DNA          ['=>'DNA',
	       'cDNA to mRNA         ['=>'RNA',
	       'rRNA                 ['=>'DNA',
	       'tRNA                 ['=>'DNA',
	       'Genomic RNA          ['=>'RNA',
	       'cDNA to genomic RNA  ['=>'RNA');

   foreach (keys %hash) {
     ($form,$type) = form_extract($form,$_);
     if ($type eq 'on') {$nuc = $hash{$_}};
   };
   unless ($nuc) {
     print $r_REPORT "  * Warning * molecule type not explicitely ticked! Assuming DNA...\n";
     $nuc ='DNA';
   };
   return ($form,$nuc);
}
##############################################################################
#init citation authors
sub get_authors{
   my $form = shift;
   my (%authors, @authors, $nb);

   ($form,@authors) = form_extract($form,'Author \d             :');#only searches first 9 authors...
   $nb = 0;
   foreach (@authors) {
     my ($first, $last, $init) = ('','','');
     $nb++;#print $r_REPORT "$_ \t=> ";
     next unless /\w+/;
     if (($last,$init) = /^([a-zA-Z\- ]+)[ ,]+([A-Z\. ]+)$/) {# Smith, A. B.
       $authors{'1author'.$nb.'_lastname'} = $last;
       if ($init =~ /^([A-Z])\.?([A-Z\. ]+)$/) {
	 $first = $1;
	 $init = $2;
       };
       $authors{'1author'.$nb.'_firstname'} = $first;
       $authors{'1author'.$nb.'_middle'} = $init;
     }
     elsif (($first,$init,$last) = /^([a-zA-Z\-]+)\s+([A-Z\. ]+)\s+([a-zA-Z\- ]+)$/) {# Alfred B. Smith
       $authors{'1author'.$nb.'_lastname'} = $last;
       $authors{'1author'.$nb.'_firstname'} = $first;
       $authors{'1author'.$nb.'_middle'} = $init;
     }
     elsif (($init,$last) = /^([A-Z\. ]+)\s+([a-zA-Z\- ]+)$/) {# A. Smith
       $authors{'1author'.$nb.'_lastname'} = $last;
       if ($init =~ /^([A-Z])\.?([A-Z\. ]+)$/) {
	 $first = $1;
	 $init = $2;
       };
       $authors{'1author'.$nb.'_firstname'} = $first;
       $authors{'1author'.$nb.'_middle'} = $init;
     }
     elsif (($last,$init) = /^([a-zA-Z\-]+)(.+)/) {# Smith ???
       $authors{'1author'.$nb.'_lastname'} = $last;
       $authors{'1author'.$nb.'_firstname'} = $init;
      };
     #print $r_REPORT "first:$first  init:$init  last:$last\n";
   };
   $authors{"1author_number"} = $nb;

   return ($form, \%authors);
}
##############################################################################
#find values in email form associated with a prompt
sub form_extract {
  my $form = shift;
  my $prompt = shift;
  my $readable = $prompt;

  $prompt = escape($prompt);

  (my @values) = ($form =~ /$prompt(.*)\n/mg);
  if (@values) {
    $form =~ s/^($prompt)/~\tOK:$1/mg;
  }
  else {
    print $r_REPORT "  * Warning * form missing line\t\"$readable\" !\n";
    @values = ('');
  };

  foreach my $value (@values) {
    $value = '' unless $value;
    if ($value =~ /^(.*)\]\s*$/) {#if tick box [X]
      if ($1 =~ /\S+/) {$value = 'on'} else {$value = ''};
    }
    elsif ($value =~ /\w+/) {#if text value
      $value = Page::translate($value);
      $value =~ s/\s{2,}/ /g;
      $value =~ s/^\s+//;
      $value =~ s/\s+$//;
      if ($prompt =~ /^(Last name|First name|Author)/) {
	$value = Page::capitalize ($value);
      };
    };
  };
  return ($form,@values);
}
###############################################################################
#write mangled form to file
sub display_bad_lines {
  my $form = shift;

  #comment out all lines that are left from form itself
  $form =~ s/BEGINNING OF SEQUENCE:\n?(.*)END OF SEQUENCE/BEGINNING OF SEQUENCE:\n~\tOK:(...)\nEND OF SEQUENCE/s;
  $form =~ s/BEGINNING OF TRANSLATION:\n?(.*)END OF TRANSLATION/BEGINNING OF TRANSLATION:\n~\tOK:(...)\nEND OF TRANSLATION/s;

  foreach my $line (keys %PROMPT) {
    $line = escape ($line);
    $form =~ s/^(\s*$line)/~\tOK:$1/m;
  };
  print $r_REPORT "  Following email form lines not understood:\n" if $form =~ /^[^~]/m;
  foreach (split /\n/, $form) {print $r_REPORT "\t$_\n" unless /^~\s+OK:/};
  return $form;
}
###############################################################################
#write mangled form to file
sub write_out {
  my $file = shift;
  my $form = shift;

  open OUT, ">$file" or die "Can't open $file";
  print OUT $form;
  close OUT;
}
###############################################################################
#unwrap lines in email form
sub unwrap {
  my $form = shift;
  my ($line);
 
  $form =~ s/^\s+//gm;
  $form =~ s/^:/, /gm;
  $form =~ s/^>?\s*\n//gm;
  if (($line) = ($form =~ /(Address  \s+:.+?)Country  \s+/s)) {
    $line =~ s/\n/ /gs;
    $form =~ s/(Address  \s+:.+?)(?=Country  \s+)/$line\n/s
  };
  if (($line) = ($form =~ /(Title  \s+:.+?)Journal  \s+/s)) {
    $line =~ s/\n/ /gs;
    $form =~ s/(Title  \s+:.+?)(?=Journal  \s+)/$line\n/s
  };
  if (($line) = ($form =~ /(Note  \s+:.+?)VI. FEATURES /s)) {
    $line =~ s/\n/ /gs;
    $form =~ s/(Note  \s+:.+?)(?=VI. FEATURES )/$line\n/s
  };
  if (($line) = ($form =~ /(Product name\s+:.+?)Codon start/s)) {
    $line =~ s/\n/ /gs;
    $form =~ s/(Product name\s+:.+?)(?=Codon start)/$line\n/s
  };
  if (($line) = ($form =~ /(Institution  \s+:.+?)Address  /s)) {
    $line =~ s/\n/ /gs;
    $form =~ s/(Institution  \s+:.+?)(?=Address  )/$line\n/s
  };
  $form =~ s/,\s*,/,/g;
  $form =~ s/,\s*$//mg;
  $form =~ s/,(?=\S)/, /g;
  $form =~ s/\s+,/,/g;
  return $form;
}
###########################################################################
#escape regex chars
sub escape {
  my $txt = shift;
  $txt =~ s/([\/\[\]\(\)\{\}\+\*\.\?\^\$\|\#\@\$])/\\$1/g;
  $txt =~ s/\s{2,}/\\s+/g;
  return $txt;
}

###############################################################################
#do all boring initialisations
sub init {
  my $file = shift;
  #read in email form, put each sub form unit into string into array
  my (@forms,$prefix,$lines,$header,$content);
  #print STDERR "$file\n";
  open IN, $file or die "FATAL ERROR: can't open $file, $! !\n";
  while (<IN>) {
    s/^>+ ?>*//;#because *stupid* Netscape mail adds a darn > in front of "From   :"....
    $lines .= $_ unless /^\s*[-=\*_\+]+\s*$/;
  };
  close IN;
  $lines =~ s/^--Boundary .+$//mg;
  unless ($lines =~ s/1\) WEBIN: THE WORLD WIDE WEB SUBMISSION TOOL.+?If you have further questions after reading this form please contact//s)
    {$lines =~ s/To display this form properly choose.+?If you have further questions after reading this form please contact//s};

  $lines =~ s/These data will be shared among.+?Wendy Baker, EMBL nucleotide sequence database curator\)//s;

  ($header,$content) = split (/I.\s+CONFIDENTIAL\s+STATUS/, $lines, 2) or warn "UNPARSABLE FORM: no 'I.  CONFIDENTIAL STATUS' divider!\n";
  unless ($header =~ s/Return-path:.+?\nReferences:.+?\n//s)
    {$header =~ s/Return-path:.+?\nMessage-id:.+?\n//s};
  $header =~ s/^Content-.+:.+\n$//mg;
  $header =~ s/\n\s*\n/\n/sg;
  foreach my $line (keys %PROMPT) {
    $line = escape ($line);
    $header =~ s/^\s*$line.*\n//m;
  };
  print $r_REPORT ":::::::::::::::::Email form header:\n$header".":::::::::::::::::Email form header end.\n";
  push @forms, split (/I.\s+CONFIDENTIAL\s+STATUS/, $content);
  foreach my $form (@forms) {
    $form = 'I.  CONFIDENTIAL STATUS'.$form;
    unless ($form =~ /Last name            :/ == $form =~ /VII\. SEQUENCE INFORMATION/) {
      print $r_REPORT "  * Warning * number of form paragraphs might not match number of sequences in email?!\n";
    }
  };
  return ($header,@forms);
}
###############################################################################
#find all input files

sub get_files {
  #define IN and OUT streams
  my @files;
  if (@ARGV) {
    push @files, shift @ARGV;  
  } else {
    opendir DIR, ".";
    @files = readdir DIR;
    @files = grep /\.form/, @files;
    closedir DIR;
  };
  unless (@files) {
    print "\nPURPOSE : Converts e-mail form submissions into EMBL format flat files.\n\n".
          "          When no input or output file names are provided, processes all\n".
          "          *.form files in the current directory.\n".
          "          Writes output files named *.sub, *.info and *.report.\n\n".
          "USAGE :   $0\n".
          "          <inputfile> <outputfile>\n\n".
          "         <inputfile>    where inputfile is the name of the file to be parsed\n".
          "         <outputfile>   where outputfile is the name of the EMBL formatted\n".
	  "                        file produced.\n\n";
    exit;
  };  
  if (@ARGV) {
    $OUTFILE = shift @ARGV;
  }
  return @files;
}

###############################################################################
#initialise constants
sub init_const {
  my $line;

  open FORM, $FILE or die "can't open $FILE $! !";
  while (<FORM>) {
    $FORM .= $_;
    chop;
    next if /^\s*$/;
    $line++;
    $PROMPT{$_} = $line;
  };
  close FORM;
  #foreach (keys %PROMPT) {print $r_REPORT $_."=".$PROMPT{$_}."\n";};

#Translate used to map data from email form prompts to WEBIN data names
%TRANSLATE = (  
 "Last name            :"=>'lastname',
 "First name           :"=>'firstname',
 "Middle initials      :"=>'middlename',
 "Department           :"=>'department',
 "Institution          :"=>'institution',
 "Address              :"=>'address',
 "Country              :"=>'country1',
 "Telephone            :"=>'telefon',
 "Fax                  :"=>'FAX',
 "Email                :"=>'e-mail',
 "Title                :"=>'1title',
 "Journal              :"=>'1possessions',
 "Volume               :"=>'1volume',
 "First page           :"=>'1first%20page',
 "Last page            :"=>'1last%20page',
 "Year                 :"=>'1year',
 "Institute (if thesis):"=>'1university',
 #"Sequence length (bp) :"=>'seq_length',   because now real seq length used!
 "Circular             ["=>'circular',
 "Organism             :"=>'organism',
 "Sub species          :"=>'sub_species',
 "Plasmid (natural)    :"=>'plasmid',
 "Strain               :"=>'strain',
 "Cultivar             :"=>'cultivar',
 "Variety              :"=>'variety',
 "Isolate/individual   :"=>'isolate',
 "Country(:region)     :"=>'country',
 "Developmental stage  :"=>'dev_stage',
 "Tissue type          :"=>'tissue_type',
 "Cell type            :"=>'cell_type',
 "Cell line            :"=>'cell_line',
 "Clone                :"=>'clone',
 "Clone library        :"=>'clone_lib',
 "Chromosome           :"=>'chromosome',
 "Map position         :"=>'map',
 "Haplotype            :"=>'haplotype',
 "Natural host         :"=>'specific_host',
 "Laboratory host      :"=>'lab_host',
 "Macronuclear         ["=>'macronuclear',
 "Germline             ["=>'germline',
 "Rearranged           ["=>'rearranged',
 "Note                 :"=>'note'
	     );
}
