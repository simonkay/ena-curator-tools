#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script takes one or more .temp files and the name of a qualifer as input,
# where the qualifier contains multiple comma-separated values.  The script then
# creates duplicates of the entry within the input file, each with a single value
# as the new qualifier value, from the list of values in the original file.
# Test mode will not overwrite the temp file.
#
#
# Gemma Hoad 11-Nov-09
#===============================================================================

use strict;
use File::Copy;
use Data::Dumper;

my $usage = "\nUsage: inflate_by_qualifier.pl <qualifier> [-test]\n\n"
    ."e.g. \"inflate strain\" (where \"inflate\" is the script alias\n"
    ."and \"strain\" is the qualifier to expand.\n\n"
    ."This script is used to generate multiple entries from a single\n"
    ."entry where there are multiple values in the specified qualifier.\n"
    ."Note this script expands the chosen qualifier in all *.temp files\n"
    ."in the current directory.\n\n"
    ."<qualifier>  e.g. strain, clone, sub_clone (unquoted qualifier name)\n\n"
    ."-test        Test mode will create a load of .temp.inflate.del files\n"
    ."             and the original temp files will remain unchanged.\n\n"
    ."In the entry, multiple qualifier fields should look like\n"
    ."/clone=\"a1, a2, a3\"  i.e. comma-separated\n\n"
    . "The resultant files are named 1.temp, 2.temp etc and the original temp\n"
    ."files are renamed (<orig filename>.del\n\n";

#############################################################
#
sub get_non_input_temp_files_for_renumbering(\@) {

    my ($i, $j, $found_match, @non_input_temp_files, $non_input_temp_files);

    my $files_to_inflate = shift;

    my @all_temp_files = glob("*.temp");

    for ($i=0; $i<@all_temp_files; $i++) {

	$found_match = 0;

	for ($j=0; $j<@$files_to_inflate; $j++) {

	    if ($all_temp_files[$i] eq $$files_to_inflate[$j]) {
		$found_match = 1;
	    }
	}

	if (!$found_match) {
	    push(@non_input_temp_files, $all_temp_files[$i]);
	}
    }

    #print Dumper(\@non_input_temp_files);

    #exit;

    $non_input_temp_files = join(" ", @non_input_temp_files);

    return(\$non_input_temp_files);
}
#############################################################
#
sub concatenate_new_files(\@$$) {

    my ($cat_cmd, $cat_filename, $file, @intermed_files, $temp_file);

    my ($temp_files, $verbose, $test) = @_;

    $cat_filename = "all_temp_files_after_inflation";
    $cat_cmd = "cat *.temp.inflate.del > $cat_filename";

    $verbose && print "\nCatting all .temp.inflate.del files and other temp files together in order to re-split them in the right order\n".$cat_cmd."\n";
  
    system($cat_cmd);

    # delete intermediate .temp.inflate.del files after they have been concatenated
    @intermed_files = glob("*.temp.inflate.del");
    foreach $file (@intermed_files) {
	unlink($file);
    }

    if (!$test) {
	# add .del to filename of input files (since they will have been replaced) 
	foreach $temp_file (@$temp_files) {
	    move($temp_file, "$temp_file.del");
	}
    }

    return($cat_filename);
}
#############################################################
#
sub split_files($$$) {

    my ($split_cmd);

    my ($concat_filename, $verbose, $test) = @_;

    $split_cmd = "/ebi/production/seqdb/embl/tools/curators/scripts/splitffl.pl $concat_filename -s=";

    if ($test) {
        # define filename suffix of newly split files
	$split_cmd .= "temp.inflate.del";
	$verbose && print "Creating numbered .temp.inflate.del files\n\n";
    }
    else {
	$split_cmd .= "temp";
	$verbose && print "Creating numbered .temp files\n\n";
    }

    system($split_cmd);
    unlink($concat_filename);
}
#############################################################
#
sub renumber_temp_files_in_dir(\@$$) {

    my ($split_cmd, $concat_filename);

    my ($temp_files, $verbose, $test) = @_;

    $concat_filename = concatenate_new_files(@$temp_files, $verbose, $test);

    split_files($concat_filename, $verbose, $test); 
}
#############################################################
#
sub inflate_files(\@$$$) {

    my ($READFILE, $WRITEFILE, $all_qualifier_values, $line, @qualifier_values);
    my ($entry_ctr, $file, $entry, $entry_copy, @old_files);

    my ($files_to_inflate, $qualifier_to_inflate, $verbose, $test) = @_;


    # cleanup previous test files
    @old_files = glob("*.temp.inflate.del");
    
    foreach $file (@old_files) {
	unlink($file);
    }

    $qualifier_to_inflate = quotemeta($qualifier_to_inflate);


    foreach $file (@$files_to_inflate) {

	open($READFILE, "<$file") || die "Cannot read $file\n";
	$verbose && print "---------\nCreating $file.inflate.del to save extra entries to.\n";
	open($WRITEFILE, ">$file.inflate.del") || die "Cannot open new file $file.inflate.del\n";

	while ($line = <$READFILE>) {

	    if ($line =~ /\/$qualifier_to_inflate\=\"([^\"]+)\"/) {

		$all_qualifier_values = $1;
		@qualifier_values = split(/ *, */, $all_qualifier_values);
		$verbose && print scalar(@qualifier_values)." qualifier value(s) found:\n$line\n";
		$line =~ s/$qualifier_to_inflate\=\"([^\"]+)\"/$qualifier_to_inflate\=\"\"/;
	    }

	    $entry .= $line;

	    if ($line =~ /^\/\//) {

		if ($all_qualifier_values eq "") {
		    print "\nWARNING: The qualifier $qualifier_to_inflate is not found in $file\n";
		}
		else {
		    for ($entry_ctr=0; $entry_ctr<@qualifier_values; $entry_ctr++) {
			
			if (defined($qualifier_values[$entry_ctr])) {
			    $entry_copy = $entry;
			    $verbose && print "Entry ".($entry_ctr+1).": replacing \/$qualifier_to_inflate\=\"\" with \/$qualifier_to_inflate\=\"$qualifier_values[$entry_ctr]\"\n";
			    $entry_copy =~ s/\/$qualifier_to_inflate\=\"\"/\/$qualifier_to_inflate\=\"$qualifier_values[$entry_ctr]\"/;
			    
			    print $WRITEFILE $entry_copy;
			}
		    }
		    $entry = ""; 
		    $all_qualifier_values = "";
		}
	    }
	}

	close($READFILE);
	close($WRITEFILE);

	#if (!$test) {
	#    print scalar(@qualifier_values)." entries have been written to $file\n";
	#}
    }
}
#############################################################
#
sub check_for_multiple_entries_in_file(\@) {

    my ($file, $num_entries, %files_with_too_many_entries);

    my $file_list = shift;

    foreach $file (@$file_list) {
       
	$num_entries = `grep -c ^ID $file`;
	chomp($num_entries);

	if ($num_entries > 1) {
	    $files_with_too_many_entries{$file} = $num_entries;
	} 
    }

    if (scalar(keys(%files_with_too_many_entries))) {
	print "Input files are only allowed to contain one entry each.\nFiles with more than one entry:\n";

	foreach $file (keys %files_with_too_many_entries) {
	
	    print "$file contains $files_with_too_many_entries{$file} entries\n";
	}

	die "\n".$usage;
    }
}
#############################################################
#
sub get_files_to_inflate() {

    my @files_to_inflate = glob("*.temp");

    return(\@files_to_inflate);
}
#############################################################
#
sub get_args(\@) {
    
    my ($qualifier_to_inflate, $arg);

    my $args = shift;

    my $verbose = 0;
    my $test = 0;

    # not enough arguments (2 minimum required)
    if (! defined $$args[1]) {
	die $usage;
    }

    foreach $arg (@$args) {

	if (($arg =~ /^\-h(elp)?/) || ($arg =~ /^\-usage/)) {
	    die $usage;
	}
	elsif ($arg =~ /\-v(erbose)?/) {
	    $verbose = 1;
	}
	elsif ($arg =~ /\-t(est)?/) {
	    $test = 1;
	}
	else {
	    $qualifier_to_inflate = $arg;
	}
    }

    if (!defined($qualifier_to_inflate)) {
	die "You need to enter a qualifier to inflate.\n$usage";
    }

    return($qualifier_to_inflate, $verbose, $test);
}

#############################################################
#
sub main(\@) {

    my ($qualifier_to_inflate, $verbose, $test, $files_to_inflate);

    my $args = shift;

    ($qualifier_to_inflate, $verbose, $test) = get_args(@$args);

    $files_to_inflate = get_files_to_inflate();

    inflate_files(@$files_to_inflate, $qualifier_to_inflate, $verbose, $test);

    renumber_temp_files_in_dir(@$files_to_inflate, $verbose, $test);
}
#############################################################
#

main(@ARGV);
