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
#  $RCSfile: fasta2subs2.pl,v $
#  $Revision: 1.19 $
#  $Date: 2010/04/01 15:39:31 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/fasta2subs2.pl,v $
#  $Author: gemmah $
#
#===============================================================================

use strict;
use Date::Manip;
use SeqDBUtils2;
use generateSubs;

# Global variables (used in many subroutines)
my ( $verbose, $args );

my $fastaExtension    = 'fasta';
my $skeletonExtension = 'skel';
my $replaceToken1     = '---';
my $mySeqLengthToken1 = $replaceToken1 . "SL" . $replaceToken1;
my $replaceToken2a    = quotemeta('{');
my $replaceToken2b    = quotemeta('}');
my $mySeqLengthToken2 = $replaceToken2a . "SL" . $replaceToken2b;
my $saveFileName      = "BULK.SUBS";
my $entrytype = "embl";
my $usage =
  "\n PURPOSE: Uses sequences from a fasta file to make EMBL sub files\n"
  . "          based on a skeleton:\n\n"
  . " USAGE:   mega [-f=<.".$fastaExtension." file>]\n"
  . "          [-t=<.".$skeletonExtension." file>] [-h] [-v]\n\n"
  . "    e.g.1 [-f=hoad01.fasta] [-t=hoad01.skel]\n"
  . "    e.g.2 [-f=hoad01.fasta] [-t=hoad.skel]\n\n"
  . "   -f=<file>         where <file> must be a file with the .".$fastaExtension."\n"
  . "                   extension. This file must contain a list of sequences\n"
  . "                   in fasta format.\n"
  . "   -t=<file>         where <file> is a template file with the .".$skeletonExtension."\n"
  . "                   extension.\n"
  . "                   This file must contain an EMBL entry template. i.e. an\n"
  . "                   EMBL file up to, but not including, the SQ line.\n"
  . "                   " . $mySeqLengthToken1 . " or " . $mySeqLengthToken2. " marks where "
  . "the sequence length is\n"
  . "                   to be inserted and ".$replaceToken1."n".$replaceToken1." or "
  .$replaceToken2a."n".$replaceToken2b." marks where a\n"
  . "                   field relating to the sequence is to be inserted\n"
  . "                   (where n is the variable number starting from 1).\n"
  . "                   NB multiple variables are separated on the '>'\n"
  . "                   comment line of the fasta file using semi-colons.\n"
  . "                   As default, the prefix of the fasta file will find\n"
  . "                   the appropriate ." . $skeletonExtension . " file.\n\n"
  . "   -v              verbose\n\n"
  . "   -h              shows this help text\n\n";


################################################################################
# get the Webin direcrtory from the ds .info file

sub get_webin_dir {

    my ( $code, $value, $webin, $ip, $infoFile, $dir, @infoFile );
    $webin = '';
    $ip    = '';

    @infoFile = find_files( "", ".info" );    # module subroutine

    if ( defined( $infoFile[0] ) ) {
	open( READINFO, "<$infoFile[0]" ) || die "Cannot open .info file: $infoFile: $!\n";

	while (<READINFO>) {

	    ( $code, $value ) = split ( ': ', $_ );

	    if ( $code eq 'WID' ) {
		$value =~ s/\s+//g;
		chomp($value);
		$webin = $value;
		if ($webin =~ /^SPIN/) {
		    print "Switching to UniProt mode because the info file says it was a SPIN submission\n";
		    $entrytype = "UP";
		}
        }
	    elsif ( $code eq 'WIP' ) {
		$value =~ s/\s+//g;
		chomp($value);
		$ip = $value;
	    }
	    if ( ( $webin ne "" ) && ( $ip ne "" ) ) {
		last;
	    }
	}
	close(READINFO);

	$dir = $ENV{WEBINDAT} . "/" . $ip . ":" . $webin;
	#$dir = "/homes/gemmah/scripts/mockup/" . $ip . ":" . $webin;
    }
    else {
	$dir = "";
    }

    return ($dir);
}

################################################################################
# Create a new skeleton/template file from FLATFILE.DOC, overwriting the
# existing input skel file.

sub make_new_skel_file($) {

    my ( $fileToUpdate, $webinDir, $field, $other, $fieldNumber, %fields, $template );
    my ( $i, $spaceHolder, $replacementString, $fieldOrderFile, $templateFile );
    my ( $templateLine, $line );

    my $skelFile = shift;

    if ($verbose) {
        print "Making a new skeleton/template file...\n";
    }

    $fileToUpdate   = ">" . $skelFile;
    $webinDir       = get_webin_dir();
    $fieldOrderFile = $webinDir . '/BULK_CONFIG';
    $templateFile   = $webinDir . '/FLATFILE.DOC';

    open( READFIELDS, "<$fieldOrderFile" ) || die "Cannot open Webin configuration file $fieldOrderFile: $!\n";

    # put field name ('organism') and field number (e.g. to translate into
    # {1}  where 1 is the field number) together in a look-up hash
    $fieldNumber = 1;
    while (<READFIELDS>) {

        ( $field, $other ) = split ( /=/, $_ );

        if ( ( $field ne "total" ) && ( $field ne "current" ) ) {
            $fields{$field} = $fieldNumber;
            $fieldNumber++;
        }
    }
    close(READFIELDS);

    # Read template into a variable
    open( READTEMPLATE, "<$templateFile" ) || die "Cannot open Webin template $templateFile: $!\n";
    while ( $line = <READTEMPLATE> ) {
        $template .= $line;
    }
    close(READTEMPLATE);

    # make substitutions in template
    $template =~ s/\r+/\n/g;              # remove any dos characters
    $template =~ s/\n+/\n/g;              # remove any empty lines generated by prev command.
    $template =~ s/SQ.+?\n//;             # remove sequence line
    $template =~ s/\{sequence\}.*\n//;    # remove sequence line
    $template =~ s/\/\/.*?\n//;           # remove entry separator

    $template =~ s/\{sequence length\}/$mySeqLengthToken2/g;

    # substitute fields
    foreach $field ( keys %fields ) {
        $template =~ s/\{$field\}/\{$fields{$field}\}/g;
    }

    open( WRITESKEL, ">$fileToUpdate" ) || die "Cannot open a new skeleton file $skelFile: $!\n";
    printf WRITESKEL $template;
    close(WRITESKEL);

    # ask if the user wants to exit the script at this point
    exit_script_after_making_skel($skelFile);

    return ($skelFile);
}

################################################################################
# see if skel file is up to date.  If not, regenerate it.

sub get_up_to_date_skel_file($$) {

    my ( $bulkConfig, $bulkConfigDate, $flatfileDoc );
    my ( $flatfileDocDate, $newestWebin, $newestFlag, $skelDate );
    my ( $makeNewSkelFlag, $generateSkelFile, $skipFlag );

    my $skelFile = shift;
    my $webinDir = shift;

    $bulkConfig  = $webinDir . '/BULK_CONFIG';
    $flatfileDoc = $webinDir . '/FLATFILE.DOC';

    if ( -e $skelFile ) {

	$newestWebin     = 2;    # assigned number that won't be returned from Date_cmp function
	$flatfileDocDate = 2;
	$skipFlag        = 0;

	# if a skel file has been chosen, get dates of <Webin directory>/BULK_CONFIG
	# and <Webin directory>/FLATFILE.DOC to compare with date of skel file

	# get newest date out of BULK_CONFIG and FLATFILE.DOC
	if ( -e $bulkConfig ) {
	    $bulkConfigDate = localtime +( stat($bulkConfig) )[9];
	}
	else {
	    if ($verbose) {
		print "Using entered .skel file because " . $bulkConfig . " does not exist.\n\n";
	    }
	    $skipFlag = 1;
	}

	# skipFlag with a value of 1 indicates there's no point doing
	# anymore checks if BULK_CONFIG doesn't exist
	if ( $skipFlag == 0 ) {
	    if ( -e $flatfileDoc ) {
		$flatfileDocDate = localtime +( stat($flatfileDoc) )[9];
		$newestFlag      = Date_Cmp( $bulkConfigDate, $flatfileDocDate );
		
		if    ( $newestFlag == -1 ) { $newestWebin = $flatfileDocDate; }
		elsif ( $newestFlag == 1 )  { $newestWebin = $bulkConfigDate; }
		elsif ( $newestFlag == 0 )  { $newestWebin = $flatfileDocDate; } # both files have identical date/times
	    }
	}
	
	# take date/time of skel file and compare it to that of the newest Webin directory file
	$skelDate   = localtime +( stat($skelFile) )[9];
	$newestFlag = Date_Cmp( $newestWebin, $skelDate );
	
	if    ( $newestFlag == -1 ) { $makeNewSkelFlag = 0; }
	elsif ( $newestFlag == 1 )  { $makeNewSkelFlag = 1; }
	elsif ( $newestFlag == 0 )  { $makeNewSkelFlag = 0; } # both files have identical date/times
	
	if ( $makeNewSkelFlag == 1 ) {
	    print "There are more recent files available than those the entered .skel file ";
	    print "($skelFile) was generated from. Do you want to generate a new .skel file? (n/y) (or q to quit):\n";
	    chomp( $generateSkelFile = <STDIN> );
	    
	    if ( $generateSkelFile eq 'q' ) {
		die "Quitting on request\n";
	    }
	    elsif ( $generateSkelFile ne 'y' ) {
		$makeNewSkelFlag = 0;
	    }
	}
	else {
	    if ($verbose) {
		print "$skelFile is up-to-date.\n";
	    }
	}
    }
    # if skel file generated from fastaFilePrefix (in get_args) doesn't exist...
    else {
	$makeNewSkelFlag = 1;
    }
    
    #generate new skel file (just the once)
    if ( $makeNewSkelFlag == 1 ) {
	if ( !( -e $bulkConfig ) ) {
	    die "\nCannot make a new .skel template file because the Webin" . 
		"bulk configuration\nfile cannot be found: $bulkConfig\n";
	}
	elsif ( !( -e $flatfileDoc ) ) {
	    die "\nCannot make a new .skel template file because the Webin" . 
		"bulk template\nfile cannot be found: $flatfileDoc\n";
	}
	else {
	    make_new_skel_file($skelFile);
	}
    }

    return ($skelFile);
}

################################################################################
# Exit the script after making the skel file

sub exit_script_after_making_skel($) {

    my ($exitFlag);
    my $skelFile = shift;

    print "$skelFile has been created.\n\n";
    print "Would you like to continue processing the fasta file to create EMBL entries (y/n) (or q to quit)?\n";
    chomp( $exitFlag = <STDIN> );

    if ( ( $exitFlag =~ /^n/ ) || ( $exitFlag =~ /^q/ ) ) {
        die "Quitting on request\n";
    }
}

################################################################################
# check if all the fasta characters are indicative of problems

sub check_for_illegal_characters($$$$$$) {

    my $message;

    my $seq         = shift;
    my $READFASTA   = shift;
    my $SAVEEMBLTMP = shift;
    my $fastaHeader = shift;
    my $emblTmpFile = shift;
    my $errorMsg    = shift;

    $seq =~ s/\s+/ /g;
    if ( $seq =~ /([ACTGRYMKSWHBVDNU=. \n\r\t]{0,5})([^ACTGRYMKSWHBVDNU=. \n\r\t]+)([ACTGRYMKSWHBVDNU=. \n\r\t]{0,5})/i ) { # I have no idea what the premise of this test is; I understand illegal characters, but why the {0,5}
        $message = "Unauthorised character(s) '$2' have been found within '$1$2$3' in:\n$fastaHeader$seq\n\n" . $errorMsg;
        printf $SAVEEMBLTMP $message;
        close($SAVEEMBLTMP);
        close($READFASTA);
        die $message;
    }
}

################################################################################
# builds the embl entry i.e. adds fasta header fields to the skel template and
# combines with reformatted sequence -> new embl entry

sub build_embl_entry($$$$$$$$$$$$) {

    my ( @substitutions, $tokenNum, $subs, $tmp1, $tmp2, $message, $continue );

    my $currentEmblEntry    = shift;
    my $fastaHeader         = shift;
    my $formattedSeq        = shift;
    my $seqlen              = shift;
    my $skelFile            = shift;
    my $fastaSeqNumber      = shift;
    my $fastaLineNumber     = shift;
    my $READFASTA           = shift;
    my $SAVEEMBLTMP         = shift;
    my $errorMsg            = shift;
    my $errorLocation       = shift;
    my $checkForSpareTokens = shift;

    $continue = 0;    

    (@substitutions) = split( /;/, $fastaHeader );

    #clean line (remove dos characters)
    $currentEmblEntry =~ s/\r+/\n/g;

    $tokenNum = 1;
    foreach $subs (@substitutions) {

        $tmp1 = $replaceToken1 . $tokenNum . $replaceToken1;
        $tmp2 = $replaceToken2a . $tokenNum . $replaceToken2b;

        if ( ( $currentEmblEntry =~ /$tmp1/ ) || ( $currentEmblEntry =~ /$tmp2/ ) ) {
            $currentEmblEntry =~ s/$tmp1/$subs/g;
            $currentEmblEntry =~ s/$tmp2/$subs/g;
            $tokenNum++;
        }
        else {
            $message = "Warning:\nThere are not enough tokens for the number of fields in the fasta header\n>$fastaHeader\n\n" . $errorLocation . $errorMsg;
            printf $SAVEEMBLTMP $message;
            close($SAVEEMBLTMP);
            close($READFASTA);
            die $message;
        }
    }

    $currentEmblEntry =~ s/$mySeqLengthToken1/$seqlen/g;
    $currentEmblEntry =~ s/$mySeqLengthToken2/$seqlen/g;

    # make any left over tokens blank but warn and give option to exit script
    if ($checkForSpareTokens) {
        if ( ( $currentEmblEntry =~ /$replaceToken1\d+$replaceToken1/ ) || ( $currentEmblEntry =~ /$replaceToken2a\d+$replaceToken2b/ ) ) {

            $currentEmblEntry =~ s/$replaceToken1\d+$replaceToken1//g;
            $currentEmblEntry =~ s/$replaceToken2a\d+$replaceToken2b//g;

            $message = "Warning: There were some extra tokens in your skel file, as compared to the number of fields in the fasta header:\n>$fastaHeader\n$errorLocation\n";
            print $message;
            print "Continue processing data (y/n) (or q to quit)?\n";

            chomp( $continue = <STDIN> );
            if ( ( $continue eq 'q' ) || ( $continue eq 'n' ) ) {
                printf $SAVEEMBLTMP $message;
                close($SAVEEMBLTMP);
                close($READFASTA);
                die "Quitting on request\n";
            }
            else {
                $checkForSpareTokens = 0;
            }
        }
    }

    $currentEmblEntry .= $formattedSeq;

    return ( $currentEmblEntry, $checkForSpareTokens );
}

################################################################################
# Change format of fasta sequence to embl format

sub compile_embl_entries($$) {

    my ( $line, $seq, $newFormat, $seqlen, $fastaPrefix, $fastaSuffix );
    my ( $fastaHeader, $nextFastaHeader, $currentEmblEntry, $emblEntryLength );
    my ( $template, $tmp, $seqLineFormat, $emblTmpFile, $tmpFileDeletedFlag );
    my ( $SAVEEMBLTMP, $READFASTA, $fastaFileLineNum, $seqErrorMsg, $headerErrorLocn );
    my ( $checkForSpareTokens, $seqCounter, $fastaSeqCounter, %fastaHeaders );
    my ( $errorSavedTo, $seqErrorLocn, $fastaSeqLineNum );
    my ( $headerLineNum, $origFastaHeader );

    my $skelFile  = shift;
    my $fastaFile = shift;

    # open a temp file for temporarily storing the output (in case of error).
    ( $fastaPrefix, $fastaSuffix ) = split( /\./, $fastaFile );
    $emblTmpFile = ">" . $fastaPrefix . ".embltmp";

    open( $SAVEEMBLTMP, $emblTmpFile ) || die "Cannot open temporary file $emblTmpFile: $!\n";
    $emblTmpFile =~ s/^>//;

    # open skel file
    open( TEMPLATE, "<$skelFile" ) || die "Cannot read skeleton file $skelFile: $!\n";
    $template = do{local $/; <TEMPLATE>}; # read file into string
    close(TEMPLATE);

    # quick check to see if template contains the correct contents...
    ($template =~ /^ID   /s) or die "The template file $skelFile does not begin with \"ID   \"\n"; 

    increment_decrement_char_check( $template, $skelFile );

    # open file of fasta sequences
    open( $READFASTA, "<$fastaFile" ) || die "Cannot open fasta file $fastaFile: $!\n";

    $checkForSpareTokens = 1;    # indicates whether spare tokens should be checked for in skel
    $seq                 = '';
    $fastaFileLineNum    = 1;    # counter used in error messages
    $fastaSeqCounter     = 0;    # counter used in error messages
    my $uracil_warning        = 0;
    while ( $line = <$READFASTA> ) {
        #clean line (remove dos characters);
        $line =~ s/\r+/\n/g;
        $line =~ s/\n+/\n/g;

	if (($line =~ /^\s*$/) && (!eof($READFASTA))) {
	    next;
	}
        # process sequence
        if ( eof($READFASTA) ) {
	    if ($line !~ /^\/\//) {
		$seq .= $line;
	    }
        }

        if ( ( ( $line =~ /^>/ ) || ( eof($READFASTA) ) ) && ( $seq ne '' ) ) {

            $fastaSeqCounter++;
            $nextFastaHeader = $line;

	    if (! $headerLineNum) {
		$headerLineNum = 1;
	    }

	    $fastaSeqLineNum = $headerLineNum+1;
	    $seqErrorLocn    = "Error found in $fastaFile (line $fastaSeqLineNum, fasta sequence number $fastaSeqCounter). ";
	    $headerErrorLocn = "Error found in $fastaFile (line $headerLineNum, fasta sequence number $fastaSeqCounter). ";
	    $errorSavedTo    = "Take a look in $emblTmpFile for the output up to this point. Exiting script...\n";
	    $seqErrorMsg     = $seqErrorLocn.$errorSavedTo;

	    chomp($fastaHeader);
	    $origFastaHeader = $fastaHeader;

            if ($entrytype eq "embl") {
		check_for_illegal_characters( $seq, $READFASTA, $SAVEEMBLTMP, $origFastaHeader, $emblTmpFile, $seqErrorMsg );
		if ($seq =~ s/u/T/ig) { # For people using U instead of T
		    if ($uracil_warning == 0) {
			print "Warning: Uracils found in fasta file, replacing with thymine\n";
			$uracil_warning = 1;
		    }
		}
	    }

	    $fastaHeader =~ s/^>//;
	    $fastaHeader =~ s/\s*;\s*/;/g;
	    $fastaHeader =~ s/(^\s*)|(;?\s*$)//g;

            # test for duplicates
            check_for_duplicate_fastaheader( $fastaHeader, $origFastaHeader, %fastaHeaders, $fastaSeqCounter, $headerLineNum );

            # change sequence in embl format
            if ($entrytype eq "UP") {
		( $newFormat, $seqlen ) = reformat_uniprot_sequence($seq);
	    } else {
		( $newFormat, $seqlen ) = reformat_sequence($seq);
	    }
            # make substitutions in skel file template and combine with reformatted sequence
            ( $currentEmblEntry, $checkForSpareTokens ) =
              build_embl_entry( $template, $fastaHeader, $newFormat, $seqlen, $skelFile, $fastaSeqCounter, $headerLineNum, $READFASTA, $SAVEEMBLTMP, $errorSavedTo, $headerErrorLocn, $checkForSpareTokens );

            # save embl entry to temp file
            print $SAVEEMBLTMP $currentEmblEntry;

	    $headerLineNum = $fastaFileLineNum;

            if ($nextFastaHeader) {
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

    }    # end of reading fastafile

    close($READFASTA);
    close($SAVEEMBLTMP);

    # if we've got this far without complaints, save the contents of <fastaprefix>.embltmp
    # to BULK.SUBS
    save_data( $emblTmpFile, $fastaSeqCounter, $fastaFile, "fasta2subs", $saveFileName, $verbose );

    delete_file($emblTmpFile, $verbose);
}

################################################################################
# make sure all the right arguments have been received

sub get_args(\@) {

    my ( $fileList, $usePrefixFlag, $i, $fastaArgsFlag, $skelFileName );
    my ( $skelArgsFlag, $fastaPrefix, $fastaSuffix, $fastaFileName );
    my ( $makeSkelFile, $makeSkelFileFlag, $webinDir, $message );

    my $args = shift;

    $verbose       = 0;
    $fastaArgsFlag = 0;
    $skelArgsFlag  = 0;

    $fastaFileName = "";
    $skelFileName  = "";

    print "\n";

    # check the arguments for values
    for ( $i = 0 ; $i < @$args ; $i++ ) {

        if ( $$args[$i] =~ /^\-v/ ) {    # verbose mode
            $verbose = 1;
        }
        elsif ( $$args[$i] =~ /^\-f=(.+)$/ ) {    #fasta file
            $fastaFileName = check_input_file( $1, $fastaExtension, $fastaExtension, $verbose );
	    while ($fastaFileName eq "") {
		$fastaFileName = ask_for_input_file( $fastaExtension );
		$fastaFileName = check_input_file( $fastaFileName, $fastaExtension, $fastaExtension, $verbose );
	    }
            $fastaArgsFlag = 1;
        }
        elsif ( $$args[$i] =~ /^\-t=(.+)$/ ) {    # skel/template file
            $skelFileName = check_input_file( $1, $skeletonExtension, $fastaExtension, $verbose );
	    while ($skelFileName eq "") {
		$skelFileName = ask_for_input_file( $skeletonExtension );
		$skelFileName = check_input_file( $skelFileName, $skeletonExtension, $fastaExtension, $verbose );
	    }
            $skelArgsFlag = 1;
        }
        elsif ( $$args[$i] =~ /^-h/ ) {
            die $usage;
        }
        else {
            die "Unrecognised argument format \"$$args[$i]\"\n" .
		$usage;
        }
    }

    # In no fasta files are provided in the args, look for one in the current directory
    if ( !$fastaArgsFlag ) {

        $fileList = get_directory_listing($fastaExtension);

        if ( $fileList eq "" ) {
            die "There are no ." . $fastaExtension . " files in this directory.\n";
        }

        # prompt for a file if there is 1+ fasta files in the directory
        elsif ( $fileList =~ /,/ ) {
            print "More than one " . $fastaExtension . " file has been found.\n";
	    while ($fastaFileName eq "") {
		$fastaFileName = ask_for_input_file( $fastaExtension );
		$fastaFileName = check_input_file( $fastaFileName, $fastaExtension, $fastaExtension, $verbose );
	    }
        }

        # if there is only 1 .fasta file in this directory, get file name from directory listing
        else {
            $fileList =~ s/\[//;
            $fileList =~ s/\]//;
            $fastaFileName = $fileList;
            print "$fileList will be used as the source of fasta sequences in this script.\n";
        }
    }

    # if there is no skel file provided in the args, either:
    # a. find the skel file and check it's up-to-date, if old, regenerate it.
    # b. regenerate the skel file
    if ( !$skelArgsFlag ) {

        $fileList = get_directory_listing($skeletonExtension);

	if ($fileList) {
	    # prompt for a file if there is 1+ fasta files in the directory
	    if ( $fileList =~ /,/ ) {
		print "More than one " . $skeletonExtension . " file has been found.\n";
		print "Do you want to use the fasta file prefix to locate the associated .skel file in this directory? (Note: This may involve making a new .skel file) (y/n) (or q to quit):\n";
		chomp( $usePrefixFlag = <STDIN> );

		if ( $usePrefixFlag eq "q" ) {
		    die "Quitting on request\n";
		}
		elsif ( $usePrefixFlag ne "y" ) {
		    while ($skelFileName eq "") {
			$skelFileName = ask_for_input_file( $skeletonExtension );
			$skelFileName = check_input_file( $skelFileName, $skeletonExtension, $fastaExtension, $verbose );
		    }
		}
		else {
		    ( $fastaPrefix, $fastaSuffix ) = split ( /\./, $fastaFileName );
		    $skelFileName = $fastaPrefix . ".skel";
		}
	    }
	    # for a single skel file in this directory, get file name from directory listing ...
	    elsif ( $fileList ne "" ) {
		$fileList =~ s/\[//;
		$fileList =~ s/\]//;
		$skelFileName = $fileList;
		print "$skelFileName will be used as the EMBL entry template in this script.\n\n";

	    }
	}
        # if there are no .skel files in the directory
        else {
            print "There are no .skel template files in this directory.\n";
            ( $fastaPrefix, $fastaSuffix ) = split ( /\./, $fastaFileName );
            $skelFileName = $fastaPrefix . ".skel";
        }
    }

    $webinDir = get_webin_dir();

    if ($webinDir ne "") {
	$skelFileName = get_up_to_date_skel_file( $skelFileName, $webinDir );
    }
    else {
	$message = "Cannot make new .skel file because there is no .info file in this directory (required for finding files in the Webin directory).\n";

	if (! (-e $skelFileName) ) {
	    print $message;
	    die "Cannot proceed without a .skel file.\nExiting script...\n";
	} 
	elsif ($verbose) {
	    print $message;
	}
    }

    return ( $fastaFileName, $skelFileName );
}

################################################################################
# make sure embl entries are wrapped to 80 characters - call external script
# to process this

sub wrap_embl_entries {

    my ( $wrappingScript, $writeFile, @wrappedEntries, $message );
    $wrappingScript = "/ebi/production/seqdb/embl/tools/curators/scripts/linewrap.pl";
    $writeFile      = '>' . $saveFileName;

    if ($verbose) {
        print "Checking EMBL entries are wrapped at 80 characters...\n";
    }

    $message =
      "Completed EMBL entries have already been saved to $saveFileName. In the event this message is being read, in order to simply make sure the EMBL entries are correctly wrapped, you need to locate Nadeem's script called linewrap.pl and to run the following command (run from THIS directory) to ensure wrapping occurs:\nlinewrap.pl $saveFileName > $saveFileName\n";

    open( READENTRIES, "-|" )
      or exec( $wrappingScript, $saveFileName ) || die "Cannot open $wrappingScript in order to wrap entries to 80 characters. $message\n";
    @wrappedEntries = <READENTRIES>;
    close(READENTRIES);

    open( WRITEENTRIES, $writeFile ) || die "Cannot open $writeFile in order to save wrapped EMBL entries. $message\n";
    foreach (@wrappedEntries) {
        printf WRITEENTRIES $_;
    }
    close(WRITEENTRIES);
}

sub reformat_uniprot_sequence {
    my $seq = shift;
    my $newFormat = uc($seq);
    $newFormat =~ s/[^A-Z]//g;
    my $seqlen = length($newFormat);
    $newFormat = "SQ   \n$newFormat\n//\n";
    return ( $newFormat, $seqlen );
}

################################################################################
# main function

sub main(\@) {

    my ( $fastaFile, $skelFile );

    my $args = shift;

    # check arguments are intact
    ( $fastaFile, $skelFile ) = get_args(@$args);

    # convert fasta sequence into embl format
    compile_embl_entries( $skelFile, $fastaFile );

    # make sure the output embl entries are wrapped at 80 characters
    #wrap_embl_entries(); # commented out 12-Jun-07 on Nadeem's request
}

################################################################################
# Run the script

main(@ARGV);
 
