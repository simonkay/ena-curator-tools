#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/parse_jitterbug.pl,v 1.3 2006/11/17 16:47:27 lin Exp $
#
#  (C) EBI 2001
#
#  MODULE DESCRIPTION:
#
#  Parses commands from downloaded jitterbug mails.
#
#  MODIFICATION HISTORY:
#
#  13-JUN-2001  Nicole Redaschi  created.
#
#===============================================================================

use strict;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------
my $usage = "\n PURPOSE: Processes all the Webin submission messages that have been\n".
            "          downloaded from Submissions Jitterbug, and writes the copy\n".
	    "          commands in a .csh file.\n\n".
	    " USAGE:   $0 <inputfile>\n\n".
	    "          <inputfile> where inputfile is the name of file containing the\n".
	    "                      downloaded messages\n\n";
( @ARGV == 1 ) ||
    die $usage;

my $infile = $ARGV[0];
my $outfile = $infile.".csh";

open ( IN, "< $infile" ) || die "cannot open file $infile: $!";
open ( OUT, "> $outfile" ) || die "cannot open file $outfile: $!";

print OUT "#!/usr/bin/csh\n\n";
print OUT "umask 006\n\n\n";

while ( <IN> )
{
   if ( /^Subject: / )
   {
      print OUT "# ", $_;
   }
   elsif ( / were|was submitted by / )
   {
      print OUT "# ", $_, "\n";
   }
   elsif ( /copy_submission.csh/ || /COMMENT/ )
   {
      print OUT $_, "\n";
   }
}

close ( IN ) || die "cannot close file $infile: $!";
close ( OUT ) || die "cannot close file $outfile: $!";

chmod ( 0770, $outfile );
