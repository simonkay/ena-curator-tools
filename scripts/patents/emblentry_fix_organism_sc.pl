#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/emblentry_fix_organism_sc.pl,v 1.2 2010/02/08 10:05:35 gemmah Exp $
#
#####################################################################
#
# Simple script to quick-fix lack of organism qualifier in patent entries.
# FT    /organism="synthetic construct" is added by default.
#
# Author: Gemma Hoad
#
#####################################################################

sub get_args(\@) {

    my (@inputtedFiles, $arg);

    my $args = shift;

    foreach $arg ( @$args ) {

	if (! -e $arg) {
	    die "$arg is not a recognised filename\n";
	}

	push(@inputtedFiles, $arg);
    }

    return(\@inputtedFiles);
}
################
sub add_organism(\@$) {

    my ($entry_line, @corrected_entry);

    my $entry = shift;
    my $replacement_org = shift;

    foreach $entry_line (@$entry) {
	if ($entry_line =~ /FT   source/) {
	    push(@corrected_entry, $entry_line);
	    push(@corrected_entry, "FT                   /organism=\"$replacement_org\"\n");
	}
	else {
	    push(@corrected_entry, $entry_line);
	}
    }

    return(\@corrected_entry);
}
#############


#################
sub main(\@) {

    my ($inputted_files, $file, $line, $organism_found, $response);
    my ($corrected_entry, $num_corrected, $org);

    my $args = shift;

    $inputted_files = get_args(@$args);

    # organism is defaulted to:
    $org = 'synthetic construct';


    foreach $file (@$inputted_files) {

	if ($file !~ /\.corrected$/) {
	    $file .= ".corrected";
	}

	open(READ, "<$file") || die "Cannot read $file";
	open(APPEND, ">>$file.orgOK") || die "Cannot append $file.orgOK";

	$organism_found = 0;
	$num_corrected = 0;

	while ($line = <READ>) {
	    
	    if ($line ne "//\n") {

		if ($line =~ /^FT\s+\/organism=/) {
		    $organism_found = 1;
		}

		push(@entry, $line);
	    }
	    else {
		#process entry

		push(@entry, "//\n");

		if (!$organism_found) {

		    $corrected_entry = add_organism(@entry, $org);
		    $num_corrected++;

		    foreach (@$corrected_entry) {
			print APPEND $_;
		    }
		}
		else {
		    foreach (@entry) {
			print APPEND $_;
		    }
		}

		$organism_found = 0;
		@entry = ();
	    }
	}

	close(READ);
	close(APPEND);

	rename("$file.orgOK", $file);

	print "$file has been updated with $num_corrected corrected entries (where /organism has been added)\n";
    }   
}


main(@ARGV);
