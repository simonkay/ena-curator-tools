#!/ebi/production/seqdb/embl/tools/bin/perl
#
# split_large_input_files.pl <entry type> <verbose>
#    
# This file will take entries in <entry type>/uncompressed where
# entry_type can be normal, con or bqv and split them into files
# containing 15000 entries max.
#
# This file is called by release_loader.pl after uncompressing 
# ftp files and merging duplicates
#
# 14-DEC-2009 G. Hoad   Created

use diagnostics;
use warnings;
use strict;
use File::Copy;
use Utils qw(my_open printfile my_rename);
use FtpRelease::ReleaseConfig;
use Data::Dumper;

#my $MAX_ENTRIES_IN_FILE = 1500;
my $MAX_ENTRIES_IN_FILE = 2;

######################################################################
#
sub archive_copy_of_original_file($$$) {

    my FtpRelease::ReleaseConfig $config = shift( @_ );
    my $file_and_path = shift;
    my $file = shift;

    print "cp $file_and_path ".$config->{archive_data_dir}."\n";
    #copy($file_and_path, $config->{archive_data_dir});
    system("cp $file_and_path ".$config->{archive_data_dir});
    print "gzip ";
    print $config->{archive_data_dir};
    print "/$file\n";
    system("gzip ".$config->{archive_data_dir}."/$file");
}
######################################################################
#
sub split_non_bqv_file($\@) {

    my $file_to_split = shift;
    my $embl_prefixes = shift;

    my ($acc_prefix, $get_entry);

    print "Opening $file_to_split (read file)\n";
    my_open(my $READ_FILE, "<$file_to_split");

    my $non_embl_entry_counter = 0;
    my $entry_counter = 0;
    my $entry = "";
    my $ctr = 1;
    my $new_filename = $file_to_split."_".$ctr;

    while (-e $new_filename) {
	$ctr++;
	$new_filename = $file_to_split."_".$ctr;
    }

    print "Opening $new_filename (write file)\n";
    my_open(my $WRITE_FILE, ">$new_filename");

    while (my $line =~ <$READ_FILE>) {

	if ($line =~ /^LOCUS\s+([A-Za-z]+)/) {
	    
	    $acc_prefix = $1;
	    print "found $acc_prefix\n";
	    $get_entry = 1;
	    $entry_counter++;
	    
	    if ($entry ne "") {
		print $WRITE_FILE $entry;
		$non_embl_entry_counter++;
		
		if ($entry_counter % $MAX_ENTRIES_IN_FILE) {
		    
		    close($WRITE_FILE);

		    $new_filename = $file_to_split."_".$ctr++;
		    print "opening new file $new_filename\n";
		    my_open($WRITE_FILE, ">$new_filename");
		}
	    }
	    
	    foreach my $prefix (@$embl_prefixes) {
		
		if ($acc_prefix eq $prefix) {
		    $get_entry = 0;
		    print "Found embl entry prefix $prefix\n";
		    last;
		}
	    }
	}
	elsif (eof($WRITE_FILE)) {
	    print $WRITE_FILE $entry;
	}

	if ($get_entry) {
	    $entry = $line;
	}
    }
    
    close($WRITE_FILE);
    close($READ_FILE);

    return($entry_counter, $non_embl_entry_counter);
}
######################################################################
#
sub split_file_and_remove_embl_entries($$\@) {

    my ($num_lines_in_file, $split_at_this_line_num, $new_file);
    my ($new_tail_filename, $file_tail_len, $new_head_filename);

    my ($file_to_split, $type, $embl_prefixes) = @_;

    my $ctr = 1;
    $new_head_filename = $file_to_split."_".$ctr;

    while (-e $new_head_filename) {
	$ctr++;
	$new_head_filename = $file_to_split."_".$ctr;
    }

    print "using  $new_head_filename\n";
    # create file containing =< 15000 entries (number of entries dependent 
    # on size of any other files taken for processing)
    if ($type eq 'bqv') {
	$split_at_this_line_num = `grep -n '^>' $file_to_split | sed -n "${$MAX_ENTRIES_IN_FILE}p" | sed 's/:.*//'`;
   
	system("head -$split_at_this_line_num $file_to_split > $new_head_filename");
    
	# create file containing those entries which won't be going for processing this time
	$num_lines_in_file = `wc -l $file_to_split`;
	$file_tail_len = $num_lines_in_file - $split_at_this_line_num;
	$new_tail_filename = ".".$file_to_split.".".timeDayDate("yyyy-mm-dd-time").".tail";
	system("tail -$file_tail_len $file_to_split > $new_tail_filename");
	copy($new_tail_filename, $file_to_split); # overwrite original with beheaded file
	unlink($new_tail_filename);
    }
    else {
	print "going to sub split_non_bqv_file\n";
	my ($entry_counter, $non_embl_entry_counter) = split_non_bqv_file($file_to_split, @$embl_prefixes);
	print "$file_to_split:\n$entry_counter entries found\n $non_embl_entry_counter non-embl entries put into files\n\n";
    }
}
######################################################################
#
sub find_files_for_splitting($$) {

    my ($filename, $file, $new_file, $latest_split_file_num, $GET_ACC_PREFIXES);
    my (@embl_prefixes);

    my FtpRelease::ReleaseConfig $config = shift( @_ );
    my $type = shift;

    my @files = glob($config->{fixed_dir}.'/*');

    print Dumper(\@files);

    print "Trying to read ".$config->{embl_prefix_file}."\n";
    open(GET_ACC_PREFIXES, "<".$config->{embl_prefix_file});
    @embl_prefixes = <GET_ACC_PREFIXES>;
    close(GET_ACC_PREFIXES);

    foreach $file (@files) {

	print "file = $file\n";
	if ($file =~ /\/([^\/]+)$/) {
	    $filename = $1;
	}

	archive_copy_of_original_file($config, $file, $filename);

	$new_file = $config->{split_files_dir}."/.".$filename;
	print "cp $file $new_file\n";
	copy($file, $new_file);
	print "rm $file\n";
	unlink($file);

	my $num_entries_in_file = `grep -c '^LOCUS' $new_file`;
	print "There are $num_entries_in_file entries in $new_file\n";
	split_file_and_remove_embl_entries($new_file, $type, @embl_prefixes);
    }
}
######################################################################
#
sub main() {

    my $type = $ARGV[0];

    my $test = 1;
    my $verbose = 1;    

    my FtpRelease::ReleaseConfig $config = FtpRelease::ReleaseConfig->get_config( $type, $verbose, $test );

    find_files_for_splitting($config, $type);
}

main();
