#!/ebi/production/seqdb/embl/tools/bin/perl -w

#$Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/make_precon.pl,v 1.2 2006/10/31 15:56:35 gemmah Exp $

use strict;

@ARGV == 1 || die "\n USAGE: $0 <input_file>\n";

my $input_file = $ARGV [0];

open (IN, "<$input_file") || die "cannot open $input_file: $!";
open (OUT,">$input_file.ac") || die "cannot open $input_file.ac: $!";

my (@acc, @seqlen, @over_lap, @data);

while (<IN>)
{ 
  last if m|//|;
  chomp;
  @data = split (/\s+/, $_);
  push (@acc, $data[0]);
  push (@seqlen, $data[1]);
  push (@over_lap, $data[2]);
}


for (my $i = 0; $i<=$#acc; $i++)
{
  print OUT "$acc[$i] $over_lap[$i] forward\n";
  if ($over_lap[$i] == 0 and $i<$#acc)
  {
    print OUT "gap() forward\n";
  }
}

close IN;
close OUT;


