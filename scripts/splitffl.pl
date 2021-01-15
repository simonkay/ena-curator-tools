#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script takes a file containing 1+ embl format files in as input and
# splits the file into files containing the individual entries.  If the files
# contain accessions, the files will be called <acc>.ffl.  Otherwise, the files 
# are called 1.sub, 2.sub etc (if there are less than 10 entries they will be called 1.sub, 2.sub; >9 but <100 01.sub, 02.sub etc etc)
#
#  (C) EBI 2007
#
#===============================================================================

use strict;
use Cwd;
use File::Copy;
use FileHandle;

my $current_working_dir = cwd;


################################################################################

sub mention_history_event($) {

    my ($dir_listing, $event_code, $msg_word);

    my $num_entries = shift;

    $dir_listing = glob("$current_working_dir/*.skel");

    # if there are no .skel files found mark as event code 23
    if (defined($dir_listing)) {

	$event_code = "23";
	$msg_word = "MEGABULK";
    }
    else {
        # if .skel files are found mark as event code 8

	$event_code = "8";
	$msg_word = "bulk";
    }

    print "To log the $msg_word data received event do\n"
	. "dsHistory -e".$event_code." '$num_entries subs received'\n";
}

################################################################################
sub add_entry_to_file(\@$\@$$$) {

    my ($i, $filename, $file_num, $overwrite_flag);

    my $entry = shift;
    my $accession = shift;
    my $files_created = shift;
    my $entry_num = shift;
    my $suffix = shift;
    my $num_entries = shift;

    if ($accession =~ /[A-Z]{1,4}\d{5,9}/) {

	$i=1;
	$filename = $accession.$suffix;

        # get unique filename (don't want to overwrite existing ffl files)
	while (-e $filename) {
	    $filename = $accession.$suffix.$i;
	    $i++;
	}
    }
    else {

	#create filename like 0001.sub, 0002.sub, 0003.sub...sprintf
	$filename = sprintf("%0".length($num_entries)."d", $entry_num).$suffix;

	if (-e $filename) {
	    print "Copying existing $filename to $filename.bak to make way for new copy of $filename...\n";
	    copy( $filename, $filename.".bak" );
       }

    }

    open(WRITE_TO_FFL, ">$filename") || die "Cannot write to $filename\n";
    print WRITE_TO_FFL @$entry;
    close(WRITE_TO_FFL);

    push(@$files_created, $filename);
}

################################################################################
sub split_file($$$) {

    my (@entry, @all_entries, @block_entries, $line, $lastArrayElement, $j, $i, $accession, $block_num, @fhout,$blockNum);
    my (@files_created, $entry_num, $num_entries, $in_entry, $continue_split);
    my ($filename_suffix, $id_line);

    my $file_to_split = shift;
    my $entered_suffix = shift;
    my $entry_num_per_block = shift;

    $accession = "";

    $num_entries = `grep -c ^ID $file_to_split`;
    $num_entries =~ s/\s*$//;


    if ($entered_suffix ne '') {
	$filename_suffix = $entered_suffix;
    }
    else {

	$id_line = `grep ^ID $file_to_split | head -1`;

	# if id line contains no accessions, file suffix will be ".sub"...
	if ($id_line =~ /^ID   XXX;/) {
	    $filename_suffix = '.sub';
	}
        # ...or else it will be given the same suffix as the input file
	elsif ($file_to_split =~ /(\.[A-Za-z]+)$/) {
	    $filename_suffix = lc($1);
	}
    }

    if ($num_entries > 250 && $entry_num_per_block ==0) {

	$continue_split = "";

	while ($continue_split !~ /^[yYnN]/) {
	    print "\nThe bulk file contains $num_entries entries.\n\nWarning: There are > 250 entries in the bulk file.  Do you really want to split them? (y/n) ";
	    $continue_split = <STDIN>;

	    if ($continue_split =~ /^n/i) {
		die "\nNo splitting will occur. Exiting script.\n";
	    }
	}
    }

    open(READ_BULK_FILE, "<$file_to_split") || die "Cannot open $file_to_split\n";
    @all_entries = <READ_BULK_FILE>;
    close(READ_BULK_FILE);

    $lastArrayElement = scalar(@all_entries) -1;
    $entry_num = 0;
    $blockNum = 0;

    ### block ##########
    if($entry_num_per_block !=0){
        $block_num = (int ($num_entries/$entry_num_per_block))+1;

	foreach my $blockNum (1 .. $block_num){
	  open ( $fhout[$blockNum],'>',"block.$blockNum") or die "can not open file block.$blockNum\n";
	}
    }
    ###################

    for ($i=0; $i<@all_entries; $i++) {

	$j = $i+1;

	if ($all_entries[$i] =~ /^ID/) {

	    if ($all_entries[$i] =~ /^ID\s+([^;]+);/) {
		$accession = $1;
	    }

	    $in_entry = 1;
	    push(@entry, $all_entries[$i]);
	}
	elsif (( defined($all_entries[$j]) && ( $i == $lastArrayElement )) || ($all_entries[$i] =~ /^\/\//)) {

	    $in_entry = 0;
	    $entry_num++;
	    push(@entry, $all_entries[$i]);

	    if($entry_num_per_block ==0){
	      add_entry_to_file(@entry, $accession, @files_created, $entry_num, $filename_suffix, $num_entries);
	    }

	    ##### block ############
	    else{
	      if((($entry_num-1)%$entry_num_per_block)==0 ){
		$blockNum++;
	      }    
	      my $fileH = $fhout[$blockNum];
	      print $fileH @entry;
	    }
	    ##### block ############

	    $accession = "";
	    @entry = ();
	}
	elsif ($in_entry) {
	    push(@entry, $all_entries[$i]);
	}
    }

    if($entry_num_per_block !=0){
      foreach my $blockNum (1 .. $block_num){
	close ( $fhout[$blockNum]) or die "can not close file block.$blockNum\n";
      }
    }

    close(READ_BULK_FILE);

    print "Files created:\n".join("\n", @files_created),"\n";

    print "\nSummary: $num_entries files found in bulk file; $entry_num files created\n\n";


    return($entry_num);
}

#################################################################################
sub get_args(\@) {

    my ($arg, $usage, $file_to_split, $counter, $entered_suffix, $entry_num_per_block);
    my $args = shift;


    $usage =
    "\n USAGE: $0 <file_to_split> [-fflupd] [-ffl] [-h(elp)]\n\n"
  . " PURPOSE: Takes the entered file containing 1+ embl formatted entries and\n"
  . "         splits it into it's component entries (one entry per file).\n"
  . "         If these entries contain an accession number, they will\n"
  . "         be named after the accession with the .ffl suffix. Alternatively,\n"
  . "         they will be named 01.sub, 02.sub etc (padded according to the number\n"
  . "         of entries).  No files will be overwritten\n\n"
  . " -ffl             The output files will be named <acc>.ffl (default if accessions are present in input file)\n"
  . " -fflupd          The output files will be named <acc>.fflupd\n"
  . " -s=<suffix>      This allows you to add any suffix you want for the output files.\n"
  . "                  .ffl and .fflupd are simply the most popular, hence having options of their own.\n"
  . " -entry_num    The number of entries per output block.\n" 
  . " -h(elp)          This help message\n"
  . " file to split    File contain 1+ embl entries with accessions.\n" 
  . "\n";

    $entered_suffix = "";
    $file_to_split = "";
    $counter = 1;
    $entry_num_per_block=0;

    if (! scalar(@$args)) {

	while ($counter < 3) {
	    print "Please enter filename to split into separate .ffl/.sub files: ";
	    $file_to_split = <STDIN>;
	    chomp($file_to_split);

	    if (! -e $file_to_split) {
		print "Filename not found.\n";
		$counter++;
	    }
	    else {
		last;
	    }
	}

	if ($counter == 3) {
	    die "A filename from the current directory must be entered. Exiting script...\n";
	}
    }
    else {
	foreach $arg (@$args) {
	    print "arg=$arg\n";
	    if (( $arg =~ /^-h(elp)?/i ) || ( $arg =~ /^-u(sage)/i )) {
		die $usage;
	    }
	    elsif (( $arg =~ /^-(fflupd)/i ) || ( $arg =~ /^-(ffl)/i )) {
                # $entered_suffix overrides default choice of suffix
		$entered_suffix = "." . lc($1);
	    }
	    elsif ( $arg =~ /^-s=(.+)$/ ) {
                # $entered_suffix overrides default choice of suffix

		$entered_suffix = "." . $1;

		if ($entered_suffix =~ /^\.(\.+.+)$/) {
		    $entered_suffix = $1;
		}
	    }
	    elsif ( $arg =~ /^-entry_num(\D+)(\d+)/i ) {	      

		$entry_num_per_block = lc($2);
	    }
	    elsif ($arg =~ /^[^-].+/) {
		# file input
		if (! -e $arg) {
		    die "Expecting a file containing 1+ embl entries: $arg does not exist\n";
		}
		else {
		    $file_to_split = $arg;
		}
	    }
	}
    }

    return($file_to_split, $entered_suffix, $entry_num_per_block);
}

################################################################################
sub main(\@) {

    my ($arg, $usage, $file_to_split, $entered_suffix, $num_entries, $entry_num_per_block);
    my $args = shift;

    ($file_to_split, $entered_suffix, $entry_num_per_block) = get_args(@$args);

    $num_entries = split_file($file_to_split, $entered_suffix,$entry_num_per_block);

    mention_history_event($num_entries);
}

################################################################################
# Run the script

main(@ARGV);
