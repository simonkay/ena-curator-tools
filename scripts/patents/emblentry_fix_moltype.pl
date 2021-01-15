#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/emblentry_fix_moltype.pl,v 1.5 2008/10/31 16:49:13 gemmah Exp $
#
#####################################################################
#
# Simple script to quick-fix lack of moltype features in patent entries.
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
sub add_moltype(\@$) {

    my ($entry_line, @corrected_entry);

    my $entry = shift;
    my $moltype = shift;

    foreach $entry_line (@$entry) {
	if ($entry_line =~ /FT\s+\/organism=/) {
	    push(@corrected_entry, $entry_line);
	    push(@corrected_entry, "FT                   /mol_type=\"$moltype\"\n");
	}
	else {
	    push(@corrected_entry, $entry_line);
	}
    }

    return(\@corrected_entry);
}
#############

sub overwrite_result_file($) {

    my $file = shift;

    if (-e $file) {
	print "Overwrite $file or quit? [q to quit] ";
	$response = <STDIN>;
	
	if ($response =~ /^q/i) {
	    die "Exiting script\n";
	}
	else {
	    print `rm $file`;
	    print "Re-writing $file\n\n";
	}
    }
}
#################
sub main(\@) {

    my ($inputted_files, $file, $line, $moltype_found, $response);
    my ($corrected_entry, $num_corrected);

    my $args = shift;

    $inputted_files = get_args(@$args);


    foreach $file (@$inputted_files) {

#	overwrite_result_file($file.".moltypeOK");

	if ($file !~ /\.corrected$/) {
	    $file = "$file.corrected";
	}

	open(READ, "<$file") || die "Cannot read $file.";
	open(APPEND, ">>$file.moltypeOK") || die "Cannot append $file.moltypeOK";

	$moltype_found = 0;
	$num_corrected = 0;

	while ($line = <READ>) {
	    
	    if ($line ne "//\n") {

		if ($line =~ /^ID(\s+[^;]+;){3}\s+([^;]+);/) {
		    $moltype = $2;

		    if ($moltype eq "XXX") {
			$moltype = "unassigned DNA"
		    }
		}
		elsif ($line =~ /^FT\s+\/moltype=/) {
		    print "changing moltype to mol_type: $line\n";
		    $line =~ s/moltype/mol_type/;
		    $moltype_found = 1;
		    $num_corrected++;
		}
		elsif ($line =~ /^FT\s+\/mol_type=/) {
		    $moltype_found = 1;
		}

		if ($line =~ /^FT\s+\/mol_type="PRT"/) {
		    $line = 'FT                   /mol_type="protein"'."\n";
		    $num_corrected++;
		}


		push(@entry, $line);
	    }
	    else {
		#process entry

		push(@entry, "//\n");

		if (!$moltype_found) {

		    $corrected_entry = add_moltype(@entry, $moltype);
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

		$moltype_found = 0;
		@entry = ();
	    }
	}

	close(READ);
	close(APPEND);

	rename("$file.moltypeOK", $file);

	print "$file has been written with $num_corrected corrected entries (where mol_type has been added or changed from moltype)\n";
    }   
}


main(@ARGV);
