#!/ebi/production/seqdb/embl/tools/bin/perl -w

require 5.004;

use strict;
use Carp;
use DBI;
use Getopt::Long;

my $db;

my $opt_text = 0;
my $opt_html = 0;

GetOptions("t|text" => \$opt_text,
           "h|html" => \$opt_html);

if (!defined($ARGV[0]) || (!$opt_text && !$opt_html) || ($opt_text && $opt_html))
{
   die "Usage: $0 -t(ext) | -h(tml) <connection>\n";
}

my %divisions = (
   'PHG' => 'Bacteriophage', 
   'EST' => 'ESTs', 
   'FUN' => 'Fungi', 
   'GSS' => 'GSSs',
   'HTG' => 'HTG',
   'HTC' => 'HTC',
   'HUM' => 'Human',
   'INV' => 'Invertebrates', 
   'ORG' => 'Organelles', 
   'MAM' => 'Other Mammals',
   'VRT' => 'Other Vertebrates',
   'PAT' => 'Patents',
   'PLN' => 'Plants',
   'PRO' => 'Prokaryotes',
   'ROD' => 'Rodents', 
   'STS' => 'STSs',
   'SYN' => 'Synthetic', 
   'UNC' => 'Unclassified',  
   'VRL' => 'Viruses');

eval
{
   $db = DBI->connect ('dbi:Oracle:', $ARGV[0], '',
      { RaiseError => 1, PrintError => 0, AutoCommit => 0 });

   # get divisions
   
   my $sth;
   $sth = $db->prepare(
      "select    c.division, to_char (count (*), '999,999,999,999'), 
                 to_char (sum (b.seqlen), '999,999,999,999')
       from      dbentry a, bioseq b, division c
       where     a.entry_name = c.entry_name and a.bioseqid = b.seqid 
       group     by c.division 
       order     by c.division");

      $sth->execute;

      print_header ();

      my @row;
      while (@row = $sth->fetchrow_array) {
        
         #
         # remove excess whitespaces
         #
         
         $row[0] =~ s/^\s+|\s+$//g;
         $row[1] =~ s/^\s+|\s+$//g;
         $row[2] =~ s/^\s+|\s+$//g;

         print_row ($row[0], $row[1], $row[2]);
      }

   $sth = $db->prepare(
      "select    to_char (count (*), '999,999,999,999')
       from      division");
    
      $sth->execute;
      @row = $sth->fetchrow_array;
      $row[0] =~ s/^\s+|\s+$//g; 

      my $entries = $row[0];

 $sth = $db->prepare(
      "select    to_char (sum (b.seqlen), '999,999,999,999')
       from      dbentry a, bioseq b, division c
       where     a.entry_name = c.entry_name and a.bioseqid = b.seqid");
              
      $sth->execute;
      @row = $sth->fetchrow_array; 
      $row[0] =~ s/^\s+|\s+$//g; 
        
      my $nucleotides = $row[0]; 

      print_footer ($entries, $nucleotides);
};

if ($@)
{
   die ("$DBI::errstr\n");
}

$db->disconnect ();

sub print_header
{
   if ($opt_text)
   {
      print "Division               Entries     Nucleotides\n";
      print "----------------- ------------ ---------------\n";
   }
   else
   {
#print "<html>\n";
#print "<body>\n";

      print "<table border>\n";
      print "<tr>\n";
      print "<td align = \"left\"><b>Division</b></td>\n";
      print "<td align = \"right\"><b>Entries</b></td>\n";
      print "<td align = \"right\"><b>Nucleotides</b></td>\n";
      print "</tr>\n";
   }
}

sub print_footer
{
   my ($entries, $nucleotides) = @_;

   if ($opt_text)
   { 
      print "                  ------------ ---------------\n";
      printf ("Total             %12s %15s\n", $entries, $nucleotides);
   }   
   else
   { 
      print "<tr>\n";
      print "<td align = \"left\"><b>Total</b></td>\n";
      print "<td align = \"right\"><b>$entries</b></td>\n";
      print "<td align = \"right\"><b>$nucleotides</b></td>\n";
      print "</tr>\n";

      print "</table>\n";

#print "</body>\n";
#print "</html>\n";
   }
}

sub print_row
{ 
   my ($division, $entries, $nucleotides) = @_;

   if ($opt_text)
   { 
      printf ("%-18s%12s%16s\n", $divisions{$division}, $entries, $nucleotides);
   } 
   else
   { 
      print "<tr>\n";    
      print "<td align = \"left\">$divisions{$division}</td>\n";        
      print "<td align = \"right\">$entries</td>\n";       
      print "<td align = \"right\">$nucleotides</td>\n";
      print "</tr>\n";
   }      
} 
