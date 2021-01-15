#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# MODULE DESCRIPTION
#
# Split files containing GenBank CON entries. One file is created for each 
# entry with sequence longer than 100000 bp. The acc# is used as file name
# with .con extension.Two lines (LOCUS and DEFINITION line) for each entry 
# with sequence shorter than 100000 bp are reported collectively in a file 
# named input_file_name.report. The data for these entries are reported
# collectivly in a file named: input_file_name.dat.
#
# USAGE:$0 <input_file_name>
#
# MODIFICATION HISTORY:
#
# 30-MAY-2001  Quan Lin       Created
#==============================================================================

use strict;

#------------------------------------------------------------------------------
# handel command line.
#------------------------------------------------------------------------------

@ARGV == 1 || die "\nUSAGE: Please provide a input file\n";

my $input_file_name = $ARGV[0];

my $count_long = 0;
my $count_short = 0;
my $total_entry = 0;

open (IN, "$input_file_name")|| die "cannot open $input_file_name: $!";
open (REPORT, "> $input_file_name.report") || die "cannot open $input_file_name.report for output: $!";
open (DAT, "> $input_file_name.dat") || die "cannot open $input_file_name.dat for output: $!";

while (<IN>)
{
  my $limit = 100000;
  my $keep;
  my $seqlength;

  if (/^LOCUS     /)
  {
    $total_entry++;
    $keep = $_;
    my @locus = split;
    $seqlength = $locus[2];
    
    while (<IN>)
    {
      $keep .= $_;
      last if /^ACCESSION /;
    }  
  }
    
  if ($seqlength >= $limit)
  {
    if (/^ACCESSION /)
    {
      my $acc_line = $_;
      my @accession = split;
      my $file_name = $accession[1];
     
      open (OUTPUT, "> $file_name.con") || die "cannot open $file_name.con: $!";
      $count_long++;
      print OUTPUT $keep;
     
      while (<IN>)
      {
	print OUTPUT;
	last if m|^//|;
      }

      close (OUTPUT);
    }	
  }
  elsif ($seqlength < $limit)
  {
    print DAT $keep;
    
    while (<IN>)
    {
      print DAT;
      last if m|^//|;
    }
    
    my @new_keep = split (/ACCESSION/, $keep);
    print REPORT "$new_keep[0]\n";
  }
}
      
close (IN) || die "cannot close file $input_file_name\n";
close (REPORT) || die "cannot close file $input_file_name.report\n";
close (DAT) || die "cannot close file $input_file_name.dat\n";

$count_short = $total_entry - $count_long;

print "Total number of entry: $total_entry.\n";
print "Number of entries with sequence longer than 100000 bp: $count_long.\n";
print "Number of entries with sequence shorter than 100000 bp: $count_short.\n";
print "One file created for each entry with sequence longer than 100000 bp.\n";
print "The rest of the entries are reported collectively in $input_file_name.report.\n";
print "The data for these eantries are kept in $input_file_name.dat.\n";

