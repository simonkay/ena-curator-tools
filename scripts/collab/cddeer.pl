#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  cddeer.pl (Collaborators Daily Data Exchange Error Roundup)
#
#  MODULE DESCRIPTION:
#
#  Reviews the daily collaborator exchange files and deleting the oldest ones.
#  Also groups outstanding errors according to the error message and 
#  provides a report to STDIN and also as a .log file in the appropriate
#  data directory
#
#  MODIFICATION HISTORY:
#
#  28-MAY-2003 Nadeem Faruque      Created.
#  20-JUL-2004 Nadeem Faruque      Rewrote to suite antiload exchange procedure
#
#===============================================================================

use strict;
use File::Find;
use SeqDBUtils2;
use sendEmails;
use Data::Dumper;

# GLOBAL

my $report = "";
my $recommendations = "";
my $minDaysBeforeDeletion = 6;
my $testing = 0;
my $exit_status = 0; 
my $destinationDir = "/ebi/production/seqdb/embl/data/collab_exchange/daily_collab_control";
my $usage = "\n PURPOSE:  Reviews AntiLoad errors\n"
    . "          in /ebi/production/seqdb/embl/data/collab_exchange/...\n"
    . "          Errors are grouped together into _GroupErrors_ files\n"
    . "          in $destinationDir\n"
    . "and the separate errors are deleted\n"
    . " USAGE:   $0 [-h] [-t(est)]\n"
    . "   -h     shows this help text\n"
    . "   -t     test mode - doesn't delete files from putff\n";

#---------------------------------------------
sub commify($) {
    local $_  = shift;
    1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $_;
}

#---------------------------------------------
# mediates the creation/destruction of the lock file
sub lockFile {

    my ($existingLock);
    my $action   = shift;
    my $lockFile = shift;

    if ( $action eq "make" ) {
        if ( -e "$lockFile" ) {
            open LOCK, "<$lockFile"
		or die "$lockFile exists already but cannot read!\n";
            $existingLock = do { local $/; <LOCK> };
            chomp($existingLock);
            die "$lockFile exists:-\n \"$existingLock\"\n" . "is someone else running $0?\n".
		"if not, delete the lock and rerun.\n";
        }
        else {
            open LOCK, ">$lockFile"
              or die "Can't create $lockFile file: $!";
            print LOCK "Update started " . timeDayDate("timedaydate") . " by user $ENV{'USER'}\n";
            close LOCK;
        }
    }
    else {
        unlink("$lockFile");
    }
    return 1;
}
#---------------------------------------------
sub findArchiveFiles(\@\@$) {

    my ($insdcDir, $loadDir, $fileName);
    my $loadDirs = shift;
    my $archiveFiles = shift;
    my $fileGroup = shift;

    foreach $insdcDir (@$loadDirs) {

	$loadDir = $insdcDir.$fileGroup."/archive";

	if (-e $loadDir) {
	    chdir ($loadDir) or die "Cannot access $loadDir: $!";
	    opendir(DH, $loadDir) or die "$loadDir Unopenable: $!";
	
	    foreach (reverse(sort map {sprintf("%010d%s", (stat($_))[9], $_)} readdir(DH))) {
		$fileName = substr($_,10);
		if (-T $fileName) {
		    push (@$archiveFiles, { 'FILE' => $fileName,
					    'DIR'  => "$loadDir",
					    'AGE'  => int ((time () - sprintf("%010d", (stat($fileName))[9]))/86400)
,
					    'FINISHED' => 1 
					  })
		    }
	    }
	    closedir(DH); 
	}
    }

    if (@$archiveFiles) {
	$report .= commify(scalar(@$archiveFiles))." archive files found\n";
    }
    else {
	$report .= "0 archive files found\n";
    }
}

#---------------------------------------------
sub findErrorFiles(\@\@$) {

    my ( $insdcDir, $loadDir, $fileName );
    my $loadDirs = shift;
    my $errorFiles = shift;
    my $fileGroup = shift;

    foreach $insdcDir (@$loadDirs) {

	$loadDir = $insdcDir.$fileGroup."/error";

	if (-e $loadDir) {
	    chdir ($loadDir) or die "Cannot access $loadDir: $!";
	    opendir(DH, $loadDir) or die "$loadDir Unopenable: $!";
	    
	    foreach (reverse(sort map {sprintf("%010d%s", (stat($_))[9], $_)} readdir(DH))){
		$fileName = substr($_,10);
		if (-T $fileName and ($fileName =~ /_[0-9]+$/)) {
		    push (@$errorFiles, { 'FILE'   => $fileName,
					  'DIR'    => "$loadDir",
					  'STATUS' => "ERROR"
					})
		    }
	    }
	    closedir(DH); 
 
	    $loadDir .= "/fatal";

	    if (-e $loadDir) {
		chdir ($loadDir) or die "Cannot access $loadDir: $!";
		opendir(FH, $loadDir) or die "$loadDir Unopenable: $!";
		
		foreach (reverse(sort map {sprintf("%010d%s", (stat($_))[9], $_)} readdir(FH))) {
		    $fileName = substr($_,10);
		    if (-T $fileName){
			print "** Fatal error for $loadDir/$fileName - please deal with manually\n";
		    }
		    closedir(FH); 
		}
	    }
	}
    }

    if (@$errorFiles) {
	$report .= commify(scalar(@$errorFiles))." error files found\n\n";
    }
    else {
	$report .= "0 error files found\n\n";
    }
}

#---------------------------------------------
sub findLoadFileForErrors(\@\@$){

    my ( $error, $errorRoot, $archive );
    my $archiveFiles = shift;
    my $errorFiles   = shift;
    my $fileGroup = shift;

    foreach $error (@$errorFiles) {

	$errorRoot = $error->{'FILE'};

	if ($errorRoot =~ s/_[0-9]+$//) {
	    foreach $archive (@$archiveFiles){
		if ($archive->{'FILE'} eq $errorRoot){
		    $error->{'ARCHIVE'} = $archive->{'DIR'}."/".$archive->{'FILE'};
		    $archive->{'FINISHED'} = 0;
		}
	    }
	}
    }
}

#---------------------------------------------
sub findBusyErrors(\@$) {

    my ( @remainingErrors, $file, $i );
    my $errorFiles = shift;
    my $fileGroup = shift;

    $i=0;
    foreach $file (@$errorFiles) {
	if (($file->{'STATUS'} ne "FATAL") and (!defined($file->{'ARCHIVE'}))) {

	    if (!$i) {
		$report .= "Checking for archived sources of $fileGroup error files:\n";
	    }

	    $report .= "$file->{'DIR'}/$file->{'FILE'} appears busy (ie no archive file)\n";
	    $i++;
	}
	else {
	    push (@remainingErrors, $file);
	}
    }
    
    @$errorFiles = @remainingErrors;
}

#---------------------------------------------
sub deleteCompletedArchives(\@$){

    my ( $archive, $cmd, $cmdExt, $i );
    my $archiveFiles = shift;
    my $fileGroup = shift;

    $i=0;
    foreach $archive (@$archiveFiles) {

	if (($archive->{'FINISHED'} == 1) and ($archive->{'AGE'} >= $minDaysBeforeDeletion)) {

	    # print once
	    if (!$i) {
		$recommendations .="\n# Deleting completed $fileGroup load files >= $minDaysBeforeDeletion days old\n";
		$i++;
	    }

	    $recommendations .= "rm $archive->{'DIR'}/$archive->{'FILE'}\n";
	    $testing or unlink "$archive->{'DIR'}/$archive->{'FILE'}";
	}
    }
}

#---------------------------------------------
sub processFatalErrors(\@$){

    my ( $file, @remainingErrors, $i );
    my $errorFiles = shift;
    my $fileGroup = shift;

    if (@$errorFiles) {
	$recommendations .="\n# Fatal error moves\n";
    }

    $i=0;
    foreach $file (@$errorFiles) {
	if ($file->{'STATUS'} eq "FATAL") {

	    if (!$i) {
		$report .= "Checking for $fileGroup fatal errors:\n";
	    }

	    # This gives a problem for fatal errors (currently commented out)
	    $recommendations .= "mv $file->{'DIR'}/$file->{'FILE'} $destinationDir\n"
		.  "mv $file->{'ARCHIVE'} $destinationDir\n";
	    $testing or rename ("$file->{'DIR'}/$file->{'FILE'}", "$destinationDir/$file->{'FILE'}");
	    $report .= "Fatal error of $file->{'DIR'}/$file->{'FILE'}\n\n";
	    $i++;
	}
	else {
	    push (@remainingErrors, $file);
	}
    }
	
    @$errorFiles = @remainingErrors;
}

#---------------------------------------------
sub findErrorTypes(\%\%){

    my ( $errorFile, $file, $errorLine, $acNumber, $latestLine );
    my ( $fileGroup );
    my $errorFiles = shift;
    my $errorTypes = shift;

    foreach $fileGroup (keys %$errorFiles) {
	foreach $errorFile (@{ $$errorFiles{$fileGroup} }) {

	    $file = $errorFile->{'DIR'}."/".$errorFile->{'FILE'};
	    open IN, "<$file" or die "$file exists but I cannot read it\n";
	
	    $errorLine = "";
	    $acNumber  = "";
	
	    # Read error line(s)
	    READERROR:while(<IN>) {
		$latestLine = $_;
		if ($latestLine =~ /^LOCUS   /){
		    last READERROR;
		}
		$errorLine .= $latestLine;
	    }
	    READAC:while(<IN>) {
		if (/^VERSION     ([\S]+)/){
		    $acNumber = $1;
		    last READAC;
		}
	    }
	    close IN;
	    chomp($errorLine);

	    #Remove any 'ERROR putff: filehandler error ' line (as long as there is some error message remaining)
	    $errorLine =~ s/\A(.+)\nERROR putff: filehandler error$(.*)/$1$2/m;
    
            #Make protein_id version errors generic
            $errorLine =~ s/^(ERROR sequence for protein_id) \S+ (.*)/$1 $2/;
	
            #Make older than errors generic # would be nicer to delete them here and now
            $errorLine =~ s/^ERROR date in file \S+ is older than date in database \S+/ERROR is older than the one in the database/;

            #Make protein_id duplication errors generic
            $errorLine =~ s/^(ERROR a CDS feature cannot have more than one protein_id qualifier)(.*)/$1/;

            #Make EC_number errors generic
            $errorLine =~ s/^(ERROR \/EC_number: non existent EC number:).*/ERROR \/EC_number: illegal or non existent/;
            $errorLine =~ s/^(ERROR \/EC_number: illegal EC number:).*/ERROR \/EC_number: illegal or non existent/;

            #Make mobile element errors generic - DDBJ introduced it a month early in November 2006
            $errorLine =~ s/^ERROR illegal feature qualifier mobile_element=.*/Premature use of mobile element/;

            #Make duplicate citations generic
   	    $errorLine =~ s/^(ERROR duplicated citations found) for entry.*/$1/;

	    #Make double quote errors generic
	    $errorLine =~ s/^(ERROR missing final double quotes).*/$1/s;

	    #Make CON->Normal errors generic
            $errorLine =~ s/ERROR Cannot update type of entry [A-Z0-9]+ from CON to other/ERROR Cannot update type of entry from CON to other/s;

            #Clean-up uncaught Oracle errors
	    if ($errorLine =~ /^ORACLE ERROR \(/m) {
	        $errorLine =~ s/\s+/ /gm;
	        $errorLine =~ s/^.*(ORACLE ERROR .*$)/ERROR $1/;
	    }

	    #Make other errors generic
	    $errorLine =~ s/(ERROR qualifier constraint violated on entry )(\w+)/$1/;
	    push(@{ $$errorTypes{$fileGroup}{$errorLine}->{'FILES'} }, $file);
 	    push(@{ $$errorTypes{$fileGroup}{$errorLine}->{'ACS'} },   $acNumber);
        }
    }

    $report .= "===========================\n"
	    .  "Grouping all errors by type\n"
	    .  "===========================\n"
	    .  commify(scalar(keys %$errorTypes))." error types found\n\n";
}
#---------------------------------------------
sub getFileHandleToWriteData($$) {

    my ($OUT, $outfile);

    my $groupedErrorRoot = shift; 
    my $groupedErrorNumber = shift;

    while ( -e $groupedErrorRoot.sprintf("%05d", $groupedErrorNumber) ) {
	$groupedErrorNumber++;
    }
    
    $outfile = $groupedErrorRoot.sprintf("%05d", $groupedErrorNumber);
    open($OUT, ">$outfile") or die "Cannot make the grouped file\n$outfile\n: $!";

    return ($OUT, $outfile, $groupedErrorNumber);
}
#---------------------------------------------
sub printResultsFile($$\@$\@) {

    my ($file, $entryStarted, $latestLine, $OUT_FH, $outfile);

    my $groupedErrorRoot = shift; 
    my $groupedErrorNumber = shift;
    my $file_list = shift;
    my $error_lines  = shift;
    my $acc_list = shift;

    ($OUT_FH, $outfile, $groupedErrorNumber)  = getFileHandleToWriteData($groupedErrorRoot, $groupedErrorNumber);

    print $OUT_FH commify(scalar(@$file_list))." x ".$error_lines."\n".join("\n", sort @$acc_list)."\n";

    $report .= "\n".commify(scalar(@$file_list))." x $error_lines\n"."Saving to -> $outfile\n";


    foreach $file (@$file_list) {
	open(IN, "<$file") or die "$file exists but I cannot read it\n";
	$entryStarted = 0;
	
	while (<IN>) {
	    $latestLine = $_;
	    if ($latestLine =~ /^LOCUS   /){
		$entryStarted = 1;
	    }
	    if ($entryStarted){
		print $OUT_FH $_;
	    }
	}
	close(IN);
	
	$recommendations .= "rm $file\n";
	$testing or unlink $file;
    }

    $report .= "\n";
    close($OUT_FH);
    system("chmod 664 $outfile");

    return($outfile);
}
#---------------------------------------------
sub resubmitSomeErrorLines($$$) {

    my $errorLine = shift;
    my $putff = shift;
    my $outfile = shift;

    if ($errorLine =~ /NCBI HTGS_PHASE1 entry are required/){
	$report .= "Resubmitted with the line\n"
	    .  "  putff /\@enapro -ncbi -ignore_errors $outfile\n";
	system("$putff -ignore_errors $outfile");
	$recommendations .= "# Deleting 'HTGS_PHASE1' GroupedError file\n"
	    .  "rm $outfile\n";
	$testing or unlink $outfile;
    }
    if ($errorLine =~ /ERROR sequence for protein_id has changed/) {
	$report .= "Resubmitted with the line\n"
	    .  "  putff /\@enapro -ncbi -ignore_version_mismatch $outfile\n";
	system("$putff -ignore_version_mismatch $outfile");
	$recommendations .= "# Deleting 'protein_id has changed' GroupedError file\n"
	    .  "rm $outfile\n";
	$testing or unlink $outfile;
    }
    if ($errorLine =~ /ERROR \/EC_number: illegal or non existent/) {
	system("/ebi/production/seqdb/embl/tools/curators/scripts/collab/update_ec_numbers.pl $outfile -ncbi");
	system("chmod 664 $outfile.upd");
	
	$report .= "Made corrected version for your manual loading\n"
	    .  "   putff /\@enapro -ncbi $outfile.upd\n";
	$recommendations .= "# Deleting 'illegal EC number' GroupedError file after .upd made\n"
	    .  "rm $outfile\n";
	$testing or unlink $outfile;
    }	
    if ($errorLine =~ /CDS feature cannot have more than one protein_id/s) {	    
	$report .= "Solution:-\n"
	    .  "/ebi/production/seqdb/embl/tools/curators/scripts/collab/clean_pids.pl /\@enapro -ff $outfile\n"
	    .  "then\n"
	    .  "putff /\@enapro -ncbi $outfile.uniq\n";
    }
    if ($errorLine =~ /is older than the one in the database/) {
	$report .= "Solution:-\n"
	    .  "rm $outfile\n";	
    }
}
#---------------------------------------------
sub groupWGSerrorsIntoFiles(\%$$) {

    my ($groupedErrorNumber, $outfile, $errorLine, $entryStarted, $latestLine, $acc);
    my (%wgs_projects, $file, @acc_lines, $acc_line, @individual_error_lines, $line);
    my ($wgs_project, $all_project_errors, $OUT, $project_abbrev);

    my $errorTypes = shift;
    my $groupedErrorRoot = shift;
    my $putff = shift;

    $groupedErrorNumber = 1;
	    
    # NB should sort these according to ACS before proceeding
    foreach $errorLine (keys %{ $$errorTypes{'wgs'} }) {

	@individual_error_lines = ();
	@individual_error_lines = split(/\n/, $errorLine);

	foreach $file (@{ $$errorTypes{'wgs'}{$errorLine}{FILES} }) {

	    @acc_lines = `grep ^LOCUS $file`;

	    foreach $acc_line (@acc_lines) {

		if ($acc_line =~ /^LOCUS\s+((\S{6})\S+)/) {

		    $project_abbrev = $2;

		    push(@{ $wgs_projects{$project_abbrev}{ACS}   }, $1);
		    push(@{ $wgs_projects{$project_abbrev}{FILES} }, $file);

                    # get unique list of errors
		    foreach $line (@individual_error_lines) {
			$wgs_projects{$project_abbrev}{ERROR_MSGS}{$line} = 1;
		    }
		}
	    }
	}
    }

    foreach $wgs_project (keys %wgs_projects) {

        # concatenate all errors from this wgs project into a single string
	foreach $errorLine (keys %{ $wgs_projects{$wgs_project}{ERROR_MSGS} }) {
	    $all_project_errors .= $errorLine."\n";
	}

	$outfile = printResultsFile($groupedErrorRoot,
				    $groupedErrorNumber,
				    @{ $wgs_projects{$wgs_project}{'FILES'} }, 
				    $all_project_errors, 
				    @{ $wgs_projects{$wgs_project}{'ACS'} }
				    );
	
	resubmitSomeErrorLines($all_project_errors, $putff, $outfile); 
    }
}
	
#---------------------------------------------
sub groupErrorsIntoFiles(\%){

    my ( $groupedErrorRoot, $groupedErrorNumber, $outfile, $errorLine );
    my ( $entryStarted, $latestLine, $putff, $file, $fileGroup, $OUT );
    my $errorTypes = shift;

    $putff = "/ebi/production/seqdb/embl/tools/bin/putff /\@enapro -ncbi";

    foreach $fileGroup (keys %$errorTypes) {

	$groupedErrorRoot   = "$destinationDir/GroupedError_".timeDayDate("yyyy-mm-dd").".$fileGroup.";

	$recommendations .="\n# Deleting error files that have been absorbed into GroupedError files\n";
	    
	if (scalar(keys (%{ $$errorTypes{$fileGroup} }))) {
	    if ($fileGroup ne 'wgs') {
		$report .="==============================\n"
		    . "Grouping $fileGroup errors by type\n"
		    . "==============================\n";
	    }
	    else {
		$report .="==============================\n"
		    . "Grouping wgs errors by project\n"
		    . "==============================\n";
	    }
	}

	
	if ($fileGroup eq 'wgs') {
            # rearrange sats first to be grouped by wgs project rather than by error
	    groupWGSerrorsIntoFiles(%$errorTypes, $groupedErrorRoot, $putff);
	}
	else {
	    $groupedErrorNumber = 1;

	    # NB should sort these according to ACS before proceeding
	    foreach $errorLine (keys %{ $$errorTypes{$fileGroup} }) {

		$outfile = printResultsFile($groupedErrorRoot,
					    $groupedErrorNumber,
					    @{ $$errorTypes{$fileGroup}{$errorLine}{'FILES'} }, 
					    $errorLine, 
					    @{ $$errorTypes{$fileGroup}{$errorLine}{'ACS'} }
					    );

		resubmitSomeErrorLines($errorLine, $putff, $outfile); 
	    } 
	}
    }
}
#---------------------------------------------
sub addLockFilesToReport {

    my ($file);

    $file = $File::Find::name;
    # age to report on LOCK files set to at least 1 day old (1.0)
    if ($file =~ /.*LOCK.*$/) {

	if (-M $file > 1.0) {
	    $report .= "Lock file found >1 day old: $file\n";
	}
    }
}
#---------------------------------------------
sub reportOnOldLockFiles(\@) {

    my $loadDirs = shift;

    $report .= "\n";
    foreach (@$loadDirs) {
	find(\&addLockFilesToReport, $_);
    }
}
#---------------------------------------------
sub get_args(\@) {

    my ( $arg );
    my $args = shift;

    foreach $arg (@$args) {
	if ( $arg =~ /^\-t(est)?$/ ) {
	    $testing = 1;
        }
	else {
	    die "Do not understand the term $arg\n" . $usage;
	}
    }
}

#---------------------------------------------
sub printReport() {

    my ( $reportRecommendationsFile, $longHashStr, $shortHashStr );

    $longHashStr = "##############################################\n";
    $shortHashStr = "\n##############################################\n\n";

    print STDOUT $longHashStr."# Exchange Error Report ".timeDayDate("timedaydate")
	. $shortHashStr.$report."\n\n";
#	. $ftpFileReport . "\n\n";

    if ($recommendations ne "") {
	print STDOUT $longHashStr . "# the following deletions were done"
	    . $shortHashStr
	    . $recommendations."\n\n";
    }
}
#---------------------------------------------
sub cddeer(\@) {

    my ( $archiveFiles, $errorFiles,  %errorTypes, @loadDirs, $reportFile );
    my ( $errorTypes, @fileGroups, $fileGroup, $lockFile, %errorFiles );
    my ( %archiveFiles, %remainingErrors, %moreRemainingErrors );
    my $args = shift;

    get_args(@$args);

    $lockFile  = $destinationDir . "/cddeer_LOCK";
    if ($testing) {
	$lockFile .= "_testing";
    }
    
    lockFile("make", $lockFile);

    @loadDirs = ("/ebi/production/seqdb/embl/data/collab_exchange/ncbi.daily/",
		 "/ebi/production/seqdb/embl/data/collab_exchange/ddbj.daily/");

    @fileGroups = ("ann", "con", "mga", "normal", "tpa", "wgs");


    # go through one file group at a time so report groups them together
    foreach $fileGroup (@fileGroups) {

	$report .= "======================\n"
	        .  "Checking $fileGroup files\n" 
	        .  "======================\n";

	findArchiveFiles(@loadDirs, @{ $archiveFiles{$fileGroup} }, $fileGroup);

	findErrorFiles(@loadDirs, @{ $errorFiles{$fileGroup} }, $fileGroup);
	
	# link error files with archived source files of origin
	findLoadFileForErrors(@{ $archiveFiles{$fileGroup} }, @{ $errorFiles{$fileGroup} }, $fileGroup);
	    
	# excludes files from list if no archived file
	findBusyErrors(@{ $errorFiles{$fileGroup} }, $fileGroup);
	    
	# excludes files from list if no archived file
	deleteCompletedArchives(@{ $archiveFiles{$fileGroup} }, $fileGroup);
	    
	# placeholder for treatment of fatals
	processFatalErrors(@{ $errorFiles{$fileGroup} }, $fileGroup);
    }

    findErrorTypes(%errorFiles, %errorTypes);
	
    groupErrorsIntoFiles(%errorTypes);  

    reportOnOldLockFiles(@loadDirs);

#    getFtpSummary(@loadDirs, @fileGroups);

    printReport();

    lockFile("remove", $lockFile);
   
    system("java -cp /ebi/production/seqdb/embl/tools/lib/ena-pipe-DEV.jar  uk.ac.ebi.ena.ena_pipe.collab.CollabReport");
}

#------------------------------------

cddeer(@ARGV);

exit $exit_status;
