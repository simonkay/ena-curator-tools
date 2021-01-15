#!/ebi/production/seqdb/embl/tools/bin/perl -w

# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/emblentry_fix_source.pl,v 1.6 2011/06/20 09:39:35 xin Exp $
#
#####################################################################
#
# Simple script to quick-fix lack of source features in patent entries.
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
sub add_source(\@$) {

    my ($entry_line, $source_feature_added, @corrected_entry);

    my $entry = shift;
    my $seqlen = shift;

    foreach $entry_line (@$entry) {
	if (($source_feature_added) || ((! $source_feature_added) && ($entry_line !~/^FT/))) {
	    push(@corrected_entry, $entry_line);
	}
	else {
	    push(@corrected_entry, "FT   source          1..$seqlen\n");
	    push(@corrected_entry, $entry_line);
	    $source_feature_added = 1;
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

    my ($inputted_files, $file, $line, $ftsource, $fh_lines_found, $num_corrected);
    my ($corrected_entry, $seqlen, $response, $ft_checked, $addsource_flag);

    my $args = shift;

    $inputted_files = get_args(@$args);


    foreach $file (@$inputted_files) {

	#overwrite_result_file($file.".sourceOK");

	open(READ, "<$file") || die "Cannot read $file.";
	open(APPEND, ">>$file.corrected") || die "Cannot append $file.sourceOK";

	$addsource_flag = 0;
	$fh_lines_found = 0;
	$num_corrected = 0;

	while ($line = <READ>) {
	    
	    if ($line ne "//\n") {

		if (($line =~ /^FT\s+/) && (!$ft_checked))  {
		    if ($line !~ /^FT\s+source/) {
			$addsource_flag = 1;
			$fh_lines_found = 0;
		    }
		    $ft_checked = 1;
		}
		elsif (($addsource_flag) && ($line =~ /^SQ\s+Sequence\s(\d+)\s+(AA|BP);/)) {
		    $seqlen = $1;
		}

		push(@entry, $line);
	    }
	    else {
		#process entry

		push(@entry, "//\n");

		if ($addsource_flag) {

		    $corrected_entry = add_source(@entry, $seqlen);
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

		$addsource_flag = 0;
		$ft_checked = 0;
		$fh_lines_found = 0;
		@entry = ();
	    }
	}

	close(READ);
	close(APPEND);

	print "$file.corrected has been written with $num_corrected corrected entries (with added FT source feature)\n";
    }   
}


main(@ARGV);
