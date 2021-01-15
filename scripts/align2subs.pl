#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2006
#
#  SCRIPT DESCRIPTION:
#
#  A script to make BULK.SUBS from a fasta file and EMBL bulk template
#
#  MODIFICATION HISTORY:
#  CVS version control block - do not edit manually
#  $RCSfile: align2subs.pl,v $
#  $Revision: 1.24 $
#  $Date: 2008/10/10 10:36:18 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/align2subs.pl,v $
#  $Author: gemmah $
#
#===============================================================================

use strict;
use Date::Manip;
use File::Copy;
use SeqDBUtils2;
use generateSubs;
use Data::Dumper;

# Global variables (used in many subroutines)
my ( $verbose, $args );

my $fastaExt        = 'fasta';
my $skelExt         = 'skel';
my $templateExt     = 'ffl';
my $alignmentExt    = 'aln';
my $replaceTokenA   = '{';
my $replaceTokenB   = '}';
my $replaceTokenC   = "---";
my $saveFileName    = "BULK.SUBS";
my $notesFile       = "cons.notes";
my $sourceNotesFile = "source.notes";


my $usage =
  "\n PURPOSE: This script translates multiple sequence alignments (in fasta\n"
  . "format) into .sub files.\n"
  . "This file has 2 uses which can be carried out independently of each\n"
  . "other.\n"
  . "1. You can create a skel file from a ffl file which adds substitution\n"
  . "   tokens in the feature position ranges.\n"
  . "2. You can use a fasta formatted set of sequences from a multiple\n"
  . "   sequence alignment as input to create .sub files.  Many of these\n"
  . "   sequences will probably contain dashes so the positions of the\n"
  . "   features can be calculated.\n\n"
  . "NB If you want to change a clustalw MSA into fasta format, run the\n" 
  . "following command:\n"
  . "/sw/arch/bin/java -jar /ebi/production/extsrv/data/idata/appbin/READSEQ/readseq.jar -f=Fasta -o=<output_filename.fasta> <filename.aln>\n\n"
  . " USAGE:   align2subs [-f=<.$fastaExt file>]\n"
  . "          [-t=<.$skelExt file>]\n"
  . "          [-st=<.$templateExt file>] [-h] [-v]\n\n"
  . "    e.g.  [-f=hoad.$fastaExt] [-t=hoad.$skelExt] [-st=hoad.$templateExt]\n"
  . "    or    [-a=hoad.alignmentExt] [-st=hoad.$templateExt]\n"
  . "   -a=<file>       where <file> is a clustalw-formatted alignment file.\n"
  . "                   If a $fastaExt file is not supplied, \n"
  . "   -f=<file>       where <file> must be a fasta_formatted file with the\n"
  . "                   $fastaExt extension. This file must contain a list of\n"
  . "                   extension. This file must contain a list of\n"
  . "                   sequences in fasta format.  You will need a fasta\n"
  . "                   file in order to create .sub files\n\n"
  . "   -t=<file>       where <file> is a template file with the .$skelExt\n"
  . "                   extension.\n"
  . "                   This file must contain an EMBL entry template.\n"
  . "                   i.e. an EMBL file up to, but not including, the SQ\n"
  . "                   line.  ".$replaceTokenA."n".$replaceTokenB." marks where a feature position is to be\n"
  . "                   inserted  (where n is the variable number starting\n"
  . "                   from 1).  ".$replaceTokenC."n".$replaceTokenC." marks where other variable fields \n"
  . "                   are to be inserted (the values of which are held in\n"
  . "                   the fasta headers). As default, the prefix of the\n"
  . "                   .$fastaExt file will be used to find the appropriate\n"
  . "                   .$skelExt file.\n\n"
  . "   -st=<file>       where <file> is a .ffl file used to create the\n"
  . "                   .$skelExt file and to extract feature positions.  This\n"
  . "                   is a required file.\n\n"
  . "   -v              verbose\n\n"
  . "   -h              shows this help text\n\n";

################################################################################
# Create a new skeleton/template file from <submitter>.ffl, overwriting the
# existing input skel file.

sub make_new_skel_file($$) {

    my ( $fieldNumber, $line, $i, @skelLines, $numFields, $desc, $lastDesc );
    my ( $tmp, $skelLineNum, $enteredSourceFlag, $num_entries );

    my $skelFile = shift;
    my $fflTemplate = shift; # .ffl file from which to make the skel file 

    if ( $verbose ) {
        print "Making a new skeleton/template file ($skelFile) using $fflTemplate...\n";
    }

    $num_entries = `grep -c ^ID $fflTemplate`;

    if ($num_entries != 1) {
	die "\nError: There must be only a single entry provided inside the .ffl file with which to make the template.\n";
    }

    open( READFFL, "<$fflTemplate" ) || die "Cannot open the .ffl file $fflTemplate ".
	"in order to generate the .skel file: $!\n";

    #  translate numbers in features into substitution tokens e.g.
    # {1} where 1 is the field number
    $enteredSourceFlag = 0;
    $fieldNumber = 1;

    while ( $line = <READFFL> ) {

	if ( $line !~ /^((SH)|(SO)|(AL))\s+/ ) {

	    if ( $line =~ /^FT   [A-z-]+\s+\S+/ ) {

		if (! $enteredSourceFlag) {
		    push( @skelLines, "FT   source          1..$replaceTokenC"."SL"."$replaceTokenC\nFT                   /organism=\"?\"\nFT                   /mol_type=\"?\"\n" );
		    $enteredSourceFlag = 1;
		}

		while ( $line =~ /[^{]\d+[^}]/ ) {
		    $tmp = $replaceTokenA.$fieldNumber.$replaceTokenB;
		    $line =~ s/([^{])\d+([^}])/$1$tmp$2/;
		    $fieldNumber++;
		}
	    }
	    elsif ( $line =~ /^ID   ALIGNMENT  standard; \S+/) {
                #ID   <primary accession>\|XXX ; (SV <sequence version>)\|XXX; circular|linear; <molecule type>\|XXX; <dataclass>\|XXX; <taxonomic division>\|XXX; <sequence length> BP.
		$line = "ID   XXX; XXX; XXX; XXX; XXX; $replaceTokenC"."SL"."$replaceTokenC BP.\n";
	    }
	    elsif ( $line =~ /^AC   ALIGN;/) {
		$line = "AC   ;\n";
	    }
	    elsif ( $line =~ /^HD /) {
		$line = "ST * draft\n";
	    }
	    elsif ( $line =~ /^RP /) {
		$line = "RP   1-$replaceTokenC"."SL"."$replaceTokenC\n";
	    }
	    # make substitutions in template
	    $line =~ s/\r+/\n/g;   # remove any dos characters
	    $line =~ s/\n+/\n/g;    # remove any empty lines generated by prev command

	    push( @skelLines, $line );
	}
    }

    close( READFFL );

    #print @skelLines;

    open( WRITESKEL, ">$skelFile" ) || die "Cannot open a new skeleton file $skelFile: $!\n";
    for ($skelLineNum=0; $skelLineNum<@skelLines; $skelLineNum++) {

	if ( ($skelLines[$skelLineNum] =~ /^XX/) && (defined $skelLines[($skelLineNum+1)]) && ($skelLines[($skelLineNum+1)] =~ /^XX/) ) {
	    # don't print 
	}
	else {
	    print WRITESKEL $skelLines[$skelLineNum];
	}
    }
    close( WRITESKEL);

    #exit script so curator has opportunity to add variable field subs'n tokens
    die "$skelFile has been created.\n\n"
	. "Please Read: Now you will need to add substitution tokens into the $skelExt\n"
	. "file manually for any variable fields (exclusive of feature positions).\n"
	. "These variable fields should be found in the fasta headers of the "
	. $fastaExt."\nfile, in semicolon-separated format.  Please add $replaceTokenC"."1"."$replaceTokenC, "
	. $replaceTokenC."2"."$replaceTokenC etc\nfor each field that needs substituting in.\n\n"
	. "Secondly, if there are ID line fields which have the same values for\n"
        . "each entry, change the XXX place holders in the $skelExt file.\n\n"
	. "For reference, ID line field positions:\n"
	. "ID   <primary accession>; SV <sequence version>; <circular|linear>; <molecule type>; <dataclass>; <taxonomic division>; <sequence length> BP.\n\n"
        . "Thirdly, please do not remove any $replaceTokenC"."SL"."$replaceTokenC tokens.\n\n";
}

################################################################################
# see if skel file is up to date.  If not, regenerate it.

sub get_up_to_date_skel_file($$) {

    my ( $fflFileDate, $newestFlag, $skelDate, $makeNewSkelFlag);
    my ( $generateSkelFile, @filenameParts );

    my $skelFile = shift;
    my $fflFile = shift;   # .ffl file from which to make the skel file

    $makeNewSkelFlag = 0;


    if (( $fflFile ne "" ) && ( -e $fflFile ) && ( -e $skelFile )) {

	# date of .ffl file
	if ( -e $fflFile ) {
	    $fflFileDate = localtime +( stat($fflFile) )[9];
	}
	else {
	    print "The file to which the skel file is generated does not exist: $skelFile\n\n";
	}
	
	# take date/time of skel file and compare it to that of the ffl file
	$skelDate   = localtime +( stat($skelFile) )[9];
	$newestFlag = Date_Cmp( $fflFileDate, $skelDate );
	
	if    ( $newestFlag == -1 ) { $makeNewSkelFlag = 0; }
	elsif ( $newestFlag == 1 )  { $makeNewSkelFlag = 1; }
	elsif ( $newestFlag == 0 )  { $makeNewSkelFlag = 0; } # identical dates/times
	
	if ( $makeNewSkelFlag == 1 ) {
	    print "\nThe .ffl file is newer than the entered .skel file ".
		" Do you want to generate a new .skel file? (n/y) (or q to quit):\n";
	    chomp( $generateSkelFile = <STDIN> );
		
	    if ( $generateSkelFile eq 'q' ) {
		die "Quitting on request\n";
	    }
	    elsif ( $generateSkelFile ne 'y' ) {
		$makeNewSkelFlag = 0;

		# make a backup of the skel file before it is rewritten
		copy( $skelFile, $skelFile.".prev" ) || die "$skelFile cannot be copied.";

		if ( $verbose ) {
		    print "A backup of the original $skelExt file $skelFile "
			. "has been backed up to $skelFile.".".prev for "
			. "reference.\n";
		}
	    }
	}
	else {
	    if ( $verbose ) {
		print "\n$skelFile is up-to-date.\n\n";
	    }
	}
    }
    # if skel file doesn't exist signal to make a new one
    elsif (! ( -e $skelFile )) {
	$makeNewSkelFlag = 1;

	if ( $skelFile eq "" ) {
	    @filenameParts = split(/\./, $fflFile);
	    $skelFile = $filenameParts[0].".".$skelExt;
	}
    }
    
    #generate new skel file
    if ( $makeNewSkelFlag == 1 ) {
	make_new_skel_file( $skelFile, $fflFile );
    }

    return ( $skelFile );
}

################################################################################
# check if all the fasta characters are inidcative of problems

sub check_for_illegal_characters($$$$) {

    my $seq         = shift;
    my $fastaHeader = shift;
    my $errorMsg    = shift;
    my $READFASTA   = shift;

    $seq =~ s/\s+/ /g;

    if ( $seq =~ /([ACTGRYMKSWHBVDNactgrymkswhbvdn=. \n\r\t-]{0,5})([^ACTGRYMKSWHBVDNactgrymkswhbvdn=. \n\r\t-]+)([ACTGRYMKSWHBVDNactgrymkswhbvdn=. \n\r\t-]{0,5})/ ) {

        close($READFASTA);

	die "Unauthorised character(s) '$2' have been found within '$1$2$3' in"
	    . ":\n$fastaHeader\n$seq\n\n" . $errorMsg;
    }
}

################################################################################
# builds the embl entry i.e. adds fasta header fields to the skel template and
# combines with reformatted sequence -> new embl entry

sub build_embl_entry($$$$\@$$$$$) {

    my ( @substitutions, $tokenNum, $subs, $tmp, $message, $continue, $ftNum );
    my ( $errorLocation, $token );

    my $template            = shift;
    my $fastaHeader         = shift;
    my $formattedSeq        = shift;
    my $seqlen              = shift;
    my $newFtPositions      = shift;
    my $skelFile            = shift;
    my $SAVEEMBLTMP         = shift;
    my $checkForSpareTokens = shift;
    my $fastaSeqCounter     = shift;
    my $errorMsg            = shift;

    $continue = 0;
    $errorLocation = "Error found in fasta sequence number $fastaSeqCounter. ";

    # substitute sequence length into the ID line
    if ( $template =~ /(\-\-\-SL\-\-\-)/ ) {
	$template =~ s/$1/$seqlen/g;
    }
    else {
	print "Warning: because the $replaceTokenC"."SL"."$replaceTokenC token has been removed from the ID "
	    . "line, sequence length cannot be substituted into each entry.\nTo "
	    . "correct this error the $replaceTokenC"."SL"."$replaceTokenC token must be reinserted into the "
	    . "$skelExt before running this script again.\n\n";
    }

    # make non-feature position substitutions, e.g. ---1---
    ( @substitutions ) = split( /;/, $fastaHeader );

    $tokenNum = 1;

    foreach $subs ( @substitutions ) {

        $tmp = $replaceTokenC.$tokenNum.$replaceTokenC;

        if ( $template =~ /$tmp/ ) {
            $template =~ s/$tmp/$subs/g;
            $tokenNum++;
        }
        else {

	    if ( $template =~ /[^-](\-\-?(\d+)\-\-?)[^-]/ ) {
		$message = "Warning:\nThe invalid token '$1' has been located in "
		    . " the $skelExt file $skelFile.  Tokens for substituting "
		    . "non-feature position data into the skel file must contain "
		    . "3 dashes either side of a number (e.g. $replaceTokenC".$2."$replaceTokenC).  Please "
		    . "amend $skelFile and try running the script again.\n\n";
	    }
	    else {
		scalar( @substitutions );
		$message = "Warning:\nThere are not enough tokens in $skelFile for "
		    . "the number of fields in the fasta header\n>$fastaHeader\n\n"
		    . $errorLocation.$errorMsg."\nTokens $replaceTokenC"."1"."$replaceTokenC to $replaceTokenC"
		    . scalar(@substitutions)."$replaceTokenC are required in $skelFile.  $tmp "
		    . "cannot be located within this file.\n\n";
	    }

            close( $SAVEEMBLTMP );
            die $message;
        }
    }

    # make feature position substitutions, e.g. {1}
    for ( $ftNum=0; $ftNum<@$newFtPositions; $ftNum++ ) {

        $tmp = quotemeta( $replaceTokenA.($ftNum+1).$replaceTokenB );

        if ( $template =~ /$tmp/ ) {
            $template =~ s/$tmp/$$newFtPositions[$ftNum]/g;
        }
        else {
            close( $SAVEEMBLTMP );
	    $tmp =~ s/\\//g;

            die "Warning:\nThere are not enough feature position tokens "
		. "for the number of feature positions to substitute in. $tmp "
		. "is missing.  Tokens {1} to {".scalar(@$newFtPositions)."} "
		. "should have been automatically inserted into this script.  "
		. "Please remove $skelFile and rerun this script in order to "
		. "generate the correct feature position tokens.\n\n";
        }
    }

    # make any left over tokens blank but warn and give option to exit script
    if ( $checkForSpareTokens ) {
        if ( ( $template =~ /($replaceTokenC\d+$replaceTokenC)/ ) || ( $template =~ /($replaceTokenA\d+$replaceTokenB)/ ) ) {

	    $token = $1;

            $template =~ s/$replaceTokenC\d+$replaceTokenC//g;
            $template =~ s/$replaceTokenA\d+$replaceTokenB//g;

            $message = "Warning: There are some spare tokens in your skel file "
		. "('$token') which have not been replaced because there are more "
		. "tokens than data fields in the fasta header:\n>$fastaHeader"
		. "\n\n$errorLocation\n";

            print $message."Remove spare tokens and continue processing data "
		. "(y/n) (or q to quit)?\n";

            chomp( $continue = <STDIN> );
            if ( ( $continue eq 'q' ) || ( $continue eq 'n' ) ) {
                print $SAVEEMBLTMP $message;
                close($SAVEEMBLTMP);
                die "Quitting on request\n";
            }
            else {
                $checkForSpareTokens = 0;
            }
        }
    }

    $template .= $formattedSeq;

    return ( $template, $checkForSpareTokens );
}

################################################################################
# Change format of fasta sequence to embl format

sub compile_embl_entries($\@$) {

    my ( $seq, $newSeqFormat, $currentEmblEntry, $template, $entry, $errorMsg );
    my ( $SAVEEMBLTMP, $checkForSpareTokens, $seqlen, $fastaSeqCounter );
    my ( $fastaErrorLocn, $loopCounter );

    my $skelFile  = shift;
    my $fastaSeqInfo = shift;
    my $emblTmpFile = shift;

    $errorMsg = "Take a look in $emblTmpFile for the output up to this point.\n\n";

    open( $SAVEEMBLTMP, ">$emblTmpFile" ) || die "Cannot open temporary file $emblTmpFile: $!\n";

    # open skel file
    open( TEMPLATE, "<$skelFile" ) || die "Cannot read skeleton file $skelFile: $!\n";
    $template = do{local $/; <TEMPLATE>}; # read file into string
    close( TEMPLATE );

    # remove dos characters
    $template =~ s/\r+/\n/g;

    # quick check to see if template contains the correct contents...
    if ( $template !~ /^ID   / ) {
	die "The template file $skelFile does not begin with \"ID   \"\n"; 
    }

    increment_decrement_char_check( $template, $skelFile );

    $checkForSpareTokens = 1;  # indicates whether spare tokens should be checked for in skel
    $fastaSeqCounter = 1;
    $loopCounter = 0;

    foreach $entry ( @$fastaSeqInfo ) {

	# change sequence in embl format
	( $newSeqFormat, $seqlen ) = reformat_sequence( $entry->{seq} );
	
	$fastaErrorLocn = "Error found in fasta sequence number $fastaSeqCounter. ";
	
	# make substitutions in skel file template and combine with reformatted sequence
	( $currentEmblEntry, $checkForSpareTokens ) =
	    build_embl_entry( $template, $entry->{header}, $newSeqFormat, $seqlen, @{$entry->{fts}}, $skelFile, $SAVEEMBLTMP, $checkForSpareTokens, $fastaSeqCounter, $errorMsg );
	
	print $SAVEEMBLTMP $currentEmblEntry;
	$fastaSeqCounter++;

	$loopCounter++;
    }
    close( $SAVEEMBLTMP );

    # if we've got this far without complaints, save the contents of <fastaprefix>.embltmp
    # to BULK.SUBS
    save_data( $emblTmpFile, ($fastaSeqCounter-1), "", "align2subs", $saveFileName, $verbose );

    delete_file( $emblTmpFile, $verbose );
}

################################################################################
# Put the fasta headers and sequences into an array so they're more managable

sub create_array_of_sub_info($) {

    my ( @fastaSeqInfo, $seq, $fastaHeader, $nextFastaHeader, %fastaHeaders );
    my ( $emblTmpFile,  $fastaPrefix, $fastaSuffix, $READFASTA, $line );
    my ( $fastaFileLineNum, $seqErrorMsg, $headerLineNum, $origFastaHeader );
    my ( $fastaSeqCounter, $errorSavedTo, $seqErrorLocn, $fastaSeqLineNum );

    my $fastaFile = shift;

    $seq = "";
    $fastaSeqCounter = 0;
    $fastaFileLineNum = 0;

    # open a temp file for temporarily storing the output (in case of error).
    ( $fastaPrefix, $fastaSuffix ) = split( /\./, $fastaFile );
    $emblTmpFile = $fastaPrefix . ".embltmp";


    # create array of fasta seqs
    open( $READFASTA, "<$fastaFile" ) || die "Cannot read $fastaFile\n";

    $headerLineNum = 1;
    while ( $line = <$READFASTA> ) {

        #clean line (remove dos characters);
        $line =~ s/\r+/\n/g;
        $line =~ s/\n+/\n/g;

        # process sequence
        if ( eof($READFASTA) ) {
	    if ($line !~ /^\/\//) {
		$seq .= $line;
	    }
        }

        if ( ( ( $line =~ /^>/ ) || ( eof($READFASTA) ) ) && ( $seq ne '' ) ) {

            $fastaSeqCounter++;
            $nextFastaHeader = $line;

	    $fastaSeqLineNum = $headerLineNum+1;
	    $seqErrorMsg    = "Error found in $fastaFile (sequence which "
		. "ends on line $fastaFileLineNum, fasta sequence number "
		. "$fastaSeqCounter).\n\n";


	    chomp($fastaHeader);
	    $origFastaHeader = $fastaHeader;

            check_for_illegal_characters( $seq, $origFastaHeader, $seqErrorMsg, $READFASTA );

	    $fastaHeader =~ s/^>//;
	    $fastaHeader =~ s/\s*;\s*/;/g;
	    $fastaHeader =~ s/(^\s*)|(;?\s*$)//g;

            # test for duplicates
	    check_for_duplicate_fastaheader( $fastaHeader, $origFastaHeader, %fastaHeaders, $fastaSeqCounter, $headerLineNum );

	    $seq =~ s/[ \n\r\t]+//g;

	    $fastaSeqInfo[($fastaSeqCounter-1)] = {
		header => $fastaHeader, 
		seq    => $seq
	    };
	    $headerLineNum = $fastaFileLineNum;
	
	    if ( $nextFastaHeader ) {
		$fastaHeader = $nextFastaHeader;
		$seq         = '';
	    }
	}
	# this one catches non-header lines
	elsif ( $line !~ /^>/ ) {
	    $seq .= $line;
	}
	#grab very first fasta line in file
	elsif ( ( $line =~ /^>/ ) && ( $seq eq '' ) ) {
	    $fastaHeader = $line;
	}

	$fastaFileLineNum++;
    }

    close( $READFASTA );

    return( \@fastaSeqInfo, $emblTmpFile );
}

################################################################################
# Get the submitted features listed in the ffl file

sub get_original_feature_positions($) {

    my ( $line, $ftNum, @origFeatures );

    my $templateFile = shift;

    open( READTEMPLATE, "<$templateFile" ) || die "Cannot open $templateFile for reading\n";

    $ftNum = 0;
    while ($line = <READTEMPLATE>) {

	if ( $line =~ /^FT   \S+[^0-9]*\d+.*/ ) {

	    while ( $line =~ s/(\d+)// ) {
		push( @{$origFeatures[$ftNum]}, $1 );
	    }
	    $ftNum++;
	}
    }

    close( READTEMPLATE );

    return( \@origFeatures );
}

################################################################################
# calculate the new feature positions along each sequence

sub calculate_new_feature_positions(\@\@) {

    my ( $entry, $featureSet, $seqBeforeFt, $cleanSeq, $cleanSeqLen, $seq );
    my ( $featureDetails, $newFtPos, $origFtPos, $numDashesBeforeFt );

    my $origFeatures = shift;
    my $fastaSeqInfo = shift;

    foreach $entry ( @$fastaSeqInfo ) {

	$seq = $entry->{seq};
	$cleanSeq = $seq;
	$cleanSeq =~ s/\-+//g;
	$cleanSeqLen = length($cleanSeq);

	foreach $featureSet ( @$origFeatures ) {

	    foreach $origFtPos ( @$featureSet ) {	    

		# Are there any '-' before the feature sequence?
		$seqBeforeFt = substr( $seq, 0, $origFtPos );
		$_ = $seqBeforeFt;
		$numDashesBeforeFt = tr/\-//;
		$newFtPos = $origFtPos - $numDashesBeforeFt;

		if ( $newFtPos < 1 ) {
		    $newFtPos = "<1";
		}
		elsif ( $newFtPos > $cleanSeqLen ) {
		    $newFtPos = ">$cleanSeqLen";
		}

                push( @{$entry->{fts}}, $newFtPos );
	    }
	}

	# remove any dashes from the sequence now 
        # new ft positions have been calc'd
	$entry->{seq} = $cleanSeq;
    }
    #print Dumper($fastaSeqInfo);
    #exit;
}

################################################################################
# Add in extended fasta headers from cons.notes.

sub substitute_fasta_headers($) {

    my ($fastaContent, $sourceContent, @bigFastaHeaders, $fullHeader);
    my ($numFields, $prevNumFields, @fields, $headerNum);

    my $fastaFile = shift;

    if (!-e $notesFile) {
	if (-e $sourceNotesFile) {
	    $notesFile = $sourceNotesFile;
	}
	else {
	    die "There is no notes files (cons.notes or $sourceNotesFile) available.  This file needs to be a '>'-separated list of fasta headers.\n";
	}
    }

    $verbose && print "\nUsing $notesFile to supply data to substitute into the skel file template.\n";

    open(READNOTES, "<$notesFile") || die "Cannot open $notesFile for reading.\n"; 
    $sourceContent = do{local $/; <READNOTES>};
    close(READNOTES);

    # fasta header file is of unrecognised format.
    if ($sourceContent !~ /^\s*>/) {
	die "\n$notesFile is of an unrecognised format.  This file needs to be a '>'-separated list of fasta headers.  Please edit this file and then try running this script again.\n\n";
    }

    # remove trailing '//' and remove any newline characters before
    # splitting into individual fasta headers
    $sourceContent =~ s/\/\/\s*$//;
    $sourceContent =~ s/[\n\r]+//g;

    @bigFastaHeaders = split(/>/, $sourceContent);

    open(READFASTA, "<$fastaFile") || die "Cannot open $fastaFile for reading.\n";
    $fastaContent = do{local $/; <READFASTA>};
    close(READFASTA);


    # substitute source.notes entire header into fasta file
    $headerNum = 1;
    foreach $fullHeader (@bigFastaHeaders) {
	if ($fullHeader ne "") {
	    $fullHeader =~ s/\s+$//;
	    @fields = split(';', $fullHeader);

            # check all supplied fasta headers contain the same number of fields
	    $numFields = scalar(@fields);

	    if (($headerNum > 1) && ($numFields != $prevNumFields)) {
		die "\nWarning: fastaHeader \"$fullHeader\" contains $numFields fields when compared with the previous fasta row field number of $prevNumFields (fastaheader number $headerNum).\n\n";
	    }

	    $fullHeader =~ s/^[^;]+;//;
	    $fullHeader =~ s/\s+;/;/;
	    $fullHeader =~ s/;\s+/;/;
	    $fields[0] =~ s/^\s+//;
	    $fields[0] =~ s/\s+$//;

	    if ($fastaContent =~ /$fields[0]\b.?[^\n]*/) {
		$fastaContent =~ s/$fields[0]\b.?[^\n]*/$fullHeader/;
	    }
	    else {
		die "\nError: The  Abbrev. column in the SO lines of the embl template file supplied must be present as the first column of values in the fasta headers in $notesFile.  \"$fields[0]\" key not found.\n";
	    }

	    $prevNumFields = $numFields;
	    $headerNum++;
	}
    }

    # make a backup of the fasta file before the fasta headers are replaced
    copy( $fastaFile, $fastaFile.".orig" ) || die "$fastaFile cannot be copied.";

    $verbose && print "A copy of $fastaFile has been made with the suffix .orig befor any changes have have been made to the fasta headers in this file.\n";

    open(SAVEFASTA, ">$fastaFile") || die "Cannot open $fastaFile for saving extra fields to fasta headers.\n";
    print SAVEFASTA $fastaContent;
    close(SAVEFASTA);
}

################################################################################
# webin-align has a nasty habit of removing the "CLUSTAL W (1.8) multiple 
# sequence alignment" header from alignment.aln - easier to change here

sub make_sure_alignment_file_contains_clustalw_header($) {

    my ($tmpFilename,  $first_line, $tmpFilename2, $i, $bakFilename);
    my ($sec, $min, $hour, $mday, $mon, $year, @other, $timestamp);

    my $alignmentFile = shift;

    $first_line =  `head -1 $alignmentFile`;

    # if file doesn't start with a clustal w header, add one
    if ($first_line =~ /[agct]{10}/i) {

	# make backup of alignment file (do not overwrite another file)
	for ($i=1; $i<100; $i++) {
	    $bakFilename = $alignmentFile.".orig.".$i;
	    
	    if (! -e $bakFilename) {
		copy($alignmentFile, $bakFilename);
		last;
	    }
	}
	
	# create timestamp for unique temporary filenames
	($sec,$min,$hour,$mday,$mon,$year,@other) = localtime(time);
	$timestamp = $year.$mon.$mday.$hour.$min.$sec;
	
	$tmpFilename  = $alignmentFile.$timestamp."A";
	$tmpFilename2 = $alignmentFile.$timestamp."B";
	
	open(WRITE_CLUST_HDR, ">$tmpFilename") || die "Cannot open alignment file to  contain clustal w headers.\n";
	print WRITE_CLUST_HDR "CLUSTAL W (1.8) multiple sequence alignment\n\n\n";
	close(WRITE_CLUST_HDR);
	
	print `cat $tmpFilename $alignmentFile > $tmpFilename2`;
	
	rename($tmpFilename2, $alignmentFile);
	unlink($tmpFilename);
    }
}

################################################################################
# Make a fasta file from the alignment file (plus cons.note for variable field
# values).

sub make_fasta_file($) {

    my ($readseq, $line, $fastaFile, $submitter, $fileSuffix);

    my $alignmentFile = shift;

    ($submitter, $fileSuffix) = split(/\./, $alignmentFile);
    $fastaFile = "$submitter\.fasta";

    make_sure_alignment_file_contains_clustalw_header($alignmentFile);

    $readseq = "/ebi/production/extsrv/data/idata/appbin/READSEQ/readseq.jar";
    if ($verbose) {
	print "\nRunning Readseq: /sw/arch/bin/java -jar $readseq -f=Fasta -o=$fastaFile $alignmentFile\n";
    }
    
    system "/sw/arch/bin/java -jar $readseq -f=Fasta -o=$fastaFile $alignmentFile";

    substitute_fasta_headers($fastaFile);

    return($fastaFile);

}

################################################################################
# Ask for either an msa alignment file or a fasta file as the sequence provider

sub ask_for_fasta_or_aln_file($$) {

    my ( $fileName );

    my $fileList = shift;
    my $availableFiles = shift;
    
    print "Please enter a .$fastaExt or .$alignmentExt file $fileList:\n";
    $fileName = <STDIN>;
    $fileName =~ s/\s+//g;

    if ($fileName eq "") {

	if ( @$availableFiles > 1 ) {
	    print"Please enter a file name:\n";
	    return( "" );
        } else {
	    return( $$availableFiles[0] );
	}
    }
    else {
	return( $fileName );
    }
}
################################################################################
# Look in the directory for suitable skel and ffl files if not entered as
# arguments

sub ensure_required_files_are_available($$$$) {

    my ( $prefix, $suffix, $fileList, $fileList2, $useFile, $availableFiles );
    my ( @availableFiles, $skelTemplate, $fileName, $ext, $fastaFileList );
    my ( $sourceContent, $addFastaHeaders, $fastaContent, $skelFileAutoChosen );
    my ( $message );

    my $fastaFile = shift;
    my $skelFile = shift;
    my $templateFile = shift;
    my $alignmentFile = shift;

    $skelFileAutoChosen = 0;

    if ($fastaFile ne "") {
	( $prefix, $suffix ) = split( /\./, $fastaFile );
    }
    elsif ($skelFile ne "") {
	( $prefix, $suffix ) = split( /\./, $skelFile );
    }
    elsif ($templateFile ne "") {
	( $prefix, $suffix ) = split( /\./, $templateFile );
    }
    elsif ($alignmentFile ne "") {
	( $prefix, $suffix ) = split( /\./, $alignmentFile );
    }
    else {
	$prefix = "";
    }

    # make sure we have the required .ffl file
    if ($templateFile eq "") {

	$fileList = get_directory_listing($templateExt);

	if ( $fileList eq "" ) {
	    
	    die "A file with the $templateExt extension is required for ".
		"this script to run.\nQuitting script.\n";
	}
	elsif ( $fileList !~ /,/ ) {
	    $fileList =~ s/\[|\]//g;
	    $templateFile = $fileList;

	    if ( $verbose ) {
		print "Using $fileList as the template file, because it was the\n"
		    . "only $templateExt file found.\n";
	    }
	}
	elsif (( $prefix eq "" ) || ($fileList !~ /($prefix\.$templateExt)/ )) {
	    while ($templateFile eq "") {
		$templateFile = ask_for_input_file( $templateExt );
		$templateFile = check_input_file( $templateFile, $templateExt, $fastaExt, $verbose );
	    }
	}
	elsif ( $fileList =~ /($prefix\.$templateExt)/ ) {

	    if ( $verbose ) {
		print "Using $prefix"."."."$templateExt to provide the $skelExt "
		    . "template and feature locations.\n";
	    }

	    $templateFile = $1;
	}
    }

    # see if there are any .skel files around
    if ( $prefix eq "" ) {
	( $prefix, $suffix ) = split( /\./, $templateFile );
    }

    if ( $skelFile eq "" ) {
	$fileList = get_directory_listing( $skelExt );

	if ($fileList eq "") {
	    $skelFile = "$prefix\.$skelExt";
	}
	elsif (($fileList ne "") && ($fileList !~ /,/)) {
	    $fileList =~ s/\[|\]//g;
	    $skelFile = $fileList;
	    $skelFileAutoChosen = 1;

	    if ( $verbose ) {
		print "Using $fileList as the $skelExt file, because it was the\n"
		    . "only $skelExt file found.\n";
	    }
	}
	elsif ( $fileList =~ /($prefix\.$skelExt)/ ) {

	    if ( $verbose ) {
		print "Using $prefix"."."."$skelExt to provide the $skelExt "
		    . "template and feature locations.\n";
	    }
	    $skelFileAutoChosen = 1;
	    $skelFile = $1;
	}
	else {
	    while ( $skelExt eq "" ) {
		$skelFile = ask_for_input_file( $skelExt );
		$skelFile = check_input_file( $skelFile, $skelExt, $fastaExt, $verbose );
	    }
	}
    }


    # if skel file exists as input, this possibly means we don't need to 
    # rebuild the skel file and therefore need the fasta/msa file in order
    # to build embl entries.
    if (-e $skelFile) {

	# check skel file for ---n--- tokens and bail if there are none.
	open(READSKEL, "<$skelFile") || die "Cannot read $skelFile: $!\n";
	$skelTemplate = do{local $/; <READSKEL>}; # read file into string
	close(READSKEL);

	if ( $skelTemplate !~ /\-\-\-\d+\-\-\-/ ) {
	    $message = "Error:\nThe ";

	    if ($skelFileAutoChosen) {
		$message .= "selected"
	    }
	    else {
		$message .= "entered"
	    }

	    $message .= " $skelExt file ($skelFile) contains no $replaceTokenC"."n"."$replaceTokenC style tokens.  You must add\n"
		. "at least one of these tokens ($replaceTokenC"."1"."$replaceTokenC) into $skelFile"
		. " so variable\nfield contents can be substituted into the embl entries.\n\n";

	    die $message;
	}


	if (( !$fastaFile ) && ( !$alignmentFile )) {

	    $fileList = get_directory_listing($fastaExt);
	    $fileList2 = get_directory_listing($alignmentExt);

	    # if there is a single fasta file, assume that is the one to use.
	    if (( $fileList ne "" ) && ( $fileList !~ /,/ )) {
		$fileList =~ s/\[|\]//g;
		$fastaFile = $fileList;

		if ( $verbose ) {
		    print "Using $fileList as the file which provides the variable\n"
			. "data, because it is the only $fastaExt file found.\n";
		}
	    }
	    elsif (($fileList ne "") && ($fileList2 ne "")) {
		$fileList = $fileList. $fileList2;
		$fileList =~ s/\]\[/, /;
	    } 
	    elsif (($fileList eq "") && ($fileList2 ne "")) {
		$fileList = $fileList2;
	    }


	    if ( $fileList eq "" ) {
		die "Error: There are no $fastaExt or $alignmentExt files available.\n"
		    . "One of these file types must be entered before this script can "
		    . "run\nproperly.\n";
	    }
	    if ($fastaFile eq "") { 
	    
		$availableFiles = $fileList;
		$availableFiles =~ s/\[//;
		$availableFiles =~ s/\]//;
		$availableFiles =~ s/\s+//;
		@availableFiles = split(/,/,$availableFiles);
	    

		if ( $fileList =~ /,/ ) {
		    $fileName = "";

		    while ( $fileName eq "" ) {
			$fileName = ask_for_fasta_or_aln_file( $fileList, @availableFiles );
			
			if ( $fileName =~ /$fastaExt$/ ) {
			    $ext = $fastaExt;
			}
			else {
			    $ext = $alignmentExt;
			}
			
			$fileName = check_input_file( $fileName, $ext, $fastaExt, $verbose );
		    }
		    
		    if ( $fileName =~ /$fastaExt$/ ) {
			$fastaFile = $fileName;
		    }
		    else {
			$alignmentFile = $fileName;
		    }
		} 
		elsif ( $fileList ne "" ) {
		    $fileList =~ s/\[|\]//g;
		    
		    if ( $fileList =~ /$fastaExt$/ ) {
			$fastaFile = $fileList;
		    }
		    else {
			$alignmentFile = $fileList;
		}
		    
		    if ( $verbose ) {
			print "Using $fileList, because it was the only file found "
			    . "with an\n$alignmentExt or $fastaExt extension.\n";
		    }
		}
	    }

	}
	elsif (($alignmentFile ne "") && ($fastaFile ne "")) {
	    print "You have entered both a .aln file and a .fasta file.  Would "
		. "you like to use the .fasta or the .aln file (f/a)?\n";
	    chomp( $useFile = <STDIN> );

	    if ( $useFile =~ /^a/ ) {
		$fastaFile = "";
	    }
	    elsif ($useFile =~ /^f/) {
		$alignmentFile = "";
	    }
	    elsif ($useFile =~ /^q/) {
		die "Quitting on request\n";
	    }
	}	    
    }

    if ( $alignmentFile ne "" ) {
	$fastaFile = make_fasta_file( $alignmentFile );
    }
    # or extend the fasta header if the fasta file exists (in the
    # right circumstances)
    elsif ( -e $fastaFile ) {

	if (!-e $notesFile) {
	    $notesFile = $sourceNotesFile;
	}

	if (open(READNOTES, "<$notesFile")) {
	    $sourceContent = do{local $/; <READNOTES>};
	    close(READNOTES);

	    # notes file contains fasta header lines
	    if ($sourceContent =~ /^\s*>/) {

		open(READFASTA, "<$fastaFile") || die "Cannot open $fastaFile for reading.\n";
		$fastaContent = do{local $/; <READFASTA>};
		close(READFASTA);

		# if fasta header looks like it already many fields
		# in it, don't ask to substitute in any headers
		if ( $fastaContent !~ /^\s*>[^;]+;([^;]+;)+/ ) {
		    print "Do you want to add the fasta headers from $notesFile into the fasta file ($fastaFile) (y/n)?\n";
		    chomp( $addFastaHeaders = <STDIN> );

		    if ($addFastaHeaders =~ /^[Yy]/) { 
			if ($verbose) {
			    print "The fasta headers are being added.\n";
			}
			substitute_fasta_headers($fastaFile);
		    }
		    else {
			if ($verbose) {
			    print "The fasta headers will not be changed.\n";
			} 
		    }
		}
	    }
	}
	else {
	    print "There is no notes files ($notesFile or $sourceNotesFile) available so it is assumed that the fasta headers in the fasta file already contain the variable fields\n";
	}
    }

    return( $fastaFile, $skelFile, $templateFile );
}

################################################################################
# make sure all the right arguments have been received

sub get_args(\@) {

    my ( $fastaFile, $skelFile, $arg, $templateFile, $fileList );
    my ( $prefix, $suffix, $alignmentFile  );

    my $args = shift;

    print "\n";

    $fastaFile    = "";
    $skelFile     = "";
    $templateFile = "";
    $alignmentFile = "";

    # check the arguments for values
    foreach $arg ( @$args ) {

        if ( $arg =~ /^\-v/ ) {    # verbose mode
            $verbose = 1;
        }
        elsif ( $arg =~ /^\-f=(.+)$/ ) {    # fasta file
            $fastaFile = check_input_file( $1, $fastaExt, $fastaExt, $verbose );
	    while ($fastaFile eq "") {
		$fastaFile = ask_for_input_file($fastaExt);
		$fastaFile = check_input_file( $fastaFile, $fastaExt, $fastaExt, $verbose );
	    }
        }
        elsif ( $arg =~ /^\-t=(.+)$/ ) {    # skel file
            $skelFile = check_input_file( $1, $skelExt, $fastaExt, $verbose );
	    while ($skelFile eq "") {
		$skelFile = ask_for_input_file( $skelExt );
		$skelFile = check_input_file( $templateFile, $skelExt, $fastaExt, $verbose );
	    }
        }
        elsif ( $arg =~ /^\-st=(.+)$/ ) {    # skel template file
            $templateFile = check_input_file( $1, $templateExt, $fastaExt, $verbose );
	    while ($templateFile eq "") {
		$templateFile = ask_for_input_file( $templateExt );
		$templateFile = check_input_file( $templateFile, $templateExt, $fastaExt, $verbose );
	    }
        }
        elsif ( $arg =~ /^\-a=(.+)$/ ) {    # clustalw file
            $alignmentFile = check_input_file( $1, $alignmentExt, $fastaExt, $verbose );
	    while ($alignmentFile eq "") {
		$alignmentFile = ask_for_input_file( $alignmentExt );
		$alignmentFile = check_input_file( $alignmentFile, $alignmentExt, $fastaExt, $verbose );
	    }
	    $alignmentFile =~ s/(^\s*.+\s*$)/$1/;
        }
        elsif ( $arg =~ /^-h/ ) {
            die $usage;
        }
        else {
            die "Unrecognised argument format \"$arg\"\n" .
		$usage;
        }
    }

    ( $fastaFile, $skelFile, $templateFile ) = ensure_required_files_are_available( $fastaFile, $skelFile, $templateFile, $alignmentFile);


    return ( $fastaFile, $skelFile, $templateFile );
}

################################################################################
# main function

sub main(\@) {

    my ( $fastaFile, $templateFile, $origFeatures, $fastaSeqInfo );
    my ( $emblTmpFile, $skelFile );

    my $args = shift;

    # check arguments are intact
    ( $fastaFile, $skelFile, $templateFile ) = get_args( @$args );

    # check skel file is up to date
    $skelFile = get_up_to_date_skel_file( $skelFile, $templateFile );

    # fetch the features into 
    $origFeatures = get_original_feature_positions( $templateFile );

    ( $fastaSeqInfo, $emblTmpFile ) = create_array_of_sub_info( $fastaFile );

    calculate_new_feature_positions( @$origFeatures, @$fastaSeqInfo );

    # convert fasta sequence into embl format
    compile_embl_entries( $skelFile, @$fastaSeqInfo, $emblTmpFile );
}

################################################################################
# Run the script

main(@ARGV);
 
