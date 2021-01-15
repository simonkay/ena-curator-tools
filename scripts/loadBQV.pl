#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;

use bqv;

# temp script to load a bqv file
# >CU468594.2 Phrap Quality (Length:183171, Min: 0, Max: 99)
#8  8  8  9  8  7  6  7  7  16 16 11 11 21 11 11 12 15 14 10 9  9  8  6  6  
#...
#99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 
#99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 
#//
#>CU468599.2 Phrap Quality (Length:185997, Min: 0, Max: 99)
#99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 99 
#...

my $bqv = "/ebi/production/seqdb/embl/data/gpscan/sangerhs/bqv";

my $dbh = DBI->connect ('dbi:Oracle:', $ARGV[0], '',
			{PrintError => 1,
			 AutoCommit => 0,
			 RaiseError => 1 });
bqv::load_bqv($bqv,$dbh);
$dbh->commit;
