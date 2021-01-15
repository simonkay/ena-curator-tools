#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script scans a *.temp for the given qualifier
# and searches the substite list to see if the given
# qualifier needs replacing.  The new qualifier value 
# replaces the old.
#
# Gemma Hoad  21-Dec-2009

use File::Copy;

my $PATTERN_FILE = "/ebi/production/seqdb/embl/tools/curators/data/substitute_patterns.lis";


sub search_and_replace_pattern($$\@) {

    my $qual_value = shift;
    my $line_of_file = shift;
    my $patterns = shift;

    my $updated_qual = "";

    $qual_value = quotemeta($qual_value);
    #print "qual_value = |$qual_value|\n";

    foreach $subs_pattern (@$patterns) {

	#print "subs_pattern = |$subs_pattern|";

	if ($subs_pattern =~ /$qual_value\t/i) {

	    #print "found $qual_value\n";
	    my ($bad_pat, $good_pat) = split(/\t/, $subs_pattern);
	    chomp($good_pat);

	    $line_of_file =~ s/$qual_value/$good_pat/;
	    $updated_qual = $good_pat;
	    last;
	}
    }

    return ($line_of_file, $updated_qual);
}

sub get_args(\@) {

    my $args = shift;

    my $usage = "\nsubstitute_pattern.pl <qualifier> [-test] [-help]\n\nThis script changes the entered qualifier value of the entered qualifier into the corrected value as listed in $PATTERN_FILE\n\nAll .temp files in the current directory will be browsed for qualifer values which need correcting.\n\nIf the -test flag is used, new files for files with substitutions will be created (and called <test_file>.sub_patterns) and the original files will be left unchanged.\nOutside test mode, the newly corrected files will replace the original temp files and the original temp files are renamed to <orig temp filename).bak\n\n";

    my $test = 0;
    my $qualifier = "";

    foreach my $arg (@$args) {

	if ($arg =~ /\-t(est)?/) {
	    $test = 1;
	}
	elsif ($arg =~ /\-h(elp)?/) {
	    die $usage;
	}
	else {
	    $qualifier = $arg;
	}   
    }

    if ($qualifier eq "") {
	die "You forgot to enter the qualifier\n\n$usage";
    }

    return($qualifier, $test);
}




sub main() {

    my ($updated_qual);

    my ($qualifier, $test) = get_args(@ARGV);


    open(READ_PATTERNS, "<$PATTERN_FILE") || die "Cannot open $PATTERN_FILE\n";
    my @patterns = <READ_PATTERNS>;
    close(READ_PATTERNS);


    my @temp_files = glob("*.temp");

    foreach my $temp_file (@temp_files) {

	my %updates = ();
	my $update_count = 0;

	if (open(READ_TEMP_FILE, "<$temp_file\n")) {

	    open(WRITE_TEMP_FILE, ">$temp_file.sub_patterns");

	    while (my $line = <READ_TEMP_FILE>) {

		if ($line =~ /\/$qualifier=\"([^"]+)\"/) { #"

		    ($line, $updated_qual) = search_and_replace_pattern($1, $line, @patterns);

		    if ($updated_qual ne "") {
			$updates{$1} = $updated_qual;
			$update_count++;
		    }
		}

	        print WRITE_TEMP_FILE $line;
	    }

	    close(WRITE_TEMP_FILE);
	}

		if ($update_count) {
		    print "\n$temp_file has been updated with the following bad qualifier names in $update_count entries:\n";
		    
		    foreach my $bad_qual (keys %updates) {
			print "$bad_qual => $updates{$bad_qual}\n";
		    }

		    if (!$test) {
			copy($temp_file, $temp_file.".bak");
			rename($temp_file.".sub_patterns", $temp_file)
		    }
		}
		else {
		    unlink("$temp_file.sub_patterns");
		}
    }
}

main();
