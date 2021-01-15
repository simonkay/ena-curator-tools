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
#  $RCSfile: copy_jb_emails.pl,v $
#  $Revision: 1.39 $
#  $Date: 2010/09/24 13:37:02 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/copy_jb_emails.pl,v $
#  $Author: faruque $
#
#===============================================================================
 
use strict;
use Date::Manip;
use File::Copy;
use SeqDBUtils2;
use Cwd;
use Data::Dumper;

# Global variables
my ( $verbose );
my $logFile = ".copied_files.log";

my $usage =
  "\n PURPOSE: Finds a thread of emails in Jitterbug and offers to copy\n"
  . "          one or more of these files to the current directory:\n\n"
  . " USAGE:   copy_jb_emails.pl [-j=<Jitterbug thread ID>]\n"
  . "          [-all] [-s=<section of Jitterbug>] [-h] [-v]\n\n"
  . "   -j=<Jitterbug thread ID or URL>   where <Jitterbug thread ID or URL> is\n"
  . "                   either the number of the Jitterbug thread/case\n"
  . "                   (e.g. 172790) OR the URL of the Jitterbug web page\n"
  . "                   e.g. http://jitterbug.ebi.ac.uk/cgi-bin/embl-...\n"
  . "                   A url must be entered on the command line in quotation\n"
  . "                   marks (single or double) so special characters are ignored.\n"
  . "                   NB a Jitterbug URL must contain a Jitterbug thread ID.\n\n"
  . "   -all            Downloads whole email thread (not including attachments).\n\n"
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

sub request_jitterbug_id($) {

    my ( $input, $jbId );

    my $jbDirType = shift;

    print "Jitterbug thread ID or URL: ";
    chomp( $input = <STDIN> );
    $input =~ s/\s+//g;

    if ( $input =~ /^http:.+/ ) {
	( $jbId, $jbDirType ) = check_jitterbug_url( $input );
    }
    elsif ( $input !~ /^\d+$/ ) {
	die "The input '".$input."' is not recognised as a Jitterbug thread ID or URL.\n";
    }
    else {
	$jbId = $input;
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

sub get_email_files($$$) {

    my ( $searchArchive, @searchDir, $archivePathPrefix, $archivePathSuffix );
    my ( $findFiles, $file, @emailFiles, $i, $jbFolder);

    my $jbId      = shift;
    my $jbDirType = shift;
    my $saveAllThreads = shift;

    $archivePathPrefix = '/usr/local/jitterbug/EMBL-';
    $archivePathSuffix = "/bugs/*/".$jbId;

    # grab archives to search (EMBL-SUB and EMBL_UPD available)
    if ( !$jbDirType ) {
	$searchArchive = 'UPD';
    }
    else {
	if ( $jbDirType =~ /sub/i ) {
	    $searchArchive = 'SUB'; 
	}
	else {
	    $searchArchive = 'UPD';
	}
    }

    # search archive
    $findFiles = $archivePathPrefix.$searchArchive.$archivePathSuffix;

    if ( $verbose ) {
	print "\nLooking for files with the pattern:\n".$findFiles,"\n";
    }

# find primary thread files, and once found look for additional ones
    @searchDir = (glob( $findFiles ));
    if (defined ($searchDir[0])) {
	foreach my $candidateFile (glob( $findFiles.".*" )){ # $searchDir[0] would be better but square brackets in some dir names cause problems
	    if (defined($candidateFile)) {
		push(@searchDir, $candidateFile);
	    } else {
		print "skipped\n";
	    }
	}
    }

    if (! @searchDir ) {

	if ($searchArchive eq 'UPD') {
	    $searchArchive = 'SUB';
	} 
	else {
	    $searchArchive = 'UPD';
	}

	$findFiles = $archivePathPrefix.$searchArchive.$archivePathSuffix;

	if ( $verbose ) {
	    print "No files found.\n\n"
	         ."Looking for files with the pattern:\n".$findFiles,"\n";
	}

# find primary thread files, and once found look for additional ones
	@searchDir = (glob( $findFiles ));
	if (defined ($searchDir[0])) {
	    foreach my $candidateFile (glob( $findFiles.".*" )){ # $searchDir[0] would be better but square brackets in some dir names cause problems
		if (defined($candidateFile)) {
		    push(@searchDir, $candidateFile);
		} else {
		    print "skipped\n";
		}
	    }
	}
    }

    if ( @searchDir ) {
	$i = 0;
	foreach $file ( @searchDir ) {

	    if (! $i) {
		# get jitterbug directory e.g rutha-fin
		$file =~ /$archivePathPrefix(SUB|UPD)\/bugs\/([^\/]+)\//;
		$jbFolder = $2;
	    }

	    if ($file !~ /.+?\.(audit|notes|notify)/) {
		push(@emailFiles, $file);
	    } 
	    elsif (( $file =~ /.+?\.notes/ ) && (!$saveAllThreads)) {
		display_notes_file( $file );
		$i = 1;
	    }
	}
    } 

    if ( !@emailFiles ) {
	die "No emails can be found with the Jitterbug thread ID of $jbId\n";
    }

    return ( \@emailFiles, $searchArchive, $jbFolder );
}

################################################################################
# format file name for displaying

sub format_email_file_name($) {

    my ( @fileName, $emailFileName );

    my $filePath = shift;

    @fileName = split( '/', $filePath );
    $emailFileName = $fileName[-1];
    $emailFileName =~ s/^\d+\.//;

    $emailFileName = right_pad_or_chop($emailFileName, 25 , " ", "... ");

    return( $emailFileName );
}


################################################################################
# format email 'from' data

sub format_email_from($) {

    my $emailFrom  = shift;

    $emailFrom =~ s/"//g;    #"
    $emailFrom =~ s/\@ebi\.ac\.uk//g;

    $emailFrom = right_pad_or_chop($emailFrom, 23, " ", "... ");

    return( $emailFrom );
}

################################################################################
# format email 'to' data

sub format_email_to($) {

    my ( $toPadLen );

    my $emailTo  = shift;
    $toPadLen = 13;

    $emailTo =~ s/"//g;    #"
    $emailTo =~ s/\@ebi\.ac\.uk//g;

    if ( length( $emailTo ) > $toPadLen) {
	$emailTo = substr( $emailTo, 0,  ($toPadLen+2)) . "... ";
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
	    #$$emailDate[$emailCounter] = $$emailDate[($emailCounter-1)];
	    $$emailDate[$emailCounter] = "          ";
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

    if (open(BROWSECOPIEDFILES, "<$logFile")) {

	while (<BROWSECOPIEDFILES>) {
	    ($newFileName, $copiedFile) = split(/\t/, $_);
	    chomp($copiedFile);

	    if (-e $newFileName) {
		$copiedFiles{$newFileName} = $copiedFile;
	    }
	}
	
	close(BROWSECOPIEDFILES);
	
	return(\%copiedFiles);
    }
}

################################################################################
# check if the file is an ncbi consultation

sub check_if_consult_email($) {

    my ( $fileContents, $consultFlag );

    my $email = shift;
    $consultFlag = 0;

    # if email is not an attachment, see if it contains the standard 
    # consultation email subject
    if ( $email !~ /[^\d]+\d+(\.followup\.\d+)?\.att\.?\d+\..+$/ ) {
	open(READEMAIL, "<$email") || die "Cannot open email file: $email";
	$fileContents = do{local $/; <READEMAIL>}; 

	if ( $fileContents =~ /Subject: ([rReE]{2}: )?Consult n =/ ) {
	    $consultFlag = 1;
	}
	close(READEMAIL);
    }

    return($consultFlag);
}

################################################################################
# see if attachment file parent email has been copied and use it's filename as 
# the attachment file prefix

sub make_attachment_file_extension($$) {

    my ( $newFileExt, $origFileName, $copiedFiles, $checkForFileName );
    my ( @origFilePath, $attExtension, @attPath );

    my $attName    = shift;
    my $parentFile = shift;

    @attPath = split( /\//, $attName);

    if (($attPath[-1] =~ /^(\d+)(\.att\.?\d+\.)(.+)/) || ($attPath[-1] =~ /^(\d+\.(followup|reply)\.\d+)\.att\.?\d+\.(.+)/)) {
	$checkForFileName = $1;
	$attExtension = $3;

	if ($parentFile) {
	    $newFileExt = $parentFile.".".$attExtension;
	    $newFileExt =~ s/^[^.]+\.//;
	}
	else {
	    if (-e $logFile) {
		$copiedFiles = get_copied_files_list();
		
		foreach $origFileName (values %$copiedFiles) {

		    @origFilePath = split( /\//, $origFileName );

		    if ( $checkForFileName eq $origFilePath[-1] ) {
			$newFileExt = $origFileName.".".$attExtension;
			$newFileExt =~ s/^[^.]+\.//;
			last;
		    }
		}
	    }
	}

	# if file is copied individually (without parent having been copied)
	if (! $newFileExt) {
	    $newFileExt = $attExtension;
	}
    }

    return($newFileExt);
}

################################################################################
# suggest a new file name (depending on names of existing copied files)

sub suggested_file_name($$$;$) {

    my ( $prefix, $fileExt, $newFileType, $consultFlag, @fileNameParts );
    my ( $filePattern, @copiedEmails, @fileName, $submitter, $subSuffix );
    my ( @orderedFileNum, $suggestedFileName, @fileNum, $copiedEmail );
    my ( $addNumber, $attachmentFlag, $emailLogList, $needsUnderscore );
    my ( $highestNum );

    my $file     = shift;
    my $jbDir    = shift;
    my $jbFolder = shift;
    my $parent   = shift;

    # get submitter name
    if ($jbDir =~ /SUB/i) {
	@fileName = find_files("", ".info");
    
	if ($fileName[0]) {
	    ($submitter, $subSuffix) = split(/\./, $fileName[0]);
	}

	if ($submitter) {

	    $emailLogList = get_copied_files_list();
	    
	    ($prefix, $fileExt) = split(/\./, $file, 2);

	    $consultFlag = check_if_consult_email($file);

	    if ($fileExt) {
		if ( $fileExt =~ /^(.*?\.)?att\.?\d+/ ) {
		    $newFileType = make_attachment_file_extension($file, $parent);
		    $attachmentFlag = 1;
		}
		elsif ( $fileExt =~ /^reply/ ) {
		    $newFileType = "query";
		}
		elsif ( $fileExt =~ /^followup/ ) {
		    $newFileType = "resp";
		}
		else {
		    $fileExt =~ s/\.\d+$//;
		    $newFileType = $fileExt;
		}

		if (!$consultFlag) {
		    #if ($jbFolder =~ /^sra/) {
			#$filePattern = $newFileType."*";
		    #}
		    #else {
			$filePattern = $submitter.".".$newFileType."*";
		    #}
		}
		else {
		    if ($newFileType eq "query") {
			$suggestedFileName = "consult.tax";
		    }
		    elsif ($newFileType eq "resp") {
			$suggestedFileName = "consult.resp";
		    }
		    $filePattern = $suggestedFileName."*";
		}

		@copiedEmails = glob($filePattern);

		# if there are pre-exisiting emails...
		if ((@copiedEmails) && ($copiedEmails[0] !~ /\*/)) {

		    foreach $copiedEmail (@copiedEmails) {
			@fileNameParts = ();
			@fileNameParts = split(/\./, $copiedEmail);

			if ($fileNameParts[-1] =~ /[A-Za-z]\d*?_(\d+)$/) {
			    push(@fileNum, $1); 
			    $needsUnderscore = 1;
			}
			elsif ($fileNameParts[-1] =~ /[A-Za-z](\d+)$/) {
			    push(@fileNum, $1);
			    
			    if ( $fileExt =~ /^(.*?\.)?att\.?\d+/ ) {
				$needsUnderscore = 1;	
			    }
			}
			elsif ($fileNameParts[-1] =~ /[A-Za-z]$/) {
			    $addNumber = 1;
			}
		    }
		
		    if (@fileNum) {
			@orderedFileNum = sort {$a <=> $b} @fileNum;
			
			if (!$consultFlag) {

			    if ($jbFolder =~ /^sra/) {
				$suggestedFileName = $newFileType;
			    }
			    else {
				$suggestedFileName = $submitter.".".$newFileType;
			    }

			    if ($needsUnderscore) {
				$suggestedFileName .= "_";
			    }
			}
			$suggestedFileName .= ($orderedFileNum[-1] + 1);
		    }
		    elsif ($addNumber) {
			if (! $consultFlag) {

			    if ($jbFolder =~ /^sra/) {
				$suggestedFileName = $newFileType;
			    }
			    else {
				$suggestedFileName = $submitter.".".$newFileType;
			    }

			    if ($attachmentFlag) {
				$suggestedFileName .= "_";
			    }
			}
			$suggestedFileName .= "2";
		    }
		}
		# if this is the first email of it's kind...
		else {
		    if (!$consultFlag) {
			if ($jbFolder =~ /^sra/) {
			    $suggestedFileName = $newFileType;
			}
			else {
			    $suggestedFileName = $submitter.".".$newFileType;
			}

			if (( $newFileType !~ /\d+$/ ) && (!$attachmentFlag)) {
			    $suggestedFileName .= "1";
			}
		    }
		}
	    }
	}
    }
    # if in EMBL-UPD directory
    else {

	$filePattern = "cit.upd*";
	@copiedEmails = glob($filePattern);

	# if there are pre-exisiting emails...
	if ((@copiedEmails) && ($copiedEmails[0] !~ /\*/)) {

	    $suggestedFileName = "cit.upd";
	    $highestNum = 0;
	    
	    foreach $copiedEmail (@copiedEmails) {
		@fileNameParts = ();
		@fileNameParts = split(/\./, $copiedEmail);

		if ($fileNameParts[1] =~ /(\d+)$/) {
		    if ($1 > $highestNum) {
			$highestNum = $1;
		    }
		}
		else {
		    $highestNum = 1;
		}
	    }
	    
	    $suggestedFileName = "cit.upd".($highestNum + 1);
	}
    }

    if (! $suggestedFileName) {
	#$suggestedFileName = "";
	if ($file =~ /followup\.\d+\.att\.?\d*\.(.+)/) {
	    $suggestedFileName = $1;
	
	    my $tmp = $suggestedFileName;
	    my $counter = 1;
	    while (-e $tmp) {
		$tmp = $suggestedFileName.".$counter";
		$counter++;
	    }
	    $suggestedFileName = $tmp;
	}
    }

    return($suggestedFileName);
}

################################################################################
# Change the order of which the emails will be printed out to the screen

sub order_files(\%\@) {

    my ( @displayOrder, $fileNum, $i, $attachmentPrefix, $prevAttachmentPrefix );
    my ( @emailGroups, $j, @emailGroupElements, @elementNumAtStartOfGroup );
    my ( %fileToFileNumber, @sortedDisplayOrder, @sortedEmailFileNames, @list );

    my $fileDate = shift;
    my $emailFileName = shift;

    # find date order of email files
    foreach $fileNum (sort { $$fileDate{$a} <=> $$fileDate{$b} } keys( %$fileDate )) {
	push( @displayOrder, $fileNum );
    }

    # switch order of attachments with their parent emails
    $j=-1;
    $prevAttachmentPrefix = "_";
    $attachmentPrefix = "";

    for ($i=0; $i<@displayOrder; $i++) {

	if ($i) {
	    $prevAttachmentPrefix = $attachmentPrefix;
	}

	if ( $$emailFileName[$displayOrder[$i]] =~ /^([^.]+(\.\d+)?)/ ) {
	    $attachmentPrefix = $1;
	    chomp($attachmentPrefix);
	}

	if ($prevAttachmentPrefix ne $attachmentPrefix) {
	    $j++;
	    push(@elementNumAtStartOfGroup, $i);
	}

	$fileToFileNumber{$$emailFileName[$displayOrder[$i]]} = $displayOrder[$i];
	push(@{ $emailGroups[$j] }, $$emailFileName[$displayOrder[$i]]);
	push(@{ $emailGroupElements[$j] }, $displayOrder[$i]);
    }

    for ($i=0; $i<@emailGroups; $i++) {

	# make array, for convenience of sorting
	@list = @{ $emailGroups[$i] };
	
	#get lowest element number (for renumbering display order)
	@sortedDisplayOrder = sort({$a <=> $b} @{$emailGroupElements[$i]});
	
	# sort files by att number
	@sortedEmailFileNames = @list[
			   map { unpack "N", substr($_,-4) }
			   sort
			   map {
			       my $key = $list[$_];
			       $key =~ s[(\d+)][ pack "N", $1 ]ge;
			       $key . pack "N", $_
			       } 0..$#list
			   ];

	$j = $elementNumAtStartOfGroup[$i];
	foreach $emailFileName (@sortedEmailFileNames) {

	    $displayOrder[$j] = $fileToFileNumber{$emailFileName};
	    $j++;
	}
    }



    return(\@displayOrder);
}

################################################################################
# display info on the available emails

sub display_email_info(\@$) {

    my ( $email, $line, @emailFrom, @emailTo, @emailDate, @emailFileName, $value );
    my ( $emailCounter, $fromFlag, %fileDate, $fileId, $element, $copiedFiles );
    my ( $dateFlag, $toFlag, $displayOrder, $copyFlag, @copyChar, $printFileId );
    my ( @copiedFilePath, @emailPath, $grabbed_date );

    my $emailFiles = shift;
    my $saveAllThreads = shift;

    if (-e $logFile) {
	$copiedFiles = get_copied_files_list();
    } 

    if (! $saveAllThreads ) {
	print "\n  ID Date      File name\t\tFrom\t\t       To\n";
	print "--------------------------------------------------------------------------------\n";
    }

    $emailCounter = 0;
    foreach $email ( @$emailFiles ) {

	# see if log already contains this email
	@emailPath = split( /\//, $email);
	$copyFlag = 0;
	foreach $value (values %$copiedFiles) {
	    @copiedFilePath = split( /\//, $value);

	    if ($copiedFilePath[-1] eq $emailPath[-1]) {
		$copyChar[$emailCounter] = "C ";
		$copyFlag = 1;
		last;
	    }
	}
	if (!$copyFlag) {
	    $copyChar[$emailCounter] = "  ";
	}

	# if not an attachment file
	if ( $email !~ /[^\d]+\d+(\.followup\.\d+)?\.att\.?\d+\..+$/ ) {
	    open(READEMAIL, "<$email") || die "Cannot open email file: $email";

	    $fromFlag = 0;
	    $toFlag = 0;
	    $dateFlag = 0;

	    while ( $line = <READEMAIL> ) {

		# Email from
		if ( $line =~ /^From:\s+.*?([A-Za-z0-9._-]+\@[A-Za-z0-9._-]+)/ ) {
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

		    my $grabbed_date = $1; 
		    if ($grabbed_date =~ /([^\+]+\s*)([\+\-])(\d{3}\b.*)/) {
                        # zero pad if like " Wed, 17 Oct 2007 12:10:52 +100";
			$grabbed_date = $1.$2."0".$3;
		    }

		    # ParseDate does not cope with summer, eg
                    # Fri, 24 Sep 2010 10:43:53 +0100 (BST)
		    if ($grabbed_date =~ s/\s([\+\-])\s*(\d{4})\s+\(BST\)\s*$/ /) {
			my $offsetDirection = $1;
			my $offsetAmount = $2; 
			if ($offsetDirection eq '+') {
			    $offsetAmount += 100; 
			} else {
			    $offsetAmount -= 100; 
			}
			$grabbed_date .= sprintf("%s%04d", $offsetDirection, $offsetAmount);
		    }
		    $fileDate{$emailCounter} = UnixDate( ParseDate($grabbed_date), "%s" );
		    $emailDate[$emailCounter] = UnixDate( ParseDate($grabbed_date), "%d-%b-%y" )." ";
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

    # display file info in date order
    $displayOrder = order_files(%fileDate, @emailFileName);

    if (! $saveAllThreads) {
	$fileId = 1;
	foreach $element ( @$displayOrder ) {

	    $printFileId = right_pad_or_chop($fileId, 3, " ", "");

	    print $copyChar[$element].$printFileId.$emailDate[$element].$emailFileName[$element].$emailFrom[$element].$emailTo[$element]."\n";
	    $fileId++;
	}
	
	if ($copyFlag) {
	    print "\nC=file already copied\n";
	}
    }
    
    return( $displayOrder );
}

################################################################################
#

sub warn_about_overwriting($) {

    my ($overwriteFlag);

    my $filename = shift;

    if (-e $filename) {
	print "Warning: filename $filename is already in use.\n";
    
	$overwriteFlag = "";
	while (( $overwriteFlag ne "y" ) && ( $overwriteFlag ne "n" )) {
	    print "Overwrite file (y/n)? ";
	    chomp ( $overwriteFlag = <STDIN> );
	}
    }
    return($overwriteFlag);
}
################################################################################
#
sub ask_for_file_name($$$;$) {

    my ( $renameFile, $overwriteFlag, $suggestedFileName, $printCopyFile );

    my $copyFile    = shift;
    my $jbDir       = shift;
    my $jbFolder    = shift;
    my $parentFile  = shift;

    while ( (! defined($renameFile)) || ($renameFile eq "") ) {	

	$suggestedFileName = suggested_file_name( $copyFile, $jbDir, $jbFolder, $parentFile);

	if (($jbFolder =~ /^sra/) && ($copyFile =~ /\/\d+\.(followup|reply)\.\d+\.att\d*\.(.+)$/)) {
	    $printCopyFile = $2;
	}
	elsif (($copyFile =~ /\/\d+\.(.+)$/) || ($copyFile =~ /\/(\d+)$/)) {
	    $printCopyFile = $1;
	}
	elsif ($copyFile =~ /(followup|reply)(\.\d+)$/) {
	    $printCopyFile = $copyFile;
	}
	elsif ($copyFile =~ /(.+)(\.\d+)$/) {
	    $printCopyFile = $1;
	}
        else {
	    $printCopyFile = $copyFile;
	}

	if ((defined($suggestedFileName)) && ($suggestedFileName ne "")) {
	    print "Save $printCopyFile as [$suggestedFileName]: ";
	} else {
	    print "Save $printCopyFile as: ";
	}

	$renameFile = <STDIN>;
	$renameFile =~ s/\s+//g;

	if (defined($suggestedFileName) && ($suggestedFileName ne "") && ((! defined($renameFile)) || ($renameFile =~ /^Y(ES)?$/i) || ($renameFile !~ /[A-z0-9]+/))) {
	    $renameFile = $suggestedFileName;
	}
	elsif ( (! defined($renameFile)) || ($renameFile =~ /^\s+$/) ) {
	    $renameFile = "";
	}
    }

    return ( $renameFile );
}
################################################################################
#
sub get_new_file_name($$$;$) {

    my ($yn_response, $filename1);

    my $copyFile    = shift;
    my $jbDir       = shift;
    my $jbFolder    = shift;
    my $parentFile  = shift;

    $filename1 = ask_for_file_name($copyFile, $jbDir, $jbFolder, $parentFile);

    while (-e $filename1) {
	$yn_response = warn_about_overwriting($filename1);

	if ($yn_response eq 'y') {
	    last;
	}
	else {
	    $filename1 = ask_for_file_name($filename1, $jbDir, $jbFolder, $parentFile);
	}
    }

    return($filename1);
}
################################################################################
# if there is an attachment to the email available, ask if the user wants to copy it

sub prompt_for_attachment_copying($\@$$$) {

    my ( @attachedFiles, $attachFileFlag, $renameAttachment, $recognisedInput );
    my ( $fileExt, $emailFile, $numAttachments, $att, %attachments, @filePath );

    my $copyFile    = shift;
    my $emailFiles  = shift;
    my $jbDir       = shift;
    my $parentFile  = shift;
    my $jbFolder    = shift;

    foreach $emailFile ( @$emailFiles ) {

	if ( $emailFile =~ /^$copyFile(.*?\.att\.?\d+\..+)/ ) {
	    $fileExt = $1;

	    #if (($copyFile !~ /\/\d+$/) || (($copyFile =~ /\/\d+$/) && ($fileExt !~ /^\.(followup|reply)/))) {
	    if ($fileExt !~ /^\.(followup|reply)/) {
		push(@attachedFiles, $emailFile);
	    }
	}
    }

    $numAttachments = @attachedFiles;

    if ( $numAttachments == 1 ) {
	print "* This email contains an attachment.\n";
    }
    elsif ( $numAttachments > 1 ) {
	print "* This email contains $numAttachments attachments.\n";
    }



    foreach $att (@attachedFiles) {

	$attachFileFlag = "";

	if ( $numAttachments == 1 ) {
	    while (($attachFileFlag ne "y") && ($attachFileFlag ne "n")) {
		print "  Copy attached file too (y/n)? ";
		chomp( $attachFileFlag = <STDIN> );
	    }
	}
	else {
	    @filePath = split(/\//, $att);
	    my $filename = $filePath[-1];
	    $filename =~ s/^\d+\.(followup|reply)\.\d+\.att\d*\.(.+)/$2/;

	    while (($attachFileFlag ne "y") && ($attachFileFlag ne "n")) {
		print "  Copy attached file $filename (y/n)? ";
		chomp( $attachFileFlag = <STDIN> );
	    }
	}

	if ( $attachFileFlag eq "y" ) {
	    $renameAttachment = get_new_file_name($att, $jbDir, $jbFolder, $parentFile);
	    $attachments{$att} = $renameAttachment;
	}
    }

    if (keys %attachments) {
	return(\%attachments);
    }
    else {
	return(0);
    }
}

################################################################################
# Display emails that have been copied earlier

sub display_pre_copied_letters($\%) {

    my ( $logFiles, $file, %files, @conFiles, @sortedConFiles, @regFiles, $i );
    my ( @sortedFiles, @foundFiles, @allFiles, @findFilePatterns, $filePattern );

    my $jbDir       = shift;
    my $copiedFiles = shift;

    #instead, find files matching *.query*, *.resp* and consult.*
    @findFilePatterns = ('*.query*', '*.resp*', 'consult.*', '*.*upd*');

    foreach $filePattern (@findFilePatterns) {
	@foundFiles = glob($filePattern);
	push(@allFiles, @foundFiles);
    }

    if ($jbDir =~ /SUB/i) {
	# split different file types into different arrays, for sorting

	foreach $file ( @allFiles ) {
	    if ($file =~ /^consult\./) {
		$file =~ s/\.tax(\d*)/.atax$1/;
		push(@conFiles, $file);
	    }
	    elsif ($file =~ /\.(query|resp)\d*/) {
		push(@regFiles, $file);
	    }
	}
	# sort regular files
	if (@regFiles) {
	    @sortedFiles =  sort {
		substr($a, (rindex($a, '.resp') > -1) ? (5 + rindex($a, '.resp')) : (6 + rindex($a, '.query')))
		cmp 
		substr($b, (rindex($b, '.resp') > -1) ? (5 + rindex($b, '.resp')) : (6 + rindex($b, '.query'))) 
		|| $a cmp $b
	    }  @regFiles;
	}

	# sort consult files
	if (@conFiles) {
	    @sortedConFiles =  sort {
		substr($a, (rindex($a, '.resp') > -1) ? (5 + rindex($a, '.resp')) : (5 + rindex($a, '.atax')))
		cmp 
		substr($b, (rindex($b, '.resp') > -1) ? (5 + rindex($b, '.resp')) : (5 + rindex($b, '.atax'))) 
		|| $a cmp $b
	    }  @conFiles;
	
	    for ($i= 0; $i<@sortedConFiles; $i++) {
		$sortedConFiles[$i] =~ s/\.atax(\d*)/.tax$1/;
	    }
	}

	push(@sortedFiles, @sortedConFiles);	
    }
    # if in an EMBL-UPD directory...
    else {

	foreach $file ( @allFiles ) {
	    if ($file =~ /\..*upd/) {
		push(@regFiles, $file);
	    }
	}
	@sortedFiles = sort {$a cmp $b} @regFiles;
    }

    if (@sortedFiles) {
	print "Letters in ds:\n";
	print join(" ", @sortedFiles) . "\n";
    }
    
}

################################################################################
# ask the user which files they'd like to copy and copy them

sub copy_files(\@\@$$) {

    my ( $copyFile, $newFileName, $element, %copiedFiles, $fileCounter );
    my ( $copyAttFiles, $att, $jb_att, $use_att_name );

    my $emailFiles   = shift;
    my $displayOrder = shift;
    my $jbDir        = shift;
    my $jbFolder     = shift;

    $copyFile = "";
    $fileCounter = 1;

    while ( $copyFile ne "q" ) {

	if ($fileCounter == 1) {
	    print "\nEnter file ID to copy (or q to quit): "; 
	}
	else {
	    print "\nEnter another file ID to copy (or q to quit): "; 
	}
	chomp( $copyFile = <STDIN> );
	$copyFile =~ s/\s+//g;

	if ( $copyFile =~ /^(\d+)$/ ) {

	    # stop users putting in FileId of 0
	    if (( $1 > 0 ) && ( $1 < (@$displayOrder + 1 ))) {
		$element = $$displayOrder[( $1 - 1 )];

		if (! $$emailFiles[$element]) {
		    print "Warning: File ID not recognised\n";
		}
		else {
		    display_pre_copied_letters( $jbDir,  %copiedFiles );

		    $copyFile = $$emailFiles[$element];
		    $newFileName = get_new_file_name( $copyFile, $jbDir, $jbFolder );
		    
		    # copy file
		    copy( $copyFile, $newFileName ) || die "$copyFile cannot be copied.";
		    print "Saving as $newFileName\n";
		    $copiedFiles{$newFileName} = $copyFile;

		    ($copyAttFiles) = prompt_for_attachment_copying( $copyFile, @$emailFiles, $jbDir, $newFileName, $jbFolder );

		    if ($copyAttFiles) {

			foreach $jb_att (keys %$copyAttFiles) {

			    $use_att_name = $$copyAttFiles{$jb_att};

			    copy( $jb_att, $use_att_name ) || die "$jb_att cannot be copied to $use_att_name.\n";
			    print "Saving as $use_att_name \n";
			    $copiedFiles{$use_att_name} = $jb_att;
			}
		    }
		}
	    }
	    else {
		print "Warning: File ID not recognised\n";
	    }
	}

	$fileCounter++;
    }

    if ( $copyFile eq "q" ) {
	print "Quitting on request.\n";
    }

    return(\%copiedFiles);
}

################################################################################
# refresh the log of files which have been copied

sub write_log(\%) {

    my ( $newlyCopiedFiles, $fileName, $newFileName, %copiedFiles );
    my ( $newlyCopiedFile, $copiedFile );

    $newlyCopiedFiles = shift;

    if (%$newlyCopiedFiles) {
       
	# get original list of copied files
	if (-e $logFile) {
	    open(READCOPIEDFILES, "<$logFile") || die "Cannot read $logFile\n";

	    while (<READCOPIEDFILES>) {
		($newFileName, $copiedFile) = split(/\t/, $_);
		chomp($copiedFile);

		# ignore copied files for which the copy has been deleted
		if (-e $newFileName) {
		    $copiedFiles{$newFileName} = $copiedFile;
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
	
	foreach $fileName (sort ( keys %copiedFiles )) {
	    printf SAVECOPIEDFILES "$fileName\t$copiedFiles{$fileName}\n";
#xxxxxxxxxxxx
	}

	close(SAVECOPIEDFILES);
    }
}

################################################################################
# reduce size of the large email header style

sub clean_large_email_header($) {

    my $data = shift;

    $data =~ s/^From [^@]+\@[A-z0-9_-]+(\.[A-z0-9_-]+)+[^\n]+\n//;
    $data =~ s/Message-ID: [^\n]+\n//i;
    $data =~ s/User-Agent: [^\n]+\n//;
    $data =~ s/References: [^\n]+\n//;
    $data =~ s/DomainKey-Signature:[^\n]+\n(  [a-z]=[^\n]+\n)*//g;
    $data =~ s/X-[A-Z][A-Z]+(-[A-Z]+)?: [^\n]+\n(\t[^\n]+\n)*//gi;
    $data =~ s/In-Reply-To: [^\n]+\n//g;
    $data =~ s/MIME-Version: [^\n]+\n//gi;
    $data =~ s/Content-[A-Za-z][^:]+: [^\n]+\n(\t[^\n]+\n)*//g;
    $data =~ s/Received: \(?[^\n]+\n([ \t]+[^\n]+\n)+//g;

    return($data);
}

################################################################################
# remove strange jitterbug inserted patterns from copied files

sub clean_copied_files(\%) {

    my ( $data, $copiedFile, $line, $stillInEmailHeader );

    my $files = shift;

    print "\n";

    foreach $copiedFile (keys %$files) {

	# if file looks like it's not an attachment, clean it
	if ($$files{$copiedFile} !~ /\.att\.?\d+\./) {
   
	    open(READFILE, "<$copiedFile") || die "Cannot open file to check for bad characters: $copiedFile\n";
	
	    $stillInEmailHeader = 1;
	    $data = "";
	
	    while ($line = <READFILE>) {
		if ($stillInEmailHeader) {
		    if($line  =~ /^\s*$/) {
			$stillInEmailHeader = 0;
		    }
		    else {
			if ($line =~ /^((From)|(To)|(Subject)|(Date)|(CC)):/){
			    $data .= $line;
			} 
		    }
		}
		else {
		    $data .= $line;
		} 
	    }
	    close(READFILE);
	
	    # emails from embl have oversized email header info - shrink it!
	    #$data = clean_large_email_header($data);
	    $data = substitute_jitterbug_chars($data);
	    
	    open(SAVECLEANFILE, ">$copiedFile") || die "Cannot open file for cleaning: $copiedFile\n";
	    print SAVECLEANFILE $data;
	    close(SAVECLEANFILE);

	    if ($verbose) {
		print "$copiedFile cleaned!\n";
	    }
	}
    }
}

################################################################################
#

sub print_if_good_email_header_line($$$) {

    my $line = shift;
    my $prev_line = shift; # for dealing with wrapped lines
    my $SAVEFILE = shift;

    if ($line =~ /^(Date|From|To|Subject|Reply-to|Cc): /) {
	print $SAVEFILE $line;
    }
    elsif (($prev_line =~ /^(To|Subject|Cc): /) && ($line =~ /^\s\s\s+\S/)) {
	# wrapped line
	print $SAVEFILE $line;
    }
}

################################################################################
#

sub save_replies_and_followups(\@$$\@$$) {

    my (@file_lines, $filename, @numbered_files, $got_email, $counter);
    my ($displayOrder, $line, $prev_line, $print_all_lines_downwards);

    my $emailFiles    = shift;
    my $SAVEFILE      = shift;
    my $savefile_name = shift;
    my $displayOrderList = shift;
    my $separator1    = shift;
    my $separator2    = shift;

    $counter = 0;

    foreach $displayOrder (@$displayOrderList) {

	if ($counter) {                                 # <- skip first file (named $jbId)
	    if (open(GRABEMAIL, "<$$emailFiles[$displayOrder]")) {
		
		if ($$emailFiles[$displayOrder] =~ /.+\/([^\/]+)$/) {
		    $filename = $1;
		}
		$verbose && print "saving $$emailFiles[$displayOrder] into $savefile_name\n";
		print $SAVEFILE $separator1."# $filename\n".$separator2;

		$prev_line = "";
		$print_all_lines_downwards = 0;

		while ($line = <GRABEMAIL>) {

		    if ($print_all_lines_downwards || ($line =~ /^\s*$/)) {
			# indicates gap between large email header (which we don't want)
			# and email content (which we do want)
			print $SAVEFILE $line;
			$print_all_lines_downwards = 1;
		    }
		    else {
			print_if_good_email_header_line($line, $prev_line, $SAVEFILE);
			$prev_line = $line;
		    }
		}
		close(GRABEMAIL);
		
	    }
	}
	$counter++;
    }
}

################################################################################
#

sub save_file_called_threadid(\@$$$$$) {

    my ($file, @file_lines, $line, $prev_line, $print_all_lines_downwards);

    my $emailFiles = shift;
    my $jbId = shift;
    my $SAVEFILE = shift;
    my $savefile_name = shift;
    my $separator1 = shift;
    my $separator2 = shift;

    foreach $file ( @$emailFiles) {

	if (($file =~ /\/$jbId$/) && (-e $file)) {

	    if (open(GRABEMAIL, "<$file")) {
		$verbose && print "saving $file into $savefile_name\n";
		print $SAVEFILE $separator1."# $jbId\n".$separator2;

		$prev_line = "";
		$print_all_lines_downwards = 0;

		while ($line = <GRABEMAIL>) {

		    if ($print_all_lines_downwards || ($line =~ /^\s*$/)) {
			# indicates gap between large email header (which we don't want)
			# and email content (which we do want)
			print $SAVEFILE $line;
			$print_all_lines_downwards = 1;
		    }
		    else {
			print_if_good_email_header_line($line, $prev_line, $SAVEFILE);
			$prev_line = $line;
		    }
		}
		close(GRABEMAIL);
	    }

	    last;
	}
    }
}

################################################################################
#

sub save_notes_file($$$) {

    my (@file_lines);

    my $notes_file = shift;
    my $SAVEFILE = shift;
    my $savefile_name = shift;

    if (-e $notes_file) {
	if (open(GRABCOMMENT, "<$notes_file")) {
	    $verbose && print "saving $notes_file into $savefile_name\n";
	    @file_lines = <GRABCOMMENT>;
	    close(GRABCOMMENT);
	    print $SAVEFILE @file_lines;
	}
	else {
	    print "Could not add $notes_file to the combined email thread\n";
	}
    }
}

################################################################################
#

sub combine_email_threads($$\@\@) {

    my ( $savefile_name, $notes_file, $separator1, $separator2, $jbDir );

    my $jbId = shift;
    my $jbDirType = shift;
    my $emailFiles = shift;
    my $displayOrder = shift;

    $separator1 = "\n\n#----------------------------------------------------------------------\n";
    $separator2 = "#----------------------------------------------------------------------\n\n";

    if ($jbDirType eq "UPD") {
	$savefile_name = "$jbId.upd_corresp";
    }
    else {
	$savefile_name = "$jbId.sub_corresp";
    }

    if ($$emailFiles[0] =~ /(.+\/)[^\/]+$/) {
	$jbDir = $1;
    }

    print "Saving email thread to $savefile_name\n";

    open(\*SAVEFILE, ">$savefile_name") || print "Cannot open $savefile_name for writing\n";

    # save notes files to new file
    $notes_file = $jbDir."$jbId.notes";
    save_notes_file($notes_file, \*SAVEFILE, $savefile_name);

    # save file called the jb thread id to new file
    save_file_called_threadid(@$emailFiles, $jbId, \*SAVEFILE, $savefile_name, $separator1, $separator2);

    # save reply and followup files to the new file
    save_replies_and_followups(@$emailFiles, \*SAVEFILE, $savefile_name, @$displayOrder, $separator1, $separator2);

    close(SAVEFILE);
}

################################################################################
# make sure all the right arguments have been received

sub get_args(\@) {

    my ( $jbId, $jbDirType, $arg, $saveAllThreads );

    my $args = shift;

    $verbose = 0;
    $saveAllThreads = 0;

    # check the arguments for values
    foreach $arg ( @$args ) {

	if ( $arg =~ /^\-h/ ) { # display help message
	    die $usage;
	}
        elsif ( $arg =~ /^\-v/ ) {    # verbose mode
            $verbose = 1;
        }
	elsif ($arg =~ /^\-all/) {
	    $saveAllThreads = 1;
	}
        elsif ( $arg =~ /^\-s=(.+)$/ ) {    # sub or upd
	    $jbDirType = check_jitterbug_type( $1 );
        }
        elsif ( $arg =~ /^(\-j=)?(\d+)$/ ) {   # jitterbug id
	    $jbId = $2;
        }
        elsif ( $arg =~ /^(\-j=)?(.+)$/ ) {    # url/anything else
	    ($jbId, $jbDirType) = check_jitterbug_url( $2 );
        }
        elsif ( $arg =~ /^\-j=?$/ ) {   # jitterbug option is empty (used in alias)
	    # jbId remains empty
        }
        else {
            die "Unrecognised argument format \"$arg\"\n$usage";
        }
    }

    if (!$jbId) {
	( $jbId, $jbDirType ) = request_jitterbug_id($jbDirType);
    }

    return ( $jbId, $jbDirType, $saveAllThreads );
}

################################################################################
# main function

sub main(\@) {

    my ( $jbId, $jbDirType, $emailFiles, $displayOrder, $copiedFiles );
    my ( $saveAllThreads, $jbFolder );

    my $args = shift;

    # check arguments are intact
    ( $jbId, $jbDirType, $saveAllThreads ) = get_args(@$args);

    # find the directory containing the jitterbug ID
    ( $emailFiles, $jbDirType, $jbFolder ) = get_email_files( $jbId, $jbDirType, $saveAllThreads );

    # ask user which files to copy and copy them
    $displayOrder = display_email_info( @$emailFiles, $saveAllThreads);

    if ( $saveAllThreads ) {
	combine_email_threads($jbId, $jbDirType, @$emailFiles, @$displayOrder);
    }
    else {
	$copiedFiles = copy_files( @$emailFiles, @$displayOrder, $jbDirType, $jbFolder );

	write_log(%$copiedFiles);
	clean_copied_files(%$copiedFiles);
    }
}

################################################################################
# Run the script

main( @ARGV );
