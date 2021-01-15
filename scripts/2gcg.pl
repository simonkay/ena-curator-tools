#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/2gcg.pl,v 1.8 2006/10/31 11:16:00 gemmah Exp $
#
# (C) EBI 1998
#
# TOGCG:
# Converts a sequence into GCG format. Does automatic pre-processing so that
# user doesn't have to remove any ".." strings from the text or insert a
# ".." line before the start of the sequence.
#
# MODIFICATION HISTORY:
#
# 29-SEP-1998 Nicole Redaschi     Created.
# 10-NOV-1998 Pascal Hingamp      Modified to guess sequence type (DNA/PROT)
#                                 and to handle default output file
# 28-FEB-2001 Carola Kanz         added strict; removed toupper of argv
# 01-JUN-2001 Carola Kanz         first line in 'unknown format' not ignored any
#                                 more
# 07-JUN-2001 Carola Kanz         inserts '..' at the beginning of files without
#                                 any '..' ( interpreted as 'sequence only files' )
#                                 ( i.e. accepts now files without any '..' )
# 15-JUN-2001 Carola Kanz         reuse infile name if no outfile name is given
#                                 and add emacs backup file ending to infile
#===============================================================================

use strict;

#-------------------------------------------------------------------------------
# handle command line
#-------------------------------------------------------------------------------

my $usage  = "\n PURPOSE: Reformats sequence files to GCG format\n";
$usage .= "          Handles EMBL/GENBANK files automatically\n";
$usage .= "          For other file formats, adds '..' on the line before the\n";
$usage .= "          sequence\n\n";
$usage .= " USAGE:   /ebi/production/seqdb/embl/tools/curators/scripts/2gcg.pl\n";
$usage .= "          <inputfile> [<outputfile>] [<sequence type>]\n\n";
$usage .= "          <sequence type> can be P(rotein) or N(ucleotide)\n";
$usage .= "          (N is default). If no <outputfile> specified, writes output\n";
$usage .= "          to <inputfile> and copies backup of <inputfile> into\n";
$usage .= "          <inputfile.~n~>\n\n";


my $seqtype = "N";
my $MAX_COUNT = 200;


if ( @ARGV < 1 || @ARGV > 3 ) {
  die $usage;
}

my $infile  = $ARGV[0];
my $outfile = $infile;

if (@ARGV == 2) {
  if ( $ARGV[1] eq "P" or $ARGV[1] eq "N" ) {
    $seqtype = $ARGV[1];
  }
  else { 
    $outfile = $ARGV[1]; 
  }
}
elsif ( @ARGV == 3 ) {
  $outfile = $ARGV[1];
  if ( $ARGV[2] eq "P" ) {
    $seqtype = "P";
  }
  elsif ( $ARGV[2] ne "N" ) { 
    die $usage; 
  }
}

if ( $outfile eq $infile ) {
  # if no outfile name is given, rename the infile ( add emacs backup
  # ending ) and reuse the filename
  my $i = 1;
  while ( -e "$infile.~${i}~" ) {
    $i++
  }
  rename ( $infile, "$infile.~${i}~" );
  $infile = "$infile.~${i}~";
}

print "*** $infile\n";

if (!-T $infile) {die "\n ERROR: Can't open/use <input file>!\n".$usage};

my $tmp_file1 = $infile.'_gcg1';
my $tmp_file2 = $infile.'_gcg2';

#-------------------------------------------------------------------------------
# check for ".."
#-------------------------------------------------------------------------------

open ( IN,  "<$infile" )         || die "cannot open file $infile: $!";
open ( OUT, ">$tmp_file1" ) || die "cannot open file $tmp_file1: $!";

my ( $dotdot, $nuc_symb, $other_symb ) = (0,0,0);
my ( $mol_type, $prt_sym );

while ( <IN> ) {

  # EMBL or NCBI format
  if ( /^ID   / || /^LOCUS / ) {
    print OUT $_;

    if (/ [RD]NA[; ]/) {
      $mol_type = 'N';
    } 
    elsif ( /( PRT;| aa )/ ) {
      $mol_type = 'P';
    }
    while ( <IN> ) {
      $_ =~ s/\.\./__/g;
      if ($dotdot and $nuc_symb + $other_symb < $MAX_COUNT) {
	&count_symbols;
      }
      if ( /^SQ   Sequence /i || /^ORIGIN/ ) {
	$_ .= " ..\n";
	$dotdot++;
      }
      print OUT $_;
    }
    $dotdot or die " ERROR: Corrupted EMBL or GENBANK file format!";
  }
  # unknown format
  else {
    do {
      if ($nuc_symb + $other_symb < $MAX_COUNT) {
	&count_symbols;
      }
      if ( /\.\./ ) {
	$dotdot++;
	# symbols are counted from the beginning of the file as it might be a 
	# sequence only file without '..' at the beginning; in case there is
	# a '..' later on, restart counting
	$nuc_symb = 0; $other_symb = 0;
      }
      print OUT $_;
    } while <IN>;
    if ( $dotdot > 1 ) {
      die "file has more than one '..' divider";
    }
  }
}

close ( IN )  || die "cannot close file $infile: $!";
close ( OUT ) || die "cannot close file $tmp_file1: $!";



#-------------------------------------------------------------------------------
# determine sequence type
#-------------------------------------------------------------------------------

$mol_type = &guess_seq_type;

if ( $seqtype ne $mol_type ) {
  print "\nWARNING: Sequence is recognised by TOGCG as ".
        ($mol_type eq 'P' ? 'protein' : 'nucleotide').
        " rather than ".($seqtype eq 'P' ? 'protein' : 'nucleotide')."!\n";
}

#-------------------------------------------------------------------------------
# replace any "?-" and "U" if RNA
#-------------------------------------------------------------------------------

open ( IN,  "$tmp_file1" )  || die "cannot open file $tmp_file1: $!";
open ( OUT, ">$tmp_file2" ) || die "cannot open file $tmp_file2: $!";


## add '..' at the beginning of files without ( should be sequence only files ... )
if ( $dotdot == 0 ) {
  print OUT "..\n";
}

# find the ".."
while ( <IN> )
{
    print OUT $_;
    last if ( /\.\./ );
}

# replace all "?-"
my $wild_card;
if ($mol_type eq "N") {$wild_card = 'N'} else {$wild_card = 'X'};

while ( <IN> )
{
  s/[?-]/$wild_card/go;
  s/u/t/gi if ($mol_type eq "N");
  print OUT $_;
}
close ( IN )  || die "cannot close file $tmp_file1: $!";
close ( OUT ) || die "cannot close file $tmp_file2: $!";

#-------------------------------------------------------------------------------
# run reformat again
#-------------------------------------------------------------------------------

if ( system ( "reformat $tmp_file2 $outfile -lower -default") != 0) {
  print "\n ERROR running GCG reformat!\n\n";
}
else {
  print "\nReformated file writen to < $outfile >\n\n";
}

unlink ("$tmp_file1", "$tmp_file2");


#-------------------------------------------------------------------------------
# MAIN END
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# SUBS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# count nucleotide/protein sequence specific symbols
#-------------------------------------------------------------------------------
sub count_symbols {

     while (/[atgcu]/ig) {$nuc_symb++;} #core nucleotide symbols
     while (/[qeilfpxzbdhkmnrsvwy]/ig) {$other_symb++;} #all minus above
     if (/[qeilfpxz]/i) {$prt_sym = 1;} #unique protein symbols
   
}

#-------------------------------------------------------------------------------
# study symbol distribution to determine sequence type
#-------------------------------------------------------------------------------
sub guess_seq_type {

my ($type, $ratio);

if ($prt_sym) {return 'P'};

$ratio = $nuc_symb / ($nuc_symb + $other_symb);
if ($ratio > 0.8) { $type = 'N'; }
else { $type = &let_gcg_guess;}

return $type;
}

#-------------------------------------------------------------------------------
# run reformat to determine sequence type
#-------------------------------------------------------------------------------
sub let_gcg_guess {
system ( "reformat $tmp_file1 $tmp_file2 -lower -default" );

my $mol_type;
open ( IN, "$tmp_file2" ) || die "cannot open file $tmp_file2: $!";
while ( <IN> )
{
    if (($mol_type) = (/Type: (P|N)/))
    {
	last;
    }
}
close ( IN ) || die "cannot close file $tmp_file2: $!";

return $mol_type;
}
