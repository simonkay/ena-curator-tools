#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# loribot.pl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/loribot.pl,v 1.14 2011/11/29 16:33:38 xin Exp $
#
#  DESCRIPTION:
#
#  reads a report file from LoriBlack (NCBI) to 
#  output a datasubs-friendly version including ds and curator
#
#  MODIFICATION HISTORY:
#
#  20-08-2004 Nadeem Faruque   Created
#  08-03-2004 Nadeem Faruque   Improved after 3rd set of error files
#                              Gets AC from GI numbers
#                              
# 
#===============================================================================

use strict;
use DBI;
use SeqDBUtils2;
use LWP::Simple;   
use LWP::UserAgent;
use Data::Dumper;

select(STDERR); $| = 1; # make unbuffered
select(STDOUT); $| = 1; # make unbuffered

########### Globals - constants ###########
my $maintainerEmailAddress = "xin\@ebi.ac.uk";
# undef this if no-one looking after it

my $totalErrorCountsFile = "/ebi/production/seqdb/embl/data/collab_exchange/logs/loribot.errors.count";

my $gi2acUrl = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=Nucleotide&id=";

# Errors not handled - syphoned off to a seperate file
# this list is of regular expressions of them
my @errorTypesNotDone = (
			 "Protein feature has description but no name");

### Data structures
# @errors = { 'AC'      => "accession number",
#             'ACV'     => sequence version,
#             'GI'      =>  Genbank ID,
#             'ERROR'   => "Main error message",
#             'DETAILS' => "Further error details",
#             'DS'      => "ds number for AC",
#             'CURATOR' => "curator name" (if eq "" -> update associate"
#           }

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Reads Lori Black data reports from the NCBI\n\n".
    " USAGE:   $0\n".
    "          [user/password\@instance] [-qhvm] filename\n\n".
    "   <user/password\@instance>\n".
    "                   where <user/password> is taken automatically from\n".
    "                   current unix session\n".
    "                   where <\@instance> is either \@enapro or \@devt\n".
    "   -q              quiet (no \"Connecting to ...\" messages\n".
    "   -h              shows this help text\n".
    "   -v              verbose output\n".
    "   -m              Sends reports to Jitterbug\n\n";
my $time1;
my $database = "";
my $inFile  = "";
my $quiet   = 0;
my $mail    = 0;
my $verbose = 0;
if (@ARGV > 1 ){
    ( $ARGV[0] =~ /^-h/i ) 
	&& die $usage;
    for ( my $i = 0; $i < @ARGV; ++$i ){
	
        if ($ARGV[$i] =~ /^\/\@(\w+)$/) {
            $database = $1;
	} 
	elsif (!( $ARGV[$i] =~ /^-/)){
	    $inFile = $ARGV[$i]
	    }
	elsif ( $ARGV[$i] =~ /-q(uiet)?/i){
	    $quiet = 1;
	}
	elsif ( $ARGV[$i] =~ /-m(ail)?/i){
	    $mail = 1;
	}
	elsif ( $ARGV[$i] =~ /-v(erbose)?/i){
	    $verbose = 1;
	}
	elsif ( $ARGV[$i] =~ /-h(elp)?/i){
	    die $usage;
	}
	else {	    
	    die ( "$ARGV[$i] not recognised\n".$usage );
	}
    }
}
else{
    die "$usage";
}
#($verbose) ||
 open(STDERR, "> loriSTDERR.log") || die "Could not create the file loriSTDERR.log";

sub pid2ac($$){
    my $dbh    = shift;
    my $pid    = shift;
    my $ac     = "UNKNOWN";

    my $pid2acquery = $dbh->prepare("select d.primaryacc# 
	    FROM  cdsfeature p, dbentry d
	    WHERE p.protein_acc = ?
	    AND   p.bioseqid = d.bioseqid");
    $pid2acquery->execute($pid)
	|| print STDERR "Can't map pid $pid to ac: $DBI::errstr";
    while (my @results = $pid2acquery->fetchrow_array) {
	$ac = $results[0];
    }
    $pid2acquery->finish;
    return $ac;
}

sub gi2ac($){
    my $gi         = shift;
    my $userAgent  = LWP::UserAgent->new;
    my $request    = HTTP::Request->new( GET => $gi2acUrl.$gi );
    my $urlDataRaw = $userAgent->request( $request );
    my $urlData    = $urlDataRaw->as_string;
    if ( $urlData =~ /Server Error/ ) {
	print STDERR $gi2acUrl.$gi."\n gave the error $urlData\n";
        return "UNKNOWN";
    }
    if ( $urlData =~ /<Item Name="Extra" Type="String">gi\|$gi\|emb\|(\w+)\./s ) {
	return $1;
    }
    else{
	print STDERR $gi2acUrl.$gi."\n gave the reply $urlData\n";
        return "UNKNOWN";
    }
    #http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=Nucleotide&id=572829134
    # http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Search&db=Nucleotide&term=AAC72193[accn]&doptcmdl=Brief
# refsef->original ac probably best a horrible call to viewer (or better still, srs)  http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=nucleotide&qty=1&c_start=1&list_uids=50953925&uids=&dopt=gb&dispmax=5&sendto=&fmt_mask=294980&truncate=294912&less_feat=68&from=1&to=2&extrafeatpresent=1
}
            
sub getErrorsFromFile($$\@){
    my $dbh    = shift;
    my $inFile = shift;
    my $errors = shift;
    (-r $inFile) or 
	die "File \"$inFile\" not found\n";
    open (FILE, "<$inFile" ) 
	|| die ("Cannot open cannot $inFile\n");
    my $errorsNotDone = 0;
    open (NOT_DONE, ">$inFile.not_done" ) 
	|| die ("Cannot open cannot $inFile.not_done\n");
    
    my $latestError = { 'AC'      => "UNKNOWN",
			'ACV'     => 0,
			'GI'      => 0,
			'ERROR'   => "",
			'DETAILS' => ""
			};
    READLINE:while(<FILE>){
	chomp(my $latestLine = $_);
	if ($latestLine =~ /^\s*$/){
	    next;
	}
	foreach my $errorTypeNotDone (@errorTypesNotDone){
	    if($latestLine =~ /$errorTypeNotDone/is){
		print NOT_DONE $latestLine."\n";
		$errorsNotDone++;
		next READLINE;
	    }
	}
	my $latestError;
	if ($latestLine =~ /^((ERROR[:\s]+.*)|(WARNING[:\s]+.*))\s+FEATURE[:\s]+(.*)$/){
	    $latestError = { 'AC'      => "",
			     'ACV'     => 0,
			     'GI'      => 0,
			     'ERROR'   => "$1",
			     'DETAILS' => "$4"
			     };
	}
	elsif ($latestLine =~ /^((ERROR[:\s]+.*)|(WARNING[:\s]+.*))\s+BIOSEQ[:\s]+(.*)/){
	    $latestError = { 'AC'      => "",
			     'ACV'     => 0,
			     'GI'      => 0,
			     'ERROR'   => "$1",
			     'DETAILS' => "$4"
			     };
	}
	elsif ($latestLine =~ /^((ERROR[:\s]+\[.*\])|(WARNING[:\s]+\[.*\]))\s+(.*)$/){
	    $latestError = { 'AC'      => "",
			     'ACV'     => 0,
			     'GI'      => 0,
			     'ERROR'   => "$1",
			     'DETAILS' => "$4"
			     };
	}
	else{
	    print "Cannot parse error in line $latestLine\n";
	    next;
	}
	if ($$latestError{'DETAILS'} =~ /[:\s]+\(emb\|([A-Z]{1,4}\d{5,9})\.(\d+)\|/) {
	    $$latestError{'AC'}  = $1;
	    $$latestError{'ACV'} = $2;
	} elsif ($$latestError{'DETAILS'} =~ /gi\|(\d+)\|emb\|([A-Z]{1,4}\d{5,9})\.(\d+)\|/){
	    $$latestError{'GI'}  = $1;
	    $$latestError{'AC'}  = $2;
	    $$latestError{'ACV'} = $3;
	} elsif ($$latestError{'DETAILS'} =~ /gi\|(\d+)/){
	    $$latestError{'GI'}  = $1;
	    $$latestError{'AC'}  = gi2ac($$latestError{'GI'});
	} elsif ($$latestError{'DETAILS'} =~ /^([A-Z]{1,4}\d{5,9}):\1.(\d+)/){
	    $$latestError{'AC'}  = $1;
	    $$latestError{'ACV'} = $2;
	} else {
	    $$latestError{'AC'}  = "UNKNOWN";
	    print "No parsable GI or AC in line \n $latestLine\nDetails: $$latestError{'DETAILS'}\n";
	}
	if ($$latestError{'AC'} =~ /^[A-Z]{3}\d+$/){
	    $$latestError{'AC'} = pid2ac($dbh,$$latestError{'AC'});
	}
	
	push (@$errors, $latestError);
    }
#    if ($latestError ne ""){
#	push (@$errors, $latestError);
#    }
    close(FILE);
    close(NOT_DONE);
    if ($errorsNotDone == 0) {
	unlink("$inFile.not_done");
    }
    else{
	print "$errorsNotDone errors not done (saved to $inFile.not_done)\n";
    }
    return;
}

sub outputErrors(\@$){
    my $errors  = shift;
    my $outFile = shift;
    my $currentCurator = " ";
    my $currentDS      = " ";
    my $lastAC = " ";
    my $lastError = " ";
    my %acList;
    open (OUT, ">$outFile" ) 
	|| die ("Cannot open cannot $outFile\n");
    select (OUT);
    foreach my $error (@$errors){
	$acList{$$error{'AC'}} = 1;

	if ($$error{'CURATOR'} ne $currentCurator){
	    print "\n======================================================\n"
		."= $$error{'CURATOR'} =\n";
	    for (my $i = 0; $i < length($$error{'CURATOR'}); $i++){
		print "=";
	    }
	    print "====\n";
	    $currentCurator = $$error{'CURATOR'};
	}
	# normalise DS's
	if ($$error{'DS'} ne  $currentDS){
	    print "\n"
		." ds $$error{'DS'}\n"
		."----------\n";
	    $currentDS = $$error{'DS'};
	}
	# normalise AC's
	if ($$error{'AC'} ne $lastAC){
	    $lastAC = $$error{'AC'};
	    print "$$error{'AC'}.$$error{'ACV'} (GI:$$error{'GI'})\n";
	}
	print " $$error{'ERROR'}\n"
	    . "  Details: $$error{'DETAILS'}\n";
    }

    select (STDOUT);
    close (OUT);

    open (OUT_AC, ">$outFile.ac" ) 
	|| die ("Cannot open cannot $outFile.ac\n");
    print OUT_AC join("\n", (sort (keys %acList)))."\n";
    close (OUT_AC);
}

sub mailErrors($$\@){
    my $database   = shift;
    my $inFile  = shift;
    my $errors  = shift;
    my $address = "test-upd\@ebi.ac.uk";
    my $url     = "http://jitterbug.ebi.ac.uk/cgi-bin/test-upd.private/incoming?page=9999";
    if ($database =~ /enapro/i){
	$address = "updates\@ebi.ac.uk";
	$url = "http://jitterbug.ebi.ac.uk/cgi-bin/embl-upd.private/incoming?page=9999";
    }
    
    my $currentCurator = " ";
    my $currentDS      = " ";
    my $lastAC = " ";
    my $fh;
    my $filename = $ENV{'USER'}.time();
    my $acCount = 0;
    foreach my $error (@$errors){
	if (uc($$error{'CURATOR'}) ne uc($currentCurator)){
	    if ($currentCurator ne " "){
		close($fh);
		system("mailx -s \"$inFile errors for $currentCurator ($acCount entries)\" $address < $filename");
		sleep(3); # try to wait so that the mailserver + jitterbug will maintain order
		$acCount   = 0;
		$currentDS = " ";
	    }
	    open($fh, ">$filename")
		|| die "Could not open temp file $filename\n";
	    $currentCurator = $$error{'CURATOR'};
	}
	# normalise DS's
	if ($$error{'DS'} ne  $currentDS){
	    print {$fh} "\n\n"
		." ds $$error{'DS'}\n"
		."----------\n";
	    $currentDS = $$error{'DS'};
	}
	# normalise AC's
	if ($$error{'AC'} ne $lastAC){
	    $acCount++;
	    $lastAC = $$error{'AC'};
	    print {$fh} "\n$$error{'AC'}.$$error{'ACV'}\n";
	    ($$error{'AC'} ne "UNKNOWN") and 
		print {$fh} "  http://www.ebi.ac.uk/ena/data/view/$$error{'AC'}\n";
	    ($$error{'GI'} > 0 ) and 
		print {$fh} "  http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=nucleotide&val=$$error{'GI'}\n";
	}
	print {$fh} "  $$error{'ERROR'}\n"
	    . "  $$error{'DETAILS'}\n";
    }
    if ($currentCurator ne " "){
	close($fh);
	system("mailx -s \"$inFile errors for $currentCurator ($acCount entries)\" $address < $filename");
    }

    unlink($filename)
	|| die "Could not delete temporary file $filename\n";
    print "Sent threads to Jiiterbug, please visit\n".
	" $url\n\n";
}

sub sortErrors(\@){
    # sort by curator, ds, AC, error
    my $errorList = shift;

    @$errorList = map { $_->[0] }
      sort {
        my @a_list = split /(\D+)/, $a->[1];
        my @b_list = split /(\D+)/, $b->[1];
        for ( my $i = 1 ; $i < @a_list ; $i++ ) {
            last if $i >= @b_list;
            my $result;
            if ( $i % 2 ) {
                $result = $a_list[$i] cmp $b_list[$i];
            } else {
                $result = ( $a_list[$i] || 0 ) <=> ( $b_list[$i] || 0 );
            }
            return $result if $result;
        }
        return 0;
      }
      map {
        [  $_,
	   $_->{'CURATOR'}."\t".$_->{'DS'}."\t".$_->{'AC'}."\t".$_->{'ERROR'}
        ]
      } @$errorList;
}    

# Generalise old curators into a single group
sub mergeCurators(\@){
    my $errors = shift;
    foreach my $error(@$errors){
	if( $error->{'CURATOR_STATUS'} ne "1") {
	    $error->{'CURATOR'} = "OLD CURATOR";
	} else{
	    $error->{'CURATOR'} =~ s/^ops\$([^,]+,)?(.+)/$2/;           # remove OPS$ and also repetitive names
	    $error->{'CURATOR'} =~ s/^datalib,(.+)/$1/i;   # activities done as datalib listed by curator
	    $error->{'CURATOR'} =~ s/^datalib$/DATALIB/;   # datalib capitalised
	}
    }
}

# Tally error types (before rewording)
sub tallyErrors(\@){
    my $errors = shift;
    my %newErrorCounts;
    foreach my $error(@$errors){
	my $errorName = $error->{'ERROR'};
	
#	#Some errors are just too varied to maintain in this form - should probably merge
#	$errorName =~ s/(tRNA )\(AAA\) (does not match amino acid )\(P/Pro\) (specified by genetic code).*/$1$2$3/;
	
	if (defined($newErrorCounts{$errorName})) {
	    $newErrorCounts{$errorName}++;
	} else {
	    $newErrorCounts{$errorName} = 1;
	}
    }
    return %newErrorCounts;
}

# Read in old totals
sub errorTotalsRead(){
    my %oldErrorCounts;

    if ( -e $totalErrorCountsFile ) {
	my $errorTotal = 0;
	open( my $errors_in, "<$totalErrorCountsFile" )
	    || die "cannot open file $totalErrorCountsFile: $!";
	while (<$errors_in>) {
	    chomp;
	    if (/^(\d+)\t(.*)$/) {
		$oldErrorCounts{$2} = $1;
		$errorTotal += $1;
	    } elsif (/\S/ && $verbose) {
		print "Ignoring stored count line $_\n";
	    }
	}
	close($errors_in);
	$verbose && 
	    print "INFO: $errorTotal old error tallies for ".scalar (keys %oldErrorCounts)." different errors\n";
    } else {
	$verbose && 
	    print "WARNING: No error tallies found at $totalErrorCountsFile\n";
    }
    return %oldErrorCounts;
}

# Print tab-delimited dump of errors sorted in descending order of count
sub printTallySummary($$\%){
    my $out_stream = shift;
    my $title = shift;
    my $rh_errorCounts = shift;

    if ((defined($title)) && ($title ne '')) {
	print $out_stream "\n" . $title . "\n";
	print $out_stream ('=' x length($title)) . "\n";
    }

    foreach my $error (sort {${$rh_errorCounts}{$a} <=> ${$rh_errorCounts}{$b}} (keys(%{$rh_errorCounts}))) {
	print $out_stream ${$rh_errorCounts}{$error} . "\t" . $error . "\n";
    }
    print "\n";
    return;
}

sub errorTotalsMerge(\%\%) {
    my $rh_oldErrorCounts = shift;
    my $rh_newErrorCounts = shift;
    foreach my $newError (keys %{$rh_newErrorCounts}) {
	if (defined(${$rh_oldErrorCounts}{$newError})) {
	    ${$rh_oldErrorCounts}{$newError} += ${$rh_newErrorCounts}{$newError};
	} else {
	    ${$rh_oldErrorCounts}{$newError} = ${$rh_newErrorCounts}{$newError};
	}
    }
    return;
}

# Read in old totals
sub errorTotalsWrite(\%){
    my $rh_oldErrorCounts = shift;

    open( my $errors_out, ">$totalErrorCountsFile" )
	|| die "cannot open file $totalErrorCountsFile: $!";
    
    printTallySummary($errors_out, '', %{$rh_oldErrorCounts});
    close($errors_out);
    $verbose && 
	print "INFO: Saved updated tallies to $totalErrorCountsFile\n";
    return;
}


# Reword errors
sub rewordErrors(\@){
    my $errors = shift;
    my %newErrors;
    foreach my $error(@$errors){
	$verbose && 
	    print "ERROR: $error->{'ERROR'}\n";
	if($error->{'ERROR'} =~ /Invalid feature for an mRNA Bioseq/){
	    if($error->{'DETAILS'} =~ /^intron/){
		$error->{'ERROR'} = "ERROR: Intron feature on an mRNA";
	    }
	}
	elsif($error->{'ERROR'} =~ /mRNA feature is invalid on an mRNA/){
	    $error->{'ERROR'} = "ERROR: mRNA feature on an mRNA";
	}
	elsif($error->{'ERROR'} =~ /SEQ_DESCR.UnbalancedParentheses/){
	    $error->{'ERROR'} = "ERROR: Unbalanced parentheses in qualifier";
	}
	elsif($error->{'ERROR'} =~ /No Mol-info applies to this Bioseq/){
	    $error->{'ERROR'} = "ERROR: No mol_type";
	}
	elsif($error->{'ERROR'} =~ /Multi-interval CDS feature is invalid on an mRNA/){
	    $error->{'ERROR'} = "ERROR: Joined CDS feature on an mRNA";
	}
	elsif($error->{'ERROR'} =~ /tRNA codon does not match genetic code/){
	    $error->{'ERROR'} = "ERROR: tRNA codon does not match genetic code";
	}
	elsif($error->{'ERROR'} =~ /\[SEQ_FEAT.TrnaCodonWrong\]/){
	    $error->{'ERROR'} = "ERROR: tRNA codon does not match genetic code";
	}
	elsif($error->{'ERROR'} =~ /Illegal start codon used. Wrong genetic code \[(\d+)\] or protein should be partial/){
	    $error->{'ERROR'} = "ERROR: Illegal start codon - check genetic code, or 3' partial";
	}
	elsif($error->{'ERROR'} =~ /Genetic code conflict between CDS \(code (\d+)\) and BioSource/){
	    $error->{'ERROR'} = "ERROR: Genetic code mismatch";
	}
	elsif($error->{'ERROR'} =~ /Genetic code conflict between CDS \(code (\d+)\) and BioSource/){
	    $error->{'ERROR'} = "ERROR: Genetic code mismatch";
	}
	elsif($error->{'ERROR'} =~ /\[SEQ_FEAT\.TransLen\]\s+(.*)/){
	    $error->{'DETAILS'} = $1.", ".$error->{'DETAILS'};
	    $error->{'ERROR'} = "ERROR: Translation length does not match expected length";
	}
	elsif($error->{'ERROR'} =~ /\[CDREGION\.ProteinLenDiff\]/){
	    $error->{'ERROR'} = "ERROR: Translation length does not match expected length";
	}
	elsif($error->{'ERROR'} =~ /\[SEQ_FEAT\.AbuttingIntervals\]\s+(.*)/){
	    $error->{'DETAILS'} = $1.", ".$error->{'DETAILS'};
	    $error->{'ERROR'} = "ERROR: Abutting/overlapping segments in a location";
	}
	elsif($error->{'ERROR'} =~ /\[SEQ_INST.InternalNsAdjacentToGap\]\s+Ambiguous residue N is adjacent to a gap around position (\d+)/){
	    $error->{'DETAILS'} = "Position $1, ".$error->{'DETAILS'};
	    $error->{'ERROR'} = "ERROR: N(s) beside gap feature";
	}
	elsif($error->{'ERROR'} =~ /Use the proper genetic code, if available, or set transl_excepts on specific codons/){
	    $error->{'ERROR'} = "ERROR: Dubious use of /codon, check genetic code or add /transl_exception(s)";
	}
	elsif($error->{'ERROR'} =~ /((Start)|(Stop)|(Start and stop)) of ((transit)|(mat)|(sig))_peptide is out of frame with CDS codons/){
	    $error->{'ERROR'} = "ERROR: $1 of $5_peptide out of frame with CDS (^c pep in emacs can be used to check these)";
	}
	elsif($error->{'ERROR'} =~ /\[LOCATION.PeptideFeatOutOfFrame\]/){
	    $error->{'ERROR'} = "ERROR: peptide out of frame with CDS (^c pep in emacs can be used to check these)";
	}
	elsif($error->{'ERROR'} =~ /\[SEQ_INST.TerminalNs\]\s+N at ((beginning)|(end)) of sequence/){
	    $error->{'ERROR'} = "ERROR: Terminal N(s) at $1 of the sequence (^c nnn in emacs could have fixed this)";
	}
	elsif($error->{'ERROR'} =~ /Signal, Transit, or Mature peptide features overlap/){
	    $error->{'ERROR'} = "WARNING: overlapping peptide features";
	}
	elsif($error->{'ERROR'} =~ /A pseudo coding region should not have a product/){
	    $error->{'ERROR'} = "ERROR: pseudo CDS has a /product";
	}
	elsif($error->{'ERROR'} =~ /Run of (\d)+ Ns in delta component (\d+) that starts at base (\d+)/){
	    $error->{'ERROR'} = "WARNING: N's in sequence";
	}
	elsif($error->{'ERROR'} =~ /Colliding locus_tags in gene features/){
	    $error->{'ERROR'} = "ERROR: locus_tag dispute";
	}
	elsif($error->{'ERROR'} =~ /Strain should not be present in an environmental sample/){
	    $error->{'ERROR'} = "ERROR: environmental sample with /strain/";
	}
	elsif($error->{'ERROR'} =~ /mRNA contains CDS but internal intron-exon boundaries do not match/){
	    $error->{'ERROR'} = "ERROR: CDS contains bases not in the mRNA: intron-exon problem";
	}
	elsif($error->{'ERROR'} =~ /mRNA overlaps or contains CDS but does not completely contain intervals/){
	    $error->{'ERROR'} = "ERROR: CDS contains bases not in the mRNA: at the end(s)";
	}
	elsif($error->{'ERROR'} =~ /\[CDREGION\.TerminalStopCodonMissing\]/){
	    $error->{'ERROR'} = "ERROR: STOP codons missing";
	}
	elsif($error->{'ERROR'} =~ /Coding region extends \d+ base\(s\) past stop codon/){
	    $error->{'ERROR'} = "ERROR: STOP codons in-frame";
	}
	elsif($error->{'ERROR'} =~ /(\d+) internal stops\. Genetic code \[(\d+)\]/){
	    $error->{'ERROR'} = "ERROR: STOP codons in-frame";
	}
	elsif($error->{'ERROR'} =~ /\[CDREGION\.InternalStopCodonFound\]/){
	    $error->{'ERROR'} = "ERROR: STOP codons in-frame";
	}
	elsif($error->{'ERROR'} =~ /Location: Mixed strands in SeqLoc /){
	    $error->{'ERROR'} = "ERROR: trans_splicing (probably) missing from feature (mixed-strands)";
	}
	elsif($error->{'ERROR'} =~ /Location: Intervals out of order in SeqLoc/){
	    $error->{'ERROR'} = "ERROR: trans_splicing (probably) missing from feature (segments out-of-order))";
	}
	else{
	    if (!(defined($newErrors{$error->{'ERROR'}}))){
		$verbose && 
		    print " new error $error->{'ERROR'}\n";

		$newErrors{$error->{'ERROR'}} = $error->{'DETAILS'};
	    }
	}
	$verbose && 
	    print "reworded as $error->{'ERROR'}\n";

    }
    return %newErrors;
}

# show new errors
sub showNewErrors(\%$$){
    my $newErrors  = shift;
    my $outFile    = shift;
    my $inFile     = shift;
    my $errorCount = scalar (keys %$newErrors);
    if($errorCount == 0){
	return;}
    print $errorCount." new types of error\n";
    open (OUT, ">$outFile" ) 
	|| die ("Cannot open cannot $outFile\n");
    foreach my $newError (keys %$newErrors){
	print OUT $newError."\n"
	    .$$newErrors{'$newError'}."\n";
    }
    close (OUT);
    if (defined($maintainerEmailAddress)) {
	system("mailx -s \"$errorCount new error types from $inFile\" $maintainerEmailAddress < $outFile");
    }
}



####################################
# Main meat of script - should be moved to a sub
#open( STDERR, "> /dev/null" );

my @errors; 
my %attr   = ( PrintError => 0,
	       RaiseError => 0,
               AutoCommit => 0 );
print "database = $database\n";
defined($database) || die $usage;
my $dbh = DBI->connect( 'dbi:Oracle:'.uc($database), '/', '', \%attr )
    || die "Can't connect to database: $DBI::errstr";

#####################
#  1) Get errors from file
#
$time1 = (times)[0];
print "Get errors from file\n";
getErrorsFromFile($dbh, $inFile,@errors);
print scalar(@errors). " errors reported in $inFile\n";
$verbose and
    printf "'Get errors from file' took %.2f CPU seconds\n\n", (times)[0] - $time1;


#####################
#  2) Get ds and curator info for each
#
$time1 = (times)[0];
print "Get ds and curator info for each\n";
foreach my $error (@errors){
# add ds number info to errors, and gather additional ds info where ds != 0
    ($error->{'DS'}, $error->{'CURATOR'} , $error->{'CURATOR_STATUS'}) = SeqDBUtils2::get_ds_and_curator($error->{'AC'}, $dbh);

}
$dbh->disconnect;
$verbose and
    printf "'Get ds and curator info for each' took %.2f CPU seconds\n\n", (times)[0] - $time1;

#####################
#  3) Merge lost curators and simplify curator names
#
$time1 = (times)[0];
print "Merge lost curators and simplify curator names\n";
mergeCurators(@errors);
$verbose and
    printf "'Merge lost curators and simplify curator names' took %.2f CPU seconds\n\n", (times)[0] - $time1;



#####################
#  4) Reword errors
#
$time1 = (times)[0];
print "Reword errors\n";
my %newErrorTypes = rewordErrors(@errors);
$verbose and
    printf "'Reword errors\n", (times)[0] - $time1;

showNewErrors(%newErrorTypes, $inFile.".newErrorTypes", $inFile);


#####################
#  5) Add/report tally of errors
#
$time1 = (times)[0];
print "Adding current errors to tally\n"; 

my %newErrorCounts = tallyErrors(@errors);
my %oldErrorCounts = errorTotalsRead();

printTallySummary(*STDOUT, "Previous tallys for Genbank errors", %oldErrorCounts);
printTallySummary(*STDOUT, "New counts for Genbank errors", %newErrorCounts);
errorTotalsMerge(%oldErrorCounts,%newErrorCounts);
# only save updated tallys if we are running in mail mode (everything else is a test run)
if ($mail) {
    errorTotalsWrite(%oldErrorCounts);
}
$verbose and
    printf "'Tallying errors took %.2f CPU seconds\n\n", (times)[0] - $time1;


#####################
#  6) Sort by curator, ds, AC, error
#
$time1 = (times)[0];
print "Sort by curator, ds, AC, error\n";
sortErrors(@errors);
$verbose and
    printf "'Sort by curator, ds, AC, error' took %.2f CPU seconds\n\n", (times)[0] - $time1;

#####################
#  7) output to .out
#
if (!($quiet)){
    $time1 = (times)[0];
    print "output to $inFile.out\n";
    outputErrors(@errors, $inFile.".out");
    $verbose and
	printf "'output to $inFile.out' took %.2f CPU seconds\n\n", (times)[0] - $time1;
}

#####################
#  8) Mail output as individual threads to Jitterbug updates
#
if ($mail){
    $time1 = (times)[0];
    print "Mail output as individual threads to Jitterbug updates\n";
    mailErrors($database, $inFile, @errors);
    $verbose and
	printf "'Mail output as individual threads to Jitterbug updates' took %.2f CPU seconds\n\n", (times)[0] - $time1;
}

$quiet || print "DONE\n\n";
exit();
