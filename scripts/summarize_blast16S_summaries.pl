#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  SCRIPT DESCRIPTION:
#
#  This script reads the summary output from the curator_blast and looks for any
#  complementary sequences in there.  If it finds any, it lists them at the top
#  of the same file (so the curators can see if there are any at a glance).
#
#===============================================================================

use strict;

################################################################################
#

sub find_complement_files($) {

    my ($line, @entry_files, $acc, $filename);

    my $input_file = shift;

    open(READSUMM, "<".$input_file) || die "Cannot read $input_file\n";

    while ($line = <READSUMM>) {
	if ($line =~ /([^:]+): complement/) {
	    
	    $acc = $1;

	    if ($acc =~ /^[A-Z]+\d+$/) {
		if (-e $acc.".fflupd") {
		    $filename = $acc.".fflupd";
		}
		elsif (-e $acc.".ffl") {
		    $filename = $acc.".ffl";
		}
	    }
	    else {
		if (-e $acc.".temp") {
		    $filename = $acc.".temp";
		}
		elsif (-e $acc.".sub") {
		    $filename = $acc.".sub";
		}
	    }

	    push(@entry_files, $filename);
	}
    }

    close(READSUMM);

    return(\@entry_files);
}

################################################################################
#

sub cat_summary_file_with_full_summaries($$) {

    my ($cmd);

    my $new_filename = shift; 
    my $input_file = shift;

    $cmd = "cat $new_filename $input_file > $input_file".".new";

    print "cmd = $cmd\n";

    system($cmd);

    unlink($new_filename);

    $cmd = "mv $input_file".".new $input_file";

    system($cmd);
}

################################################################################
#

sub save_complement_files(\@$) {

    my ($new_filename, $file);

    my $entry_files = shift;
    my $input_file = shift;

    $new_filename = "blast16S_revcomp";
    open(SAVESUMMARY, ">".$new_filename);

    print SAVESUMMARY "Reverse complemented files:\n";

    foreach $file (@$entry_files) {
	print SAVESUMMARY "$file\n";
    }
    print SAVESUMMARY "#########################################\n\n";

    close(SAVESUMMARY);

    cat_summary_file_with_full_summaries($new_filename, $input_file);
}

################################################################################
#

sub get_args(\@) {

    my ($input_file, $arg);

    my $args = shift;

    my $usage =
    "\nPURPOSE: This script takes the output summary from blast16S, finds the sequences which show the complement of a blast database entry matches.  These entries are in term summarized.\n\n"
  . " USAGE:   summarize_blast16S_summaries.pl <summary file> [-v] [-h]\n\n"
  . "   <summary file>      This is the file containing the summary of blast16S results\n\n"
  . "   -v                  verbose mode\n\n"
  . "   -h                  shows this help text\n\n";


    foreach $arg (@$args) {
	if (! -e $arg) {
	    die $usage;
	}
	elsif ($arg =~ /(^[^-].+)/) {
	    return($1);
	}
    }
}

################################################################################
#

sub main(\@) {
    
    my ($input_file, $entry_files);

    my $args = shift;

    $input_file = get_args(@$args);

    $entry_files = find_complement_files($input_file);

    save_complement_files(@$entry_files, $input_file);
}

################################################################################
# run the script

main(@ARGV);
