#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  SCRIPT DESCRIPTION:
#  Uses sequences from a fasta file to make EMBL sub files
#  based on a skeleton file
#  
#  MODIFICATION
#   
#  09-Jul-2002 Nadeem Faruque   Created, only works with a single variable
#  26-Jul-2002 Nadeem Faruque   v1.5 works with multiple variables
#  03-OCT-2002 Nadeem Faruque   v1.6 made the reporting of unresolved
#                               tokens more friendly
#
#  To Do:-
#   Handle lines expanding to > 80 characters
#    does someone have a seperate line cleaner that can be used?
#   Better contingencies for empty variable fields - 
#    at the moment we just need empty ;'s in the fasta file
#
#==============================================================
select(STDOUT); $| = 1; # make unbuffered
select(STDERR); $| = 1; # make unbuffered
#################################
# SUBROUTINES
#################################

#################################
# commify # 
# adds commas to delimit thousands in numbers
sub commify ($){
    local $_ = shift;
    1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $_;
}

#################################
# log_usage # 
# log usage so that I can suggest using WebinBulk - nb doesn't try too hard to avoid clashes of two people using it at once. 
sub log_usage($){
    my $entryTotal = shift;
    my $logfile="fasta2subs.log";
    if (open LOGUSAGE, ">>$logfile"){
	print LOGUSAGE $ENV{'USER'}."\t".$entryTotal."\t".(scalar localtime)."\n";
	close LOGUSAGE;
    }
}

#################################
# MAIN BODY
#################################

# The FASTA file is expected to end in .fasta, and the skeleton ends in .skel,
$fastaFileExtension=".fasta";
$skeletonFileExtension=".skel";

# Location of the readseq jar file
$readSeqJarFile="/ebi/production/seqdb/embl/tools/bin/readseq.jar";

# Single variable and seq length tokens
$myReplaceToken="---";
$mySeqLengthToken=$myReplaceToken."SL".$myReplaceToken;

my $usage = "\n PURPOSE: Uses sequences from a fasta file to make EMBL sub files\n".
            "          based on a skeleton:\n\n".
            " USAGE:   $0".
	    "          [-f=<file>] [-t=<file>] [-h]\n\n".
            "   -f=<file>       where <file> contains the sequences in fasta format\n".
            "                   otherwise the last $fastaFileExtension file found is used.\n\n".
            "   -t=<file>       where <file> contains the skeleton file\n".
            "                   (if omitted any $skeletonFileExtension file found that matches\n".
            "                   the fasta file name is used)\n".
            "                   ie an EMBL file up to but not including the SQ line where\n".
            "                    $mySeqLengthToken marks where the sequence length is to be inserted\n".
            "                   and \n".
            "                    ".$myReplaceToken."n".$myReplaceToken." marks where the fasta file sequence name is \n".
            "                    to be inserted where n is the variable number\n".
            "                    starting from 1\n".
            "                    NB multiple variables are seperated on the ID line of the\n".
            "                     fasta file by semi-colons (ie ;)\n\n".
            "   -v              verbose\n\n".
            "   -h              shows this help text\n\n";
#( @ARGV >= 1 && @ARGV <= 3 ) || die $usage;
if (@ARGV >= 1){
    ( $ARGV[0] !~ /^-h/i ) || die $usage;}

$fastaInFileName="";
$skeletonFileName="";
$verboseMode=0;
if (@ARGV > 0){
    for ( my $i = 0; $i < @ARGV; ++$i ){
	if ( $ARGV[$i] =~ /^\-f=(.+)$/ ){
	    $fastaInFileName = $1 ;
	    if ( ( ! ( -f $fastaInFileName ) || ! ( -r $fastaInFileName ) ) ){
		print "ERROR: $fastaInFileName is not readable, \n".
		    "will use the last $fastaFileExtension file found in this directory\n";
		$fastaInFileName ="";
	    }
	}
	elsif ( $ARGV[$i] =~ /^\-t=(.+)$/ ){
	    $skeletonFileName = $1;
	  if ( ( ! ( -f $skeletonFileName ) || ! ( -r $skeletonFileName ) ) ){
	      print "ERROR: $skeletonFileName is not readable, \n".
		  "will look for one that matches the fasta file";
	      $skeletonFileName ="";
	  }
	}
	elsif ( $ARGV[$i] =~ /^\-v/ ){
	    $verboseMode = 1;}
	else{
	    die ( $usage );}
    }
}

# In none provided in the args, look for a fasta file in the current directory
# NB only utilises the last one it finds
if(!$fastaInFileName){
    if(!open(PIPE,"/bin/ls -l *$fastaFileExtension |")){
	die "Error: failed to find .$fastaFileExtension files in this directory\n";
	}
    print "$fastaFileExtension files found:-\n";

# Take the name of any .fasta files
    while(<PIPE>){
	@in=split;
	if($in[8] ) {
		$fastaInFileName=$in[8];
		print "\t$in[8]\n";
	}
    }

# If there's no fasta files, what is there?
    if (!$fastaInFileName){
	open(PIPE,"/bin/ls -l |") || die "Error: Cannot list any files\n";
	print "NONE\nFiles found:-\n";
	while(<PIPE>){
		print;
	    }
	die "Come back when you have a $fastaFileExtension file\n";
    }	
}
	
$submitterName=$fastaInFileName;
$submitterName=~s/\..*//g;
print "I presume the submittor is $submitterName\n";
$emblInFileName=$submitterName.".em";

# If there's no given skeletonFileName but there is a 
# .skel file named similarly to the fasta file, try and use that
if ((!$skeletonFileName) && 
  ( -f $submitterName.$skeletonFileExtension ) && 
  ( -r $submitterName.$skeletonFileExtension ) ){
    $skeletonFileName = $submitterName.$skeletonFileExtension;} 

#  If all else fails, try for any readable .skel file in the directory
if (!$skeletonFileName){
    if(!open(PIPE,"/bin/ls -l *$skeletonFileExtension |")){
	die "Error: failed to find .$skeletonFileExtension files in this directory\n";}
    print "$skeletonFileExtension files found:-\n";

    while(<PIPE>){
	@in=split;
	if($in[8] ) {
		$skeletonFileName=$in[8];
		print "\t$in[8]\n";
		}
	}

# If there's no $skeletonFileExtension files, what is there?
    if (!$skeletonFileName){
	open(PIPE,"/bin/ls -l |") || die "Error: Cannot list any files\n";
	print "NONE\nFiles found:-\n";
	while(<PIPE>){
		print;}
	die "Come back when you have a $skeletonFileExtension file containing your skeleton\n";
    }	
}	
print "Skeleton file used is $skeletonFileName\n";

# convert any Mac line endings to UNIX (upsets readseq sometimes)
system "perl -pi -e 's|\\r\\n?|\\n|g' $fastaInFileName";

# convert the fasta file to an embl multi-sequence file
system "echo java -cp readseq.jar run -f=em -a -o=$emblInFileName $fastaInFileName";

system "java -cp $readSeqJarFile run -f=em -a -o=$emblInFileName $fastaInFileName";


# Traverse the .em file finding '^ID   ''s
# make a new sub file for each entry - adapted from /ebi/production/seqdb/embl/tools/curators/scripts/splitff_embl.pl

( -e $emblInFileName) || die "file $emblInFileName does not exist\n";
my $entryTotal = 0;
chop ( $entryTotal = `grep -c '^ID   ' $emblInFileName` );
print "Detected $entryTotal sequences in $emblInFileName\n";
if ($entryTotal < 30000){
    print "Webin Bulk's fasta-upload facility can easily handle ".commify($entryTotal)." entries\n";
}
log_usage($entryTotal);
open ( IN, $emblInFileName) || die "cannot open $emblInFileName\n";
my $entry_number = 0;
my $entryVariables = "";
my $entryLength = "";
my $deLineUsed=0;
my $outFileName;
while ( <IN> ) {
    if ( /^ID  / ) {
	$deLineUsed=0;
	$entry_number++;
	@in = split;
	$entryVariables = $in[1];
	$entryLength  = $in[5];
	if($verboseMode==1){
	    print"\nID $entryVariables\n";
	}
	
	$outFileName = "$submitterName".sprintf("%0".length($entryTotal)."s", $entry_number).".sub";
	
# Bit of a hack - should pipe to info from the skeleton to the outfile manually while replacing the token
	system "cp $skeletonFileName $outFileName";

	open ( OUT, ">>$outFileName" ) || die "cannot create file $outFileName\n";      
    }
    
# Accumulate the DE lines (plus a leading space to accomodate second lines)
# these will override anything from the ID line
    if( /^DE  / ){
	if ($deLineUsed == 0){
	    $deLineUsed  = 1;
	    $entryVariables = "";
	}
	chop;
	$entryVariables .= substr($_, 4);
    }  
    
    if(( /^SQ  / ) || ( /^    / )){
	print OUT $_ ;
    }
    
# When at the end of the item, append the SQ->// lines to the outfile and then replace variables.
    if ( /^\/\/$/ ) {
	print OUT $_ ;     
	close ( OUT );
	system "perl -pi -e 's|$mySeqLengthToken|$entryLength|g' $outFileName";

	
	my $variableCount=0;
	my $latestVariableToken="";
	foreach $deValue(split(/;/,$entryVariables)){
	    $deValue=~s/^\s*|\s*$//g;
	    if ($deValue =~ s/\'/&apos;/g){
		print "Warning apostophe found in variable data, using '&apos;' instead\n";
	    }
	    $deValue = quotemeta($deValue);
	    $variableCount++;
	    $latestVariableToken=$myReplaceToken.$variableCount.$myReplaceToken;
	    system"perl -pi -e 's|$latestVariableToken|$deValue|g' $outFileName";

# system"perl -pi -e 's|.. is the worst hack 

# to replace the token with info - can't I do  it directly anyway?
	    if($verboseMode==1){
		print "variable $variableCount =$deValue.\n";
	    }
	}  
	$entryVariables = "";
    }
}

print "\n$entry_number sub files made.\n";
if($verboseMode==0){
    system "rm $submitterName.em";

}

print "Checking the sub files for unresolved tokens\n";
my $unresolvedTokensInFilesCount=0;
if(<$submitterName*.sub>){ 
    if(!open(PIPE,"/sbin/find . -name '$submitterName*.sub' | /usr/bin/xargs -i /sbin/grep -l '\\-\\-\\-' {} |")){ 
	print "Cannot access grep to check that all tokens have been replaced in the sub files\nSorry.";
	exit 1;
    }
    while(<PIPE>){ 
	print $_;
	$unresolvedTokensInFilesCount += 1;
    }
    close(PIPE);
}

else{ 
    print "Cannot find the ".$submitterName."xxx.sub files.\n"}

if ($unresolvedTokensInFilesCount > 0){
    if ($unresolvedTokensInFilesCount == 1){
	print "Unfortunately there is a sub file with unresolved tokens (see above)\n";}
    else {
	print "Unfortunately there are $unresolvedTokensInFilesCount sub files with unresolved tokens (see above)\n";}
}

exit 1;

