#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script takes a file containing 1+ ncbi format files in as input and
# splits the file into files containing the individual entries.  If the files
# contain accessions, the files will be called <acc>.ncbi.  Otherwise, the files 
# are called whatever is specified in the -s option.

#
#
# (C) EBI 2009
#
#===============================================================================

use strict;


################################################################################
sub split_file($$) {

    my ($i, $filename_suffix, $id_line, $line, $test_new_filename, $new_filename);
    my ($write_to_file, $num_entries, @files_created, $num_files_created);

    my $file_to_split = shift;
    my $entered_suffix = shift;

    $num_entries = `grep -c ^LOCUS $file_to_split`;
    $num_entries =~ s/\s*$//;


    if ($entered_suffix ne '') {
	$filename_suffix = $entered_suffix;
    }
    else {
	$filename_suffix = '.ncbi';
    }

    $write_to_file = 0;

    open(READ_BULK_FILE, "<$file_to_split") || die "Cannot open $file_to_split\n";
    while ($line = <READ_BULK_FILE>) {

	if ($line =~ /^LOCUS\s+(\S+)\s+/) {

	    $new_filename = $1.$filename_suffix;

	    $i = 1;
	    $test_new_filename = $new_filename;

	    while (-e $test_new_filename) {
		$test_new_filename = $new_filename."_$i";
		$i++;
	    }
	    $new_filename = $test_new_filename;
	    push (@files_created, $new_filename);

	    open(WRITE_ENTRY, ">$new_filename");
	    print WRITE_ENTRY $line;
	    $write_to_file = 1;
	}
	elsif ($line =~ /^\/\//) {
	    $write_to_file = 0;
	    print WRITE_ENTRY $line;
	    close(WRITE_ENTRY);
	}
	elsif ($write_to_file) {
	    print WRITE_ENTRY $line;
	}
    }

    close(READ_BULK_FILE);

    print "Files created:\n".join("\n", @files_created),"\n";

    $num_files_created = scalar(@files_created);

    print "\nSummary: $num_entries files found in bulk file. $num_files_created files were created.\n\n";
}
################################################################################
sub get_args(\@) {

    my ($arg, $usage, $file_to_split, $counter, $entered_suffix);
    my $args = shift;

    $usage =
    "\n USAGE: $0 <file_to_split> [-fflupd] [-ffl] [-s=<filename suffix>] [-h(elp)]\n\n"
  . " PURPOSE: Takes the entered file containing 1+ ncbi formatted entries and\n"
  . "         splits it into it's component entries (one entry per file).\n"
  . "         The entry files will be named after the accession with the .ncbi suffix\n"
  . "         (unless another suffix is specified). \n"
  . "         No files will be overwritten\n\n"
  . " -s=<suffix>      This allows you to add any suffix you want for the output files.\n"
  . "                  .ffl and .fflupd are simply the most popular, hence having options of their own.\n"
  . " -h(elp)          This help message\n"
  . " file to split    File contain 1+ ncbi entries with accessions.\n\n";

    $entered_suffix = "";
    $file_to_split = "";
    $counter = 1;

    if (! scalar(@$args)) {

	while ($counter < 3) {
	    print "Please enter filename to split into separate entry files: ";
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
	    if (( $arg =~ /^-h(elp)?/i ) || ( $arg =~ /^-u(sage)?/i )) {
		die $usage;
	    }
	    elsif ( $arg =~ /^-s=(.+)$/ ) {
                # $entered_suffix overrides default choice of suffix

		$entered_suffix = "." . $1;

		if ($entered_suffix =~ /^\.(\.+.+)$/) {
		    $entered_suffix = $1;
		}
	    }
	    elsif ($arg =~ /^[^-].+/) {
		# file input
		if (! -e $arg) {
		    die "Expecting a file containing 1+ ncbi entries: $arg does not exist\n";
		}
		else {
		    $file_to_split = $arg;
		}
	    }
	}
    }

    return($file_to_split, $entered_suffix);
}

################################################################################
sub main(\@) {

    my ($file_to_split, $entered_suffix);
    my $args = shift;

    ($file_to_split, $entered_suffix) = get_args(@$args);

    split_file($file_to_split, $entered_suffix);
}

################################################################################
# Run the script

main(@ARGV);
