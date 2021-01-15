#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2006
#
#  SCRIPT DESCRIPTION:
#
#  A script copy emails from Jitterbug to the ds directory
#
#  MODIFICATION HISTORY:
#  CVS version control block - do not edit manually
#  $RCSfile: testmod.pl,v $
#  $Revision: 1.1 $
#  $Date: 2008/01/25 11:50:06 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/testmod.pl,v $
#  $Author: szilva $
#
#===============================================================================

use strict;
use Date::Manip;
use File::Copy;
use SeqDBUtils22;

# Global variables
my ( $verbose );

my $usage =
  "\n PURPOSE: Finds a thread of emails in Jitterbug and offers to copy\n"
  . "          one or more of these files to the current directory:\n\n"
  . " USAGE:   copy_jb_emails.pl [-j=<Jitterbug thread ID>]\n"
  . "          [-s=<section of Jitterbug>] [-h] [-v]\n\n"
  . "   -j=<Jitterbug thread ID or URL>   where <Jitterbug thread ID or URL> is\n"
  . "                   either the number of the Jitterbug thread/case\n"
  . "                   (e.g. 172790) OR the URL of the Jitterbug web page\n"
  . "                   e.g. http://systems.ebi.ac.uk/cgi-bin/embl-...\n"
  . "                   A url must be entered on the command line in quotation\n"
  . "                   marks (single or double) so 'special' characters are ignored.\n"
  . "                   NB a Jitterbug URL must contain a Jitterbug thread ID.\n\n"
  . "   -s=<section of Jitterbug>         where <section of Jitterbug> can be\n"
  . "                   upd or sub (default: sub) denoting the part of the\n"
  . "                   Jitterbug system you want to search for the emails in.\n\n"
  . "   -v              verbose\n\n"
  . "   -h              shows this help text\n\n";

################################################################################
# check jitterbug type is valid

sub check_jitterbug_type($) {

    my $jbType = shift;

    if (($jbType !~ /^upd$/i) && ($jbType !~ /^sub$/i)) {
	print "Warning:\nThe entered Jitterbug type was not expected. EMBL-SUB will be searched by default.\n\n";
    }

    return($jbType);
}

################################################################################
# check jitterbug url is valid and if so extract data from it

sub check_jitterbug_url($) {

    my ( $jbId, $jbDirType );

    my $jbUrl = shift;

    if ( $jbUrl =~ /^http.+?cgi-bin\/embl-(sub|upd).+?id=(\d+)/ ) {
	$jbDirType = $1;
	$jbId = $2;
    } 
    else {
	die "Format of the entered Jitterbug URL entered is not recognised.\n\n$usage";
    }

    return( $jbId, $jbDirType );
}

################################################################################
# If not entered, ask for the jitterbug thread id

sub request_jitterbug_id {

    my ( $input, $jbId, $jbDirType );

    print "Jitterbug thread ID or URL: ";
    chomp( $input = <STDIN> );
    $input =~ s/\s+//g;

    if ( $input =~ /^http:.+/ ) {
	( $jbId, $jbDirType ) = check_jitterbug_url( $input );
    }
    elsif ( $input !~ /^\d+$/ ) {
	die "Input format not recognised. The required format is either a purely numeric ID or a URL (web address).\n";
    }
    else {
	$jbId = $input;
	$jbDirType = "";
    }

    return( $jbId, $jbDirType );
}

################################################################################
# find the directory that contains the jitterbug thread id

sub display_notes_file($) {

    my $file = shift;

    if (open( READNOTES, "<$file" )) {
	print "\nNotes\n";
	print "-----\n";
	while ( <READNOTES> ) {
	    print $_;
	}
	close( READNOTES );
	print "\n-----\n";
    }
    else {
	print "\nCould not open notes file: $file\n";
    }
}

################################################################################
# find the directory that contains the jitterbug thread id

sub get_email_files($$) {

    my ( $searchArchive, @searchDir, $archivePathPrefix, $archivePathSuffix );
    my ( $findFiles, $file, @emailFiles );

    my $jbId      = shift;
    my $jbDirType = shift;

    $archivePathPrefix = '/usr/local/jitterbug/EMBL-';
    $archivePathSuffix = "/bugs/*/".$jbId.".*";

    # grab archives to search (EMBL-SUB and EMBL_UPD available)
    if ( !$jbDirType ) {
	$searchArchive = 'SUB';
    }
    else {
	if ( $jbDirType =~ /upd/i ) {
	    $searchArchive = 'UPD'; 
	}
	else {
	    $searchArchive = 'SUB';
	}
    }

    # search archive
    $findFiles = $archivePathPrefix.$searchArchive.$archivePathSuffix;

    if ( $verbose ) {
	print "\nLooking for files with the pattern:\n".$findFiles,"\n";
    }

    @searchDir = glob( $findFiles ); 

    # if we find some files with the jitterbug id prefix...
    if ( @searchDir ) {

	foreach $file ( @searchDir ) {

	    if ($file !~ /.+?\.(audit|notes)/) {
		push(@emailFiles, $file );
	    } elsif ( $file =~ /.+?\.notes/) {
		display_notes_file( $file );
	    }
	}
    } 

    if ( !@emailFiles ) {
	die "No emails can be found with the Jitterbug thread ID of $jbId\n";
    }

    return ( \@emailFiles );
}

################################################################################
# format file name for displaying

sub format_email_file_name($) {

    my ( @fileName, $emailFileName, $fileNamePadLen );

    my $filePath = shift;

    $fileNamePadLen = 23;

    @fileName = split( '/', $filePath );
    $emailFileName = $fileName[-1];
    $emailFileName =~ s/^\d+\.//;

    $emailFileName = right_pad_or_chop($emailFileName, 18, " ", "... ");

    return( $emailFileName );
}


################################################################################
# format email 'from' data

sub format_email_from($) {

    my ( $fromPadLen );

    my $emailFrom  = shift;

    $emailFrom =~ s/"//g;    #"
    $emailFrom =~ s/\@ebi\.ac\.uk//g;

    $emailFrom = right_pad_or_chop($emailFrom, 34, " ", "... ");

    return( $emailFrom );
}

################################################################################
# format email 'to' data

sub format_email_to($) {

    my ( $toPadLen );

    my $emailTo  = shift;
    $toPadLen = 15;

    $emailTo =~ s/"//g;    #"
    $emailTo =~ s/\@ebi\.ac\.uk//g;

    if ( length( $emailTo ) > 13) {
	$emailTo = substr( $emailTo, 0, 13 ) . "... ";
    }

    return( $emailTo );
}

################################################################################
# check email details are present and if not, add in substitute values

sub check_email_details_are_complete(\@\@\@\%$) {

    my ( $datePadLen );

    my $emailFrom    = shift;
    my $emailTo      = shift;
    my $emailDate    = shift;
    my $fileDate     = shift;
    my $emailCounter = shift;
    
    $datePadLen = 10;

    # if date or from not found in file (e.g. attachment file)
    if ( !$$emailFrom[$emailCounter] ) {
	if (( $emailCounter > 0 ) && ( $$emailFrom[($emailCounter-1)] )) {
	    $$emailFrom[$emailCounter] = $$emailFrom[($emailCounter-1)];
	}
	else {
	    $$emailFrom[$emailCounter] = "??";
	    $$emailFrom[$emailCounter] = format_email_from( $$emailFrom[$emailCounter] );
	}
    }
    if ( !$$emailTo[$emailCounter] ) {
	if (( $emailCounter > 0 ) && ( $$emailTo[($emailCounter-1)]) ) {
	    $$emailTo[$emailCounter] = $$emailTo[($emailCounter-1)];
	}
	else {
	    $$emailTo[$emailCounter] = "??";
	}
    }
    if (!$$emailDate[$emailCounter]) {
	if (($emailCounter > 0) && ($$emailDate[($emailCounter-1)])) {
	    $$fileDate{$emailCounter} = $$fileDate{($emailCounter - 1)};
	    $$emailDate[$emailCounter] = $$emailDate[($emailCounter-1)];
	}
	else {
	    $$fileDate{$emailCounter} = 0;
	    $$emailDate[$emailCounter] = "??";
	    $$emailDate[$emailCounter] = right_pad_or_chop($$emailDate[$emailCounter], $datePadLen, " ");
	}
    }
}

################################################################################
# display info on the available emails

sub get_copied_files_list {

    my ( $copiedFile, $newFileName, %copiedFiles );

    open(BROWSECOPIEDFILES, "<.copied_files.log") || die "Cannot read .copied_files.log\n";

    while (<BROWSECOPIEDFILES>) {
	($copiedFile, $newFileName) = split(/\t/, $_);
	chomp($newFileName);

	if (-e $newFileName) {
	    $copiedFiles{$copiedFile} = $newFileName;
	}
    }
    
    close(BROWSECOPIEDFILES);

    return(\%copiedFiles);
}

################################################################################
# suggest a new file name (depending on names of existing copied files)

sub suggested_file_name($) {

    my ( $prefix, $fileType, @fileExt, $cleanFileType, $fileNum, $newFileType );
    my ( $filePattern, @copiedEmails, @fileName, $submitter, $subSuffix );
    my ( @orderedFileNum, $suggestedFileName, @fileNum, $copiedEmail );

    my $file = shift;

    # get submitter name
    @fileName = find_files("", ".info");
    if ($fileName[0]) {
	($submitter, $subSuffix) = split(/\./, $fileName[0]);
    }
	
    if ($submitter) {

	($prefix, $fileType, @fileExt) = split(/\./, $file);

	    if ($fileType eq "reply") {
		$newFileType = "query";
	    }
	    elsif ($fileType eq "followup") {
		$newFileType = "resp";
	    }
	    else {
		$newFileType = $fileType;
	    }

	if ($submitter) {
	    $filePattern = $submitter.".".$newFileType."*";
	    @copiedEmails = glob($filePattern);

	    # if there are pre-exisiting emails
	    if ((@copiedEmails) && ($copiedEmails[0] !~ /\*/)) {

		foreach $copiedEmail (@copiedEmails) {
		    ($prefix, $subSuffix) = split(/\./, $copiedEmail);

		    if ($subSuffix =~ /[a-z](\d+)/) {
			push(@fileNum, $1); 
		    }
		}

		@orderedFileNum = sort {$a <=> $b} @fileNum;

		$suggestedFileName = $submitter.".".$newFileType;
		$suggestedFileName .= ($orderedFileNum[-1] + 1);

		if ((defined $fileExt[1]) && ($fileExt[1] =~/^att/)) {
		    $suggestedFileName .= '.att';
		}
	    }
	    else {
		$suggestedFileName = $submitter.".".$newFileType."1";
	    }
	}
    }

    if (! $suggestedFileName) {
	$suggestedFileName = "";
    }

    return($suggestedFileName);
}

################################################################################
# display info on the available emails

sub display_email_info(\@) {

    my ( $email, $line, @emailFrom, @emailTo, @emailDate, @emailFileName );
    my ( $emailCounter, $padChar, $fromFlag, %fileDate, $fileId, $element );
    my ( $dateFlag, $toFlag, @fileName, $datePadLen, $fileNum, @displayOrder );
    my ( $copiedFiles, @copyChar, $copyFlag, $logFile, $printFileId );

    my $emailFiles = shift;

    $padChar = " ";
    $datePadLen = 10;

    $logFile = ".copied_files.log";
    if (-e $logFile) {
	$copiedFiles = get_copied_files_list();
    } 

    print "\n  ID Date      File name\t From\t\t\t\t   To\n";
    print "--------------------------------------------------------------------------------\n";

    $emailCounter = 0;
    foreach $email ( @$emailFiles ) {

	if ($$copiedFiles{$email}) {
	    $copyChar[$emailCounter] = "C ";
	    $copyFlag = 1;
	}
	else {
	    $copyChar[$emailCounter] = "  ";
	}

	# if not an attachment file
	if ( $email !~ /[^\d]+\d+(\.followup\.\d+)?\.att\d+\..+$/ ) {
	    open(READEMAIL, "<$email") || die "Cannot open email file: $email";

	    $fromFlag = 0;
	    $toFlag = 0;
	    $dateFlag = 0;

	    while ( $line = <READEMAIL> ) {

		# Email from
		if ( $line =~ /^From:\s+([^\n]+)\n/ ) {
		    $emailFrom[$emailCounter] = format_email_from( $1 );
		    $fromFlag = 1;
		}
		# Email to
		elsif ( $line =~ /^To:\s+([^\n]+)\n/ ) {
		    $emailTo[$emailCounter] = format_email_to( $1 );
		    $toFlag = 1;
		}
		# Email date
		elsif (( $line =~ /^Date:\s+([^:]+:\d\d:\d\d) [A-Z]{3}[^\n]+\n/ ) || ( $line =~ /^Date:\s+([^\n]+)\n/ )){
		    $fileDate{$emailCounter} = UnixDate( ParseDate($1), "%s" );
		    $emailDate[$emailCounter] = UnixDate( ParseDate($1), "%d-%b-%y" )." ";
		    $dateFlag = 1;
		}
		
		if ( $fromFlag && $toFlag && $dateFlag ) {
		    last;
		}
	    }
	    close(READEMAIL);
	}
	    
	# format file name
	$emailFileName[$emailCounter] = format_email_file_name( $email );

	# if empty, populate the variables
	check_email_details_are_complete( @emailFrom, @emailTo, @emailDate, %fileDate, $emailCounter );
	$emailCounter++;
    }

    # find date order of email files
    foreach $fileNum (sort { $fileDate{$a} <=> $fileDate{$b} } keys( %fileDate )) {
	push( @displayOrder, $fileNum );
    }

    # display file info in date order
    $fileId = 1;
    foreach $element ( @displayOrder ) {

	$printFileId = right_pad_or_chop($fileId, 3, " ", "");

	print $copyChar[$element].$printFileId.$emailDate[$element].$emailFileName[$element].$emailFrom[$element].$emailTo[$element]."\n";
	$fileId++;
    }

    if (defined($copyFlag)) {
	print "\nC=file already copied\n";
    }
	
    return( \@displayOrder );
}

################################################################################
# get the new filename to copy the jitterbug file to
 
sub get_new_file_name($) {

    my ( $renameFile, $overwriteFlag, $suggestedFileName );

    my $copyFile = shift;

    while (! defined( $renameFile )) {	

	$suggestedFileName = suggested_file_name($copyFile);

	if ($suggestedFileName ne "") {
	    print "Save as ($suggestedFileName): ";
	} else {
	    print "Save as: ";
	}

	chomp( $renameFile = <STDIN> );

	if ((! defined($renameFile)) || ($renameFile =~ /Y(ES)?/i) || ($renameFile !~ /[A-z0-9]+/)) {
	    $renameFile = $suggestedFileName;
	}
	elsif ( -e $renameFile ) {
	    print "Warning: $renameFile is already in use.\n";

	    $overwriteFlag = "";
	    while (( $overwriteFlag ne "y" ) && ( $overwriteFlag ne "n" )) {
		print "Overwrite file (y/n)? ";
		chomp ( $overwriteFlag = <STDIN> );
	    }
	    
	    if ( $overwriteFlag eq "n" ) {
		$renameFile = "";
	    }
	}
    }

    return ( $renameFile );
}

################################################################################
# ask the user which files they'd like to copy and copy them

sub copy_files(\@\@) {

    my ( $copyFile, $cmd, $newFileName, $element, %copiedFiles );

    my $emailFiles   = shift;
    my $displayOrder = shift;

    $copyFile = "";
    while ( $copyFile ne "q" ) {

	print "\nEnter file ID to copy (or q to quit): "; 
	chomp( $copyFile = <STDIN> );
	$copyFile =~ s/\s+//g;

	if ( $copyFile =~ /^(\d+)$/ ) {

	    # stop users putting in FileId of 0
	    if ( $1 > 0 ) {
		$element = $$displayOrder[( $1 - 1 )];

		if (! $$emailFiles[$element]) {
		    print "Warning: File ID not recognised\n";
		}
		else {
		    $copyFile = $$emailFiles[$element];
		    $newFileName = get_new_file_name($copyFile);
		    
		    # copy file
		    copy( $copyFile, $newFileName ) || die "$copyFile cannot be copied.";
		    print "Copying file...\n"; 
		    $copiedFiles{$copyFile} = $newFileName;
		}
	    }
	    else {
		print "Warning: File ID not recognised\n";
	    }
	}
    }

    if ( $copyFile eq "q" ) {
	print "Quitting on request.\n";
    }

    return(\%copiedFiles);
}

################################################################################
# refresh the log of files which have been copied

sub write_log(\%) {

    my ( $newlyCopiedFiles, $copiedFile, $newFileName, %copiedFiles );
    my ( $newlyCopiedFile, $logFile );

    $newlyCopiedFiles = shift;

    $logFile = ".copied_files.log";

    if (%$newlyCopiedFiles) {
       
	# get original list of copied files
	if (-e $logFile) {
	    open(READCOPIEDFILES, "<$logFile") || die "Cannot read $logFile\n";

	    while (<READCOPIEDFILES>) {
		($copiedFile, $newFileName) = split(/\t/, $_);

		# ignore copied files for which the copy has been deleted
		chomp($newFileName);
		if (-e $newFileName) {
		    $copiedFiles{$copiedFile} = $newFileName;
		}
	    }

	    close(READCOPIEDFILES);
	}

	# add any newly copied files to original copied file list
	foreach $newlyCopiedFile (keys %$newlyCopiedFiles) {
	    $copiedFiles{$newlyCopiedFile} = $$newlyCopiedFiles{$newlyCopiedFile};
	}

	# save copied list to file
	open(SAVECOPIEDFILES, ">$logFile") || die "Cannot save to $logFile\n";
	
	foreach $copiedFile (sort ( keys %copiedFiles )) {
	    printf SAVECOPIEDFILES "$copiedFile\t$copiedFiles{$copiedFile}\n";
	}

	close(SAVECOPIEDFILES);
    }
}

################################################################################
# reduce size of the large email header style

sub clean_large_email_header($) {

    my $data = shift;

    $data =~ s/^From [^@]+\@[A-z0-9_-]+(\.[A-z0-9_-]+)+[^\n]+\n//;
    $data =~ s/Received: \(?[^\n]+\n(\t[A-Za-z]+[^\n]+\n)*//g;
    $data =~ s/Message-ID: [^\n]+\n//;
    $data =~ s/DomainKey-Signature:[^\n]+\n(  [a-z]=[^\n]+\n)*//g;
    $data =~ s/X-[A-Z][A-Za-z]+(-[A-Za-z]+)?: [^\n]+\n(\t[^\n]+\n)*//g;
    $data =~ s/In-Reply-To: [^\n]+\n//g;
    $data =~ s/MIME-Version: [^\n]+\n//g;
    $data =~ s/Content-[A-Za-z][^:]+: [^\n]+\n(\t[^\n]+\n)*//g;

    return($data);
}

################################################################################
# remove strange jitterbug inserted patterns from copied files

sub clean_copied_files(\%) {

	my ( $data, $copiedFile );

	my $files = shift;

	foreach $copiedFile (keys %$files) {
	    open(READFILE, "<$$files{$copiedFile}") || die "Cannot open file to check for bad characters: $$files{$copiedFile}\n";

	    $data = do{local $/; <READFILE>}; # read file into string
	    close(READFILE);

	    open(SAVECLEANFILE, ">$$files{$copiedFile}") || die "Cannot open file for cleaning: $$files{$copiedFile}\n";

	    # emails from embl have oversized email header info - shrink it!
	    if ($$files{$copiedFile} =~ /\.followup/) {
		$data = clean_large_email_header($data);
	    }

	    $data = substitute_jitterbug_chars($data);

	    print SAVECLEANFILE $data;
	    close(SAVECLEANFILE);
	}
}

################################################################################
# make sure all the right arguments have been received

sub get_args(\@) {

    my ( $jbId, $jbDirType, $arg );

    my $args = shift;

    $verbose = 0;

    # check the arguments for values
    foreach $arg ( @$args ) {

	if ( $arg =~ /^\-h/ ) { # display help message
	    die $usage;
	}
        elsif ( $arg =~ /^\-v/ ) {    # verbose mode
            $verbose = 1;
        }
        elsif ( $arg =~ /^\-j=(\d+)$/ ) {   # jitterbug id
	    $jbId = $1;
        }
        elsif ( $arg =~ /^\-j=(.+)$/ ) {    # url/anything else
	    ($jbId, $jbDirType) = check_jitterbug_url( $1 );
        }
        elsif ( $arg =~ /^\-j=?$/ ) {   # jitterbug option is empty (used in alias)
	    # jbId remains empty
        }
        elsif ( $arg =~ /^\-s=(.+)$/ ) {    # sub or upd
	    $jbDirType = check_jitterbug_type( $1 );
        }
        else {
            die "Unrecognised argument format \"$arg\"\n$usage";
        }
    }

    if (!$jbId) {
	( $jbId, $jbDirType ) = request_jitterbug_id();
    }

    return ( $jbId, $jbDirType );
}

################################################################################
# main function

sub main(\@) {

    my ( $jbId, $jbDirType, $emailFiles, $displayOrder, $copiedFiles );

    my $args = shift;

    # check arguments are intact
    ( $jbId, $jbDirType ) = get_args(@$args);

    # find the directory containing the jitterbug ID
    ( $emailFiles ) = get_email_files( $jbId, $jbDirType );

    # ask user which files to copy and copy them
    $displayOrder = display_email_info( @$emailFiles );
    $copiedFiles = copy_files( @$emailFiles, @$displayOrder );

    write_log(%$copiedFiles);
    clean_copied_files(%$copiedFiles);
}

################################################################################
# Run the script

main( @ARGV );
