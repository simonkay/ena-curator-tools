#!/ebi/production/seqdb/embl/tools/bin/perl -w
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/deprecated/blastn.pl,v 1.6 2006/11/20 15:41:54 lin Exp $

#===========================================================================
# Module Description:
# 
# This script is mainly to be used by datasub people to run blastn on every 
# new submission and have search results ready in every ds directory.
#
# The script only works on the machines of ebi1 cluster.
#
# The script can run blastn on any file that is in embl flat file format if 
# file names are provided on the command line. Multiple files can be provided 
# on the same command line (i.e.>blastn.pl file1 file2...). If no file names 
# are supplied on the command line the script processes all .sub files in the 
# current ds director.
#
# For each file the script copies the sequence and converts it to fasta
# format as required by the WU-blast. The blastn (of the WU-blast) is then run 
# against both embl and emblnew. One report is written for each search result. 
#
#
# MODIFICATION HISTORY:
#
# 18-AUG-2001 Quan Lin        Created.
#
# 24-AUG-2001 Nicole Redaschi, Quan Lin    Modified
# 14-AUG-2002 Quan Lin        removed path for bsub due to changes in system 
#                             setup and added sequin sub file .ffl
# 20-NOV-2006 Quan Lin        changed paths for blast and emboss.
#===========================================================================

use strict;
use DirHandle;
use SeqDBUtils;

#-----------------------------------------------------------------------------
# set environment for running seqret, bsub  and blastn
#-----------------------------------------------------------------------------

my $seqret = "/ebi/extserv/bin/EMBOSS-4.0.0/bin/seqret";

my $blastn = "/ebi/extserv/bin/wu-blast/blastn";

$ENV{"BLASTDB"} =  "/ebi/services/idata/latest/blastdb/";
$ENV{"BLASTFILTER"} = "/ebi/extserv/bin/wu-blast/filter/";
$ENV{"BLASTMAT"} = "/ebi/extserv/bin/wu-blast/matrix/";


#---------------------------------------------------------------------------
# handle command line
#---------------------------------------------------------------------------

my $usage = "**This script runs blastn on any files provided on the command line.\n".
            "**More than one file can be listed on the same command line.\n".
            "**The files should be in the embl flat file format.\n".
            "**If no file name is provided the script will process\n". 
            "     all the .sub and .ffl files in the current directory.\n";

my @files;

if (! @ARGV) # if no file is porvided on command line
{
  # find all .sub files in current directory and store them in an array

  my $dh = DirHandle->new ( "." ) || die "cannot opendir: $!"; 
  @files = sort grep { -f } grep { /\.sub$|\.ffl$/ } $dh->read ();
}
else
{
  @files = @ARGV;
}

if ( ! @files )
{
   print $usage;
   exit;
}

# process each file

foreach my $sub_file (@files)
{
 
  open (IN, "< $sub_file") || die "cannot open file $sub_file: $!";
  open (OUT, "> $sub_file.seq_temp") ||  die "cannot open file 
              $sub_file.seq_temp: $!";
 
  my $sequence;

  while (<IN>)
  {
    last if (/^SQ   /)
  }
  
  while (<IN>)
  {
    last if (m|//|);
    $sequence .= $_;
  } 
     
  print OUT $sequence;

  close (IN) || die "cannot close file $sub_file: $!";;
  close (OUT)|| die "cannot close file $sub_file.seq_temp: $!";

  # run seqret to convert sequence from embl to fasta format

  sys ("$seqret $sub_file.seq_temp -outseq $sub_file.fasta_temp", __LINE__ );

  # run blastn and write search result to a file 
  
   sys ("bsub -q production -I $blastn 'embl emnew' $sub_file.fasta_temp -V=20 -B=20 -E=20 -cpus 2 >$sub_file.blastn_temp", __LINE__);

  unlink ("$sub_file.seq_temp", "$sub_file.fasta_temp"); # delete these files
}




