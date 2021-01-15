#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;

my @files = <@ARGV>;



my $var = 'PR   Project:36577;
XX
DE   Schistosoma mansoni genome sequence supercontig {1}
XX
KW   .
XX
OS   Schistosoma mansoni
OC   Eukaryota; Metazoa; Platyhelminthes; Trematoda; Digenea; Strigeidida;
OC   Schistosomatoidea; Schistosomatidae; Schistosoma.
XX
RN   [1]
RP   1-{SL}
RA   Aslett M.A.;
RT   ;
RL   Submitted (03-APR-2009) to the EMBL/GenBank/DDBJ databases.
RL   Aslett M.A., Wellcome Trust Sanger Institute, Pathogen Sequencing Unit,
RL   Wellcome Trust Genome Campus, Hinxton, Cambridge, Cambridgeshire. CB10 1SA,
RL   UNITED KINGDOM.
XX
RN   [2]
RA   Berriman M., Haas B.J., LoVerde P.T., Wilson R.A., Dillon G.P.,
RA   Cerqueira G.C., Mashiyama S.T., Al-Lazikani B., Andrade L.F., Ashton P.D.,
RA   Aslett M.A., Bartholomeu D.C., Blandin G., Caffrey C.R., Coghlan A.,
RA   Coulson R., Day T.A., Delcher A., DeMarco R., Djikeng A., Eyre T.,
RA   Gamble J.A., Ghedin E., Gu Y., Hertz-Fowler C., Hirai H., Hirai Y.,
RA   Houston R., Ivens A., Johnston D.A., Lacerda D., Macedo C.D., McVeigh P.,
RA   Ning Z., Oliveira G., Overington J.P., Parkhill J., Pertea M., Pierce R.J.,
RA   Protasio A.V., Quail M.A., Rajandream M.A., Rogers J., Sajid M.,
RA   Salzberg S.L., Stanke M., Tivey A.R., White O., Williams D.L., Wortman J.,
RA   Wu W., Zamanian M., Zerlotini A., Fraser-Liggett C.M., Barrell B.G.,
RA   El-Sayed N.M.;
RT   "The genome of the blood fluke Schistosoma mansoni";
RL   Unpublished.
XX
FH   Key             Location/Qualifiers';


my $dont_save_line = 0;

foreach my $file (@files) {

    open(WRITE, ">".$file.".updated");

    if (open(READ, "<$file")) {

	while (my $line = <READ>) {

	    if ($line =~ /^PR\s+Project:36577;/) {
		$dont_save_line = 1;
	    }
	    elsif (($line =~ /^XX\s*/) && $dont_save_line) {
		#  do nothing
	    }
	    elsif (($line =~ /^FH\s+Key\s+Location\/Qualifiers\s*/) && $dont_save_line) {
		print WRITE $var;
		$dont_save_line = 0;
	    }
	    else {
		print WRITE $line;
	    }

	}

	close(READ);
    }
    else {
	print "Could not read $file\n";
    }

    close(WRITE);

    #system("mv ".$file.".updated ".$file);
}

