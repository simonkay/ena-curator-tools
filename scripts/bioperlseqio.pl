#!/ebi/production/seqdb/embl/tools/bin/perl -w
unshift @INC,"/ebi/extserv/bin/perl/lib/site_perl/";

use Bio::SeqIO;

$in  = Bio::SeqIO->new(-file => "</homes/faruque/temp.embl",
		       -format => 'EMBL');

$out = Bio::SeqIO->new(-file => ">/homes/faruque/temp.OUT.embl",
		       -format => 'EMBL');

while ( my $seq = $in->next_seq() ) {$out->write_seq($seq); }



