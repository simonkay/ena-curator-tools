#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# author: Gemma
#
#  (C) EBI 2007
#
# Script renames <prefix>.updnew files in the current directory and converts
# them to <prefix>.upd1 if there are no files with the same prefix with 
# .upd1 as suffix.  Otherwise <prefix>.updnew will be renamed to the next
# numeric iteration available of .upd[X]
# 
#===============================================================================

use strict;
use File::Find;
use Cwd;

my (@updnew_files, @existing_upd_files);
my $current_working_dir = cwd;


################################################################################
sub find_all_upd_files() {

    my ($fileAndPath, $file);

    $fileAndPath = $File::Find::name;

    # if $file is a file (not a directory)
    if (-f $fileAndPath) {
 
        $file = $fileAndPath;
        $file =~ s/.+\/([^\/]+\..+)$/$1/;

        if ($file =~ /^[^.]+\.updnew$/) {
            push(@updnew_files, $file);
        }
	elsif ($file =~ /^[^.]+\.upd(\d+)?$/) {
            push(@existing_upd_files, $file);
	}
    }
}
################################################################################
sub find_all_update_files() {

    find(\&find_all_upd_files, $current_working_dir);

}
################################################################################
sub get_file_prefix($) {

    my ($prefix);
    my $file = shift;

    $prefix = $file;
    if ($prefix =~ /([^.]+)\./) {
	$prefix = $1;
    }

    return($prefix);
}
################################################################################
sub get_file_upd_suffix_num($) {

    my ($suffix_num);
    my $file = shift;

    $suffix_num = 1;

    if ($file =~ /[^.]+\.upd(\d+)/) {
	$suffix_num = $1;
    }

    return($suffix_num);
}
################################################################################
sub get_next_upd_num($) {

    my ($existing_upd_file, $existing_file_prefix, $max_upd_num, $upd_suffix_num);

    my $updnew_file_prefix = shift;

    $max_upd_num = 0;

    foreach $existing_upd_file (@existing_upd_files) {
	$existing_file_prefix = get_file_prefix($existing_upd_file);
	
	if ($updnew_file_prefix eq $existing_file_prefix) {
	    
	    $upd_suffix_num = get_file_upd_suffix_num($existing_upd_file);	    

	    if ($upd_suffix_num > $max_upd_num) {
		$max_upd_num = $upd_suffix_num;
	    }
	}
    }

    $max_upd_num++;

    return($max_upd_num);
}
################################################################################
sub rename_updnew_files() {

    my ($updnew_file, $file_prefix, $cmd, $new_filename, $next_upd_num);

    foreach $updnew_file (@updnew_files) {
	$file_prefix = get_file_prefix($updnew_file);

	$next_upd_num = get_next_upd_num($file_prefix);

	$new_filename = $file_prefix.".upd";

        # append update number to file suffix
	$new_filename .= $next_upd_num;
	
	if (! -e $new_filename) {
	    $cmd = "mv $updnew_file $new_filename";
	    print "Renaming $updnew_file as $new_filename\n";
	    system($cmd);
	}
	else {
            # this should never happen, but it's been put in 'just in case'
	    print "ERROR: $updnew_file is not being renamed (to $new_filename) because $new_filename already exists.\nPlease contact Gemma about this.\n";
	}
    }

}
################################################################################
sub main(\@) {

    my ($arg);
    my $args = shift;

    foreach $arg (@$args) {
	if (( $arg =~ /^-h(elp)?/i ) || ( $arg =~ /^-u(sage)/i )) {
	    die "This script renames <file_prefix>.updnew files found in the current directory to the next version of <file_prefix>.upd.  No files will be overwritten by this script.\n";
	}
    }

    find_all_update_files();

    if (@updnew_files) {
	print "updnew files found:\n". join("\n", @updnew_files). "\n\n";

	rename_updnew_files();
    }
    else {
	print "There are no .updnew files in this directory to rename to .upd files.\n";
    }
}

################################################################################
# Run the script

main(@ARGV);
