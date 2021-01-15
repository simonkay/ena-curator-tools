#!/ebi/production/seqdb/embl/tools/bin/perl -w

##################################################################################
# toembl.pl - converts FastA, raw or gcg formatted sequence files to EMBL format #
#             length of individual lines in input file shouldn't matter,         #
#             neither does the length of the actual sequence.                    #
#             Also accepts EMBL flat files                                       #
# Author: PETER STERK                                                            #
# 08-JUN-1999: Version 1.0                                                       #
##################################################################################

print "\ntoembl.pl converts FastA, GCG or raw nucleotide file formats to EMBL format\n\n";

unless (defined $ARGV[0] ) {
    die ("No input file specified. Aborting.\n");
}

$infile = $inputfile = $ARGV[0];
#strip off extension
$infile =~ s/\..*//;
&seq2embl;

sub seq2embl {    
#Convert sequence file into EMBL format file 

    my $totalnt = 0;
    my @chars = ("a","c","g","t");
    my $remainder = "";

    open INSEQ,"$inputfile" or die "Can't open file\n";
    open TEMPFILE, ">${infile}.temp_" or die "Can't open temporary file\n";
    open EMBLSEQ,">${infile}.embl" or die "Can't open file\n";   

    #First determine sequence length and number of a, c, t, g and other nucleotides
    #Write sequence to temporary file 
    
    while (<INSEQ>) {
        if (/^ID /) { 
	    $|=1; # no buffering in order to print and make cursor wait at end of next question
	    print "This seems to be an EMBL flat file.\nDo you want the complete file Y/[N] or just the sequence? ";
	    $reply = <STDIN>;
	    $|=0;
	}
	if (defined $reply && $reply =~ /^y/i) {
	    if (/^ID / .. /^SQ/) {
		if (/^FT   /) {
		    s/__/../g;      #replace underscores with dots in case file is in GCG format
		}
		if (/^SQ  /) {
		    $_ = "";
		}
		print EMBLSEQ;
	    }

	}
    }
    if (defined $reply && $reply =~ /^y/i) {
	print "Keeping flat file.\n";
    } else {
	 print "Formatting sequence to EMBL format.\n";
    }
    close(INSEQ);
    open INSEQ,"$inputfile" or die "Can't open file\n";
    while (<INSEQ>) {
        if (/^ID / .. /^SQ/) {                   #if flat file, ignore everything above sequence
		$_ = "";
        }
	unless (/^>/ || /^\/\// || /\.\./ || /^SQ/ ) {  #ignore FastA header or // or GCG .. or EMBL SQ
            if (/[e|f|i|j|l|o|p|q|u|z|\.|\!]/i) {
		die "Sequence contains non-IUPAC nucleotide base codes. Aborting.\n\n";
	    }
	    chomp;
	    tr/A-Z/a-z/;                         #convert to lowercase, just in case
	    tr/u/t/;                             #convert u's to t's
            s/[\d\s]//g;                         #remove numbers and whitespace
	    $totalnt += length($_);
	    foreach $char (@chars) {
		eval ("\$count = tr/$char/$char/;");
		$count{$char} += $count;
	    }
            #write line of sequence, 6x10 chars
            $current_line = $remainder . $_;
            $linelength = length($current_line);
            $whole_lines = int $linelength/60;      #how many complete 60 nts lines in current line?
            $rest_of_line = $linelength%60;         #how many nts remain?
	    if ($rest_of_line == 0) {
		$remainder = "";
	    } else {            
		$remainder = substr($current_line,-$rest_of_line); #put remainder in string
	    }
            for ($i=1; $i <= $whole_lines; ++$i) {  #write out complete lines
		$seqline = substr($current_line,($i-1)*60,60);
                $seqline =~ s/^(.{10})(.{10})(.{10})(.{10})(.{10})(.{10})$/$1 $2 $3 $4 $5 $6/;
		print TEMPFILE "$seqline\n";
	    }
	}
    }
    if (length($remainder) > 0) {
	$rest = length($remainder);
	$ten_nt_blocks = int $rest/10;               #how many complete 10 nts blocks in remainder?
	$rest_nts = $rest%10;                        #how many nts remain?
	for ($i=1; $i <= $ten_nt_blocks; ++$i) {     #write out complete lines
	    $block = substr($remainder,($i-1)*10,10);
	    $lastline .= $block . " ";
	}
	$lastline .= substr($remainder,-$rest_nts) unless $rest_nts == 0;
	print TEMPFILE "$lastline\n";
    }
    close(INSEQ);
    close(TEMPFILE);
    open TEMPFILE, "${infile}.temp_" or die "Can't open temporary file\n";
    #Print header
    print EMBLSEQ "SQ   Sequence $totalnt BP; ";
    foreach $char (sort (@chars)) {
       print EMBLSEQ $count{$char}," ",uc$char,"; ";
       $totalactg += $count{$char};
    }
    print EMBLSEQ $totalnt - $totalactg," other;\n";

format EMBLSEQ =
     @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @>>>>>>>>
$seqline, $basecount
.

#Add sequence + base counts
#How many complete 60 nt lines?
    $no_of_60nt_lines = $totalnt/60;
    $linecounter = 1;
    while (<TEMPFILE>) {
	$seqline = $_;
        if ($linecounter <= $no_of_60nt_lines) {
	    $basecount = 60*$linecounter;
	} else {
	    $basecount = $totalnt;
	}
	write EMBLSEQ;
        ++$linecounter;
    }
    print EMBLSEQ "//\n";       #add //
    close(TEMPFILE);
    unlink("${infile}.temp_");
    close(EMBLSEQ);
    print "Done. Outputfile: ${infile}.embl\n";
}








