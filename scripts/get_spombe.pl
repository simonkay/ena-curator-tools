#!/ebi/production/seqdb/embl/tools/bin/perl -w

#$Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_spombe.pl,v 1.2 2006/10/31 14:25:05 gemmah Exp $

use strict;

@ARGV == 1 || die "\n USAGE: $0 <input_file>\n";

my $input_file = $ARGV [0];

open (IN, "<$input_file") || die "cannot open $input_file: $!";
open (OUT,">$input_file.lis") || die "cannot open $input_file.lis: $!";

while (<IN>)
{
  chomp;
  my @fields = split;

  print OUT "$fields[4]\t$fields[$#fields-1]\t$fields[$#fields]\n";

}
print OUT "//\n";

close IN;
close OUT;


