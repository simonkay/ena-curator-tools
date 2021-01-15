#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/cleanup_letterdir.pl,v 1.1 2007/08/09 15:25:42 gemmah Exp $
#
#  MODULE DESCRIPTION:
#  deletes all files in the letter directory that are older than 60 days
#  ( techfiles, reports, logfiles, remarks etc... )
#
#  MODIFICATION HISTORY:
#  11-FEB-2003  Carola Kanz      Created.
#===============================================================================

use strict;
use DirHandle;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\nUSAGE: $0 [-test | -h]\n\n";
my $exit_status = 0;

( @ARGV == 0 || @ARGV == 1 ) || die $usage;

my $test = 0;

if ( defined $ARGV[0] ) {
  if ( $ARGV[0] eq "-test" ) {
    $test = 1;
  }
  else {
    print $usage;
    exit(255);
  }
}


my $dir = ( $test ) ? $ENV{"LETTERS_TEST"} : $ENV{"LETTERS"};

( defined $dir ) || die ( "ERROR: environment is not set\n" );

my $dh = DirHandle->new ( $dir ) || die ( "ERROR: cannot open directory: $!\n" );
my @files = sort grep { ! -d } grep { ! /\.cls$/ } map  { "$dir/$_" } $dh->read();

foreach my $file ( @files ) {
  if ( -M $file > 60 ) {
    print "delete $file\n";
    unlink ( "$file" ) || print "ERROR: could not remove $file: $!\n";
  }
  else {
    print "*** $file\n";
  }
}

print "Data processed by $0 on ". ( scalar localtime ) . "\n";

exit($exit_status);
