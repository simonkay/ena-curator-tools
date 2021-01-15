#!/ebi/production/seqdb/embl/tools/bin/perl -w

#------------------------------------------------------------------------------#
#                                                                              #
# delete_old_files <days> <path>                                               #
#   deletes files older than <days> and matching the <path>                    #
#                                                                              #
# 8-Aug-2003  F. Nardone  Created                                              #
#                                                                              #
#------------------------------------------------------------------------------#

use strict;

if ( $#ARGV < 1 ||       # not enough arguments
     $ARGV[0] =~ /\D/ ) {# <days> must be numeric
  die <<USAGE;
 delete_old_files <days> <path>
   deletes files older than <days> and matching the <path>
   
USAGE
}

my( $days, @files ) = @ARGV;

foreach my $node ( @files ) {
  if ( -f( $node ) && -M( $node ) > $days ) {
    unlink( $node) or
      print( STDERR "Can`t remove '$node'.\n$!\n" );
  }
}
