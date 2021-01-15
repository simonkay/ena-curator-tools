#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  SCRIPT DESCRIPTION:
#
# This script loads entries found in the genome submission directories into
# enapro.
# 
#
#===============================================================================

use strict;
use DBI;
use File::Copy;
use SeqDBUtils2 qw(timeDayDate assign_accno_list);
use GenomeProjectPipeline;
use Data::Dumper;
use DBLog_test;

# changes to gpscan_test if in test mode
my $DATA_DIR = '/ebi/production/seqdb/embl/data/ena_submission_accounts';
my $DATA_DIR_TEST = '/ebi/production/seqdb/embl/data/gpscan_test';
my $EXTERNAL_FTP_DIR = "/ebi/ftp/private";
my $verbose = 0;
# max number of entries to load at one time
my $MAX_PROCESSING_SIZE = 15000;  


#############################################################
#
sub housekeeping($$$) {

    my (@files_to_check, @files_to_check2, $file);

    my ($dir_to_tidy, $days, $test_mode) = @_;

    @files_to_check  = glob("$dir_to_tidy/??????_*.seq.gz");
    @files_to_check2 = glob("$dir_to_tidy/??????_*.bqv.gz");

    push(@files_to_check, @files_to_check2);
 
    foreach $file ( @files_to_check ) {

	if ( -f( $file ) && -M( $file ) > $days ) {

	    if ($test_mode) {
		print STDERR "Removing '$file' (housekeeping).\n$!\n";
	    }
	    else {
		if (!$test_mode) {
		    unlink( $file) ||
			print STDERR "Can`t remove '$file' (housekeeping).\n$!\n";
		}
	    }
	}
    }
}
#############################################################
#
sub get_project_email_addresses($$) {

    my ($sql, $sth, $email_addresses);

    my ($dbh, $project_name) = @_;

    $sql = "SELECT email_address from cv_project_list where project_abbrev = ?";
    $sth = $dbh->prepare($sql);
    $sth->execute($project_name);

    $email_addresses = $sth->fetchrow_array();

    if (! $email_addresses) {
	print STDERR "There are no email_addresses found for the $project_name genome project\n";
    }

    return($email_addresses);
}
#############################################################
#
sub email_submitter_with_report($$$$$$) {

    my ($email_subject, $initial_text, $email_addresses, $line);

    my ($dbh, $project_path, $project_name, $report_file, $warning_list, $test) = @_;

    $email_subject = "Automatic submission processing summary $project_name";

    if ($test) {
	$email_subject .= " (\$DS_TEST)";
	$email_addresses = "gemmah\@ebi.ac.uk,nimap\@ebi.ac.uk";
    }
    else {
	$email_addresses = get_project_email_addresses($dbh, $project_name);

	if (!$email_addresses) {
	    print STDERR "Sending email to gemmah\@ebi.ac.uk and nimap\@ebi.ac.uk instead\n";
	    $email_addresses = "gemmah\@ebi.ac.uk,nimap\@ebi.ac.uk";
	}
    }

    $initial_text = "The following is a list of entries (and base quality values if submitted too) showing the success or failure of the load:\n\n";

    open(MAIL, "|/usr/sbin/sendmail -oi -t");

    print MAIL 'To: '."$email_addresses\n"
	. 'From: datalib@ebi.ac.uk'."\n"
	. "Subject: $email_subject\n"
	. $initial_text;

    open(READ_REPORT, "<$report_file");
    while ($line = <READ_REPORT>) {
	print MAIL "$line\n";
    }
    close(READ_REPORT);

    close(MAIL);

    print STDERR "\nEmails have been sent to: $email_addresses\n";
}
#############################################################
#
sub open_individual_seq_file($;$$$) {

    my ($WRITE_DOT_SEQFILE, $bqv_new_filename, $seq_filename);

    my ($filename, $project_path, $file_counter, $acc) = @_;

    $seq_filename = "";

    if ($filename ne "") {
	$verbose && print STDERR "\nOpening existing file $filename to save seq data to\n\n";
    }
    else {
	$filename = "$project_path/split_seq/.".sprintf("%06d", $file_counter)."_".$acc.".seq";

	$verbose && print STDERR "\nOpening new file $filename to save seq data to\n";
    }

    open($WRITE_DOT_SEQFILE, ">$filename") || print STDERR "Cannot open $filename in write-mode\n";
    $bqv_new_filename = substr($filename, 0, -3).'bqv';
    $bqv_new_filename =~ s/split_seq/split_bqv/;

    return ($WRITE_DOT_SEQFILE, $bqv_new_filename, $filename);
}
#############################################################
#
sub split_file_into_bqv_and_normal_entry_files($$$$\@) {

    my ($line, $acc, $ac_star, $bqv_new_filename);
    my ($bqv_info, $method, $entry, $seqver, $seqlen, $cumulative_file);
    my (%filename, $WRITE_DOT_SEQFILE, $file_counter, $seq_filename);

    my ($dbh, $project_path, $project_name, $project_code, $files_to_split) = @_;

    $file_counter = 0;

    foreach $cumulative_file (@$files_to_split) {

	if ($cumulative_file !~ /\.\~[0-9\.]+\~$/) { # if not a backup file...

	    if (open(CUMU_FILE, "<$cumulative_file")) { 

		# collect entry and bqv data.  Take info from entry for bqv header.
		# write info to separate bqv and seq file after end of each entry has been read.
		#############################################################
		while ($line = <CUMU_FILE>) {

		    if ($line !~ /^B[HQ] /) {
			$entry .= $line;
		    }
		   
		    if ($line =~ /^ID   [^;]+; SV ([^;]+)/) {
			$seqver = $1;  # could be XXX or an actual version number

			if ($seqver =~ /XXX/) {
			    $seqver = "";
			}
		    }
		    elsif ($line =~ /^AC\s+([^\*\s;\.]+)/) {
			$acc = $1;  # overrides acc in ID line, if it exists
		    }
		    elsif ($line =~ /^AC +\* +(\S+)/) {
			$ac_star = $1;
		    }
		    elsif ($line =~ /^SQ +Sequence (\d+) BP;/) {
			$seqlen = $1;
		    }
		    elsif ($line =~ /^BH /) { # Base Quality Values Header
			# Tells us whether it is Phrap or Phred
			$method = substr($line, 5); # discards first 5 chars
		    } 
		    elsif ($line =~ /^BQ /) { # Base Quality Values
			$bqv_info .= substr($line, 5);
		    }

		    # the following is kept separate in case the last line of 
		    # the file contains data (e.g. bqv data rather than //)
		    if ((eof(CUMU_FILE)) || ($line =~ /^\/\/\s*$/)) {

			# reminder:
			# $filename{$acc} = ".000001_$acc_or_ac_star.seq"
			
			if ((defined $filename{$acc}) && (-e $filename{$acc})) {
			    print STDERR "Opening existing file $filename{$acc}\n";

			    ($WRITE_DOT_SEQFILE, $bqv_new_filename, $seq_filename) = open_individual_seq_file($filename{$acc});
			}
			else {
			    # make new file (and store the filename)
			    $file_counter++;
			    ($WRITE_DOT_SEQFILE, $bqv_new_filename, $seq_filename) = open_individual_seq_file("", $project_path, $file_counter, $acc);
			    $verbose && print STDERR "Opening new file $seq_filename\n";
			    $filename{$acc} = $seq_filename;
			}

			print $WRITE_DOT_SEQFILE $entry;

			if ($line !~ /\/\//) {
			    print $WRITE_DOT_SEQFILE "//\n";
			}

			close($WRITE_DOT_SEQFILE);
			
			# if there is bqv data for this entry, save to bqv file of 
			# same prefix as seq file.
			if ($bqv_info) {

			    if (!defined($seqver)) {$seqver = "";}
			    if (!defined($method)) {$method = "";}

			    $bqv_info = "> $acc;$ac_star;$seqlen;$seqver;$method;$project_code\n".$bqv_info."//\n";
			    

			    $verbose && print STDERR "Saving bqv data to $bqv_new_filename\n";
			    open(WRITE_DOT_BQVFILE, ">$bqv_new_filename") || print STDERR "Cannot open $bqv_new_filename";
			    print WRITE_DOT_BQVFILE $bqv_info;
			    close(WRITE_DOT_BQVFILE);
			}

			$seqver = "";
			$seqlen = 0;
			$ac_star = "";
			$method = "";
			$bqv_info = "";
			$entry = "";
		    }
		}
	    }
	}
	else {
	    print STDERR "Cannot open $cumulative_file in order to split it\n";
	}

	unlink($cumulative_file);
    }
}
#############################################################
#
sub copy_and_archive_original_files($\@) {

    my ($file, $filename, $needs_zipping);

    my ($project_path, $ftp_files) = @_;

    foreach $file (@$ftp_files) {

	if (($file =~ /.+\/([^\/\.][^\/]+)$/) && ($file  !~ /\.\~[0-9\.]+\~$/)) {

	    $filename = $1;

	    $needs_zipping = 0;
	    if ($filename !~ /\.(gz|Z|tar)$/) {
		$needs_zipping = 1;
	    }

	    $filename = $filename.".".timeDayDate("yyyy-mm-dd-time");
	    $verbose && print STDERR "Copying $file to $project_path/archive/$filename\n";
	    copy($file, "$project_path/archive/$filename");
	    
	    if ($needs_zipping) {
		system("gzip $project_path/archive/$filename");
	    }
	}
    }
}
#############################################################
#
sub unzip_files($$) {

    my (@zipped_files, $zipped_file, $number_of_seqs, @nonzip_seq_files);
    my (@potential_seq_files, $potential_seq_file, $new_file, @seq_files);
    my (@compressed_files);

    my ($dbh, $project_path) = @_;

    @zipped_files = glob("$project_path/ftp/*.gz");
    @compressed_files = glob("$project_path/ftp/*.Z");
    push(@zipped_files, @compressed_files); # combine .gz and .Z file lists

    foreach $zipped_file (@zipped_files) {
	if ($zipped_file =~ /.+\/([^\.][^\/]+)\.(gz|Z)$/) {
	    $new_file = "$project_path/ftp/.$1";
	    system("gunzip -c $zipped_file > $new_file"); # make .<file> for transfer
	    unlink($zipped_file);
	}
    }

    @zipped_files = glob("$project_path/ftp/*.tar");

    foreach $zipped_file (@zipped_files) {
	if ($zipped_file =~ /.+\/([^\.][^\/]+)\.tar$/) {
	    $new_file = "$project_path/ftp/.$1";
	    system("tar -xf $zipped_file"); # make .<file> for transfer
	    unlink($zipped_file);  # untarring an archive leave the archive file in place (so remove it)
	}
    }

    # make sure gathered files are sequence files
    @nonzip_seq_files = glob("$project_path/ftp/*"); # take files which weren't originally zipped
    @potential_seq_files = glob("$project_path/ftp/.*");
    push(@potential_seq_files, @nonzip_seq_files);


    foreach $potential_seq_file (@potential_seq_files) {

        # if not a backup file or a filename of "." or "..", get filename for moving to uncompressed
	if (($potential_seq_file !~ /\.\~[0-9\.]+\~$/) && ($potential_seq_file !~ /\/\.+$/)) {

	    $number_of_seqs = `grep -c ^ID $potential_seq_file`;
	    
	    if ($number_of_seqs) {
		push(@seq_files, $potential_seq_file);
	    }
	}
    }

    # if none of the files contain sequences, complain in the log
    if (! @seq_files) {

	print STDERR "WARNING: There are no sequence files in $project_path, but there are other files in there which should not be present.\n";
    }

    return(\@seq_files);
}
#############################################################
#
sub tar_up_latest_putff_reports($) {

    my ($counter, $putff_tar_report, $date1, $cmd);
    my ($system_reply, $system_reply2, $tar_filename);

    my $project_path = shift;


    if (glob("$project_path/logs/*.putff")) {
	$counter = 1;
	$date1 = timeDayDate("yyyy-mm-dd");

	$tar_filename = "$project_path/logs/$date1"."_".sprintf("%02d", $counter)."_putff.tar";
	while (-e $tar_filename) {
	    $counter++;
	}

	$putff_tar_report = "$project_path/logs/$date1"."_".sprintf("%02d", $counter)."_putff_report.tar";
	
	if (-e $putff_tar_report) {
	    $cmd = "tar --append -Pf";    # append tar file
	}
	else {
	    $cmd = "tar -cvPf";    # create new tar file
	}
	
	my $latest_tar_report = "$project_path/logs/latest_tar_report";
	$cmd .= " $putff_tar_report $project_path/logs/*.putff > $latest_tar_report";

	$verbose && print STDERR "Tar command = $cmd\n";
	system($cmd);
	unlink($latest_tar_report); # tar cannot be run in quiet mode so grab the output and throw it away
	#unlink("$project_path/logs/*.putff");
    }
    else {
	print STDERR "Warning: $project_path/logs/*.putff not found\n";
    }
}
#############################################################
#
sub remove_lock($$) {

    my ($dbh, $project_path) = @_;

    system("rm $project_path/LOCK");

    if (-e "$project_path/LOCK") {
	print STDERR "WARNING: $project_path/LOCK could not be created (touched) so directory not processed.\n";
    }
}
#############################################################
#
sub create_lock($$) {

    my ($dbh, $project_path) = @_;

    system("touch $project_path/LOCK");

    if (! -e "$project_path/LOCK") {
	print STDERR "WARNING: $project_path/LOCK could not be created (touched) so directory not processed.\n";
    }
}
#############################################################
#
sub get_args(\@) {

    my ($arg, $db, $project_path, $test_mode, $usage, $project_name);
    my ($parent_id);

    my $args = shift;

    $test_mode = 0;
    $project_path = "";
    $project_name = "";
    $parent_id = 0;

    $usage = "Usage: genome_project_pipeline.pl <database> [-test] [-help]\n\n"
	. "This script takes any new unlocked genome projects and adds them to\n"
	. "the specified database, saving both normal and BQV entries.\n\n"
	. "*The script must be run as datalib or LOG_PKG cannot be accessed.\n\n"
	. "<database>   database containing datalib EMBL-bank schema e.g. "
	. '/@enapro or /@devt'."\n"
	. "-test        no files are renamed or deleted\n"
	. "-help        this message\n\n";

    foreach $arg (@$args) {

	if ($arg =~ /\/\@(enapro|devt)/i)  {

            # enapro or devt
	    $db = $1;
	}
	elsif ($arg =~ /\-log_id=(\d+)/) {
	    $parent_id = $1;
	}
	elsif ($arg =~ /\-t(est)?/) {
	    $test_mode = 1;
	}
	elsif (($arg =~ /\-h(elp)?/) || ($arg =~ /\-usage/)) {
	    die $usage;
	}
	elsif ($arg =~ /\-v(erbose)?/) {
	    $verbose = 1;
	}
	elsif ($arg =~ /([^\-]\S+)/) { # project to process
	    $project_name = $1;
	}
    }

    if ($ENV{USER} ne "datalib") {
	die  "Please run this script as datalib (so the logging can work)\n\n$usage";
    }
    elsif ($project_name eq "") {
	die "Please enter project abbreviation as one of the script arguments.\n.$usage";
    }
    elsif (! defined($db)) {
	die  "Please add a database as an argument\n\n$usage";
    }

    if (($test_mode) || ($db =~ /devt/i)) {
	    $DATA_DIR = $DATA_DIR_TEST;
	    $db = 'devt';
	    $test_mode = 1;
    }

    #needs to be done outside the argument loop in case of different ordering of arguments
    $project_path = "$DATA_DIR/$project_name";

    if ($project_path eq "") {
	die "The project name is a required argument when running this script.\n\n$usage";
    }

    return($db, $project_path, $project_name, $test_mode, $parent_id);
}
#############################################################
#
sub get_project_code($$) {

    my ($prj_code, $sth);
    my ($dbh, $project_name) = @_;

    $sth = $dbh->prepare("SELECT project_code FROM cv_project_list WHERE project_abbrev = '$project_name'");
    $sth->execute();
    $prj_code = $sth->fetchrow_array();
    $sth->finish();

    if (! defined($prj_code)) {
	die "The project abbreviation '$project_name', used to call this script does not\n"
	    . "exist in datalib.cv_project_list (Oracle table).\n";
    }

    return($prj_code);
}
#############################################################
#
sub directory_is_locked($$) {

    my (@processes, $lockfile, $grepCmd);
    my ($project_path, $project_name) = @_;

    $lockfile = "$project_path/LOCK";

    if (-e "$project_path/LOCK_MANUAL") {
	# set so directory cannot be processed.
	print STDERR "Manual lock in place for $project_name.  Must be deleted manually\n\n";
	return(1);
    }
    elsif (-e $lockfile) {

	print STDERR "$project_name is locked.  Checking processes...\n";

	$grepCmd = "ps -fu datalib | grep genome_project_pipeline.pl | grep /ebi/production/seqdb/embl/tools/bin/perl -w | grep -v 'ps -fu'";
	@processes = `$grepCmd`;

	if (defined($processes[1])) {
            # project is locked and processes are still running
	    print STDERR "$project_name is still undergoing loading.\n";
	    return(1);
	}
	else {
	    # project is locked but processes have died
	    print STDERR "Removing lock on $project_name\n";
	    system("rm $lockfile");
	    return(0);
	}
    }

    return(0);
}
#############################################################
#
sub make_new_report_file($$) {

    my ($counter, $report_file, $REPORT);
    my ($project_path, $project_name) = @_;

    $counter = 1;
    while (-e "$project_path/reports/$project_name"."_".timeDayDate("yyyy-mm-dd")."_".sprintf("%02d", $counter).".report") {
	$counter++;
    }
    $report_file = "$project_path/reports/$project_name"."_".timeDayDate("yyyy-mm-dd")."_".sprintf("%02d", $counter).".report";
    print STDERR "Creating report at $report_file\n";

    open($REPORT, ">$report_file");#  || die "Cannot open $report_file in write_mode\n";

    return($REPORT, $report_file);
}
#############################################################
#
sub check_if_entry_is_an_update($$$\$) {

    my ($gp_accid, $sth, $acc);
    my ($dbh, $ac_star, $project_code, $warning_list) = @_;

    # convert ac_star into a format the database recognises
    if ($ac_star =~ /^_/) {
	$gp_accid = $project_code.$ac_star;
    } 
    else {
	$gp_accid = $project_code."_".$ac_star;
    }

    $sth = $dbh->prepare("select d.primaryacc# from dbentry d, gp_entry_info g where d.bioseqid = g.seqid and g.gp_accid = ?");
    $sth->bind_param(1, $gp_accid);
    $sth->execute();
    $acc = $sth->fetchrow_array();

    if ($verbose && $acc) {
	print STDERR "Using accession $acc from dbentry for AC * $ac_star\n";
    }

    if (! defined($acc)) {

	# check in the acc-ac_star temporary table
	$sth = $dbh->prepare("select primaryacc# from gp_preassign where gp_accid = ?");
	$sth->bind_param(1, $gp_accid);
	$sth->execute();
	$acc = $sth->fetchrow_array();

	if ($verbose && $acc) {
	    print STDERR "Reusing accession $acc from gp_preassign for AC * $ac_star\n";
	}
    }

    if (! defined($acc)) {
	return("");
    }

    if ($acc =~ /^[A-Za-z]+\d+/) {
	$$warning_list .= "WARNING: $ac_star (accession $acc) is already present in EMBL-bank\n";
    }

    return($acc);
}
#############################################################
#
sub get_num_new_accs_and_updated_accs($\@$) {

    my ($file, $num_accs_required, $acc, $ac_star, %update_accs);
    my ($line, $update_acc, %ac_stars, $acc_in_ac_line, $acc_in_id_line);
    my ($warning_list);

    my ($dbh, $uncompressed_files, $project_code) = @_;

    $num_accs_required = 0;
    $acc = "";
    $ac_star = "";
    $acc_in_id_line = 0;
    $acc_in_ac_line = 0;

    foreach $file (@$uncompressed_files) {

	if ($file  !~ /\.\~[0-9\.]+\~$/) { # if it's not a backup file...

	    if (open(GET_ACC_AND_AC_STAR, "<$file")) {

		while ($line = <GET_ACC_AND_AC_STAR>) {

		    if ($line =~ /^ID\s+([^;]+)/) {
			$acc = $1;
			if ($acc !~ /XX+/) {
			    $acc_in_id_line = 1;
			}
		    }
		    elsif ($line =~ /^AC   ([^\*;]+)/) {
			$acc = $1; # overriding acc from ID line, if present
			$acc_in_ac_line = 1;
		    }
		    #xxxxxx is this right?  Originally $1 slurped up the first dot
		    elsif ($line =~ /^AC \* ([\S]+)(\.\d+)?/) {
			$ac_star = $1;

			#ls -a print STDERR "found ac_star = $ac_star\n";
		    }
		    elsif (($line =~ /^\/\//) || eof(GET_ACC_AND_AC_STAR)) {

			if ($acc =~ /XX+/){
			    $acc = "";
			}

                        # make unique list of ac_stars (to avoid duplications)
			if (! defined($ac_stars{$ac_star})) {
			
			    if ($acc_in_id_line && (!$acc_in_ac_line)) {
				# This clause kicks in if there is an accession in
				# the ID line but not the AC line.  AC line is the important one.
				# Adding acc to this hash will later allow it to be added to AC line.
				$update_accs{$file}{$ac_star} = $acc;
			    }
			    # if there is no acc (since putff will check acc-ac_star pairs)
			    elsif ($acc !~ /[A-Za-z]+\d+/) {

				#print STDERR "acc is not acceptable. Needs to be sought or requested.\n";
				
				$update_acc = check_if_entry_is_an_update($dbh, $ac_star, $project_code, $warning_list);
				#print STDERR "update_acc = $update_acc\n";
				#print STDERR "ac_star = $ac_star\n";

				if ($update_acc eq "") {
				    # there are no accessions associated with the ac_star
				    $ac_stars{$ac_star} = "1";
				}
				else {
				    # if update acc is found, link ac_star to acc
				    $update_accs{$file}{$ac_star} = $update_acc;
				}
			    }
			}
			
			$acc = "";
			$ac_star = "";
			$acc_in_id_line = 0;
			$acc_in_ac_line = 0;
		    }
		}
	    }
	    else {
		die "Could not read $file\n";
	    }
	}
    }

    foreach $ac_star (keys %ac_stars) {
	if ($ac_stars{$ac_star} eq "1") {
	    $num_accs_required++;
	}
    }

    return($num_accs_required, \%update_accs, $warning_list);
}
#############################################################
#
sub add_accs_into_each_file(\@\%\@$$$) {

    my ($file, $line, $entry, $acstar, $acc, $ac_star, $used_acc_element);
    my ($sth_add_preassigned_pair, $changed_AC_field, $update_ac_flag);

    my ($uncompressed_files, $update_accs, $accs, $dbh, $project_code, $logger) = @_;

    # arrange to store each acc-ac_star pair.  Unpon successful loading, 
    # the pair will be removed from this table
    $sth_add_preassigned_pair = $dbh->prepare("insert into gp_preassign (gp_accid, primaryacc#) values (?, ?)");

    $used_acc_element = 0;

    foreach $file (@$uncompressed_files) {

	if (scalar(keys(%{ $$update_accs{$file} }))) {
	    $update_ac_flag = 1;
	}
	else {
	    $update_ac_flag = 0;
	}

	my $var = scalar(@$accs);

	$logger->write_log_with_count("New accessions to be added to split files", "INFO", $var);
	$logger->write_log_with_count("Updated accessions to be added to AC lines", "INFO", scalar(keys(%{$$update_accs{$file}})));

	$verbose && print STDERR "Copying $file to $file.withaccs\n";
	copy($file, "$file.withaccs");
	system("chmod 755 $file.withaccs");

	if ($file !~ /\.\~[0-9\.]+\~$/) { # if not a backup file...
	    open(WRITE_ACCS, ">$file.withaccs") || print STDERR "Cannot write to $file.withaccs\n";
	    if (open(GET_ACC_AND_AC_STAR, "<$file")) {

		while ($line = <GET_ACC_AND_AC_STAR>) {

		    $entry .= $line;

		    if (($line =~ /^\/\//) || (eof(GET_ACC_AND_AC_STAR))) {

			$entry =~ s/\r//g; # removes lots of ctl-M characters which appear in the .withaccs file
			$changed_AC_field = 0;

			# needs a new accession
			if (!defined($acc) || ($acc !~ /^[A-Za-z]+\d+/)) {

			    if ($update_ac_flag) {
				# if entry is an update, add the appropriate accession

				foreach $acstar (keys %{$$update_accs{$file}}) {
				    if ($acstar eq $ac_star) {
					$entry =~ s/\nAC [^\*\n]*\n/\nAC   $$update_accs{$file}{$ac_star};\n/;
					$changed_AC_field = 1;
				    }
				}
			    }
			    
			    if (!$changed_AC_field) {
				if ( defined($$accs[$used_acc_element]) ) {
				    $entry =~ s/\nAC [^\*\n]*\n/\nAC   $$accs[$used_acc_element];\n/;
				    if ($ac_star =~ /^_/) {
					$ac_star = $project_code.$ac_star;
				    }
				    else {
					$ac_star = $project_code."_".$ac_star;
				    }

				    $sth_add_preassigned_pair->bind_param(1, $ac_star);
				    $sth_add_preassigned_pair->bind_param(2, $$accs[$used_acc_element]);
				    $sth_add_preassigned_pair->execute() || dbi_error($DBI::errstr);
				    $sth_add_preassigned_pair->finish();
				    $verbose && print STDERR "inserted preassign pair $ac_star - $$accs[$used_acc_element]\n";

				    $used_acc_element++;
				}
			    }
			}

			print WRITE_ACCS $entry;
			$entry = "";
			$acc = "";
		    }
		    elsif ($line =~ /^ID\s+([^;]+)/) {
			$acc = $1;
		    }
		    elsif ($line =~ /^AC\s+([^;\*\n\r\t \.]+)/) {
			$acc = $1; # overriding acc in ID line, if present
		    }
		    elsif ($line =~ /^AC\s+\*\s+([_A-Za-z0-9]+)(\.\d+)?/) {
			$ac_star = $1;
		    }
		}
	    }
	    else {
		die "Could not read $file\n";
	    }
	    close(GET_ACC_AND_AC_STAR);
	    close(WRITE_ACCS);
	    
	    rename($file.".withaccs", $file);
	}
    }
}
#############################################################
# figure out how many accessions are required, get a whole range 
# and then make replacements within the uncompressed data file
sub add_new_accs_into_compressed_files($$\@$) {

    my ($num_accs_required, $update_accs, @accs, $warning_list);

    my ($dbh, $project_code, $uncompressed_files, $logger) = @_;
    
    ($num_accs_required, $update_accs, $warning_list) = get_num_new_accs_and_updated_accs($dbh, @$uncompressed_files, $project_code);

    if ($num_accs_required) {
	SeqDBUtils2::assign_accno_list($dbh, $num_accs_required, "DS", @accs);
    }

    add_accs_into_each_file(@$uncompressed_files, %$update_accs, @accs, $dbh, $project_code, $logger);

    return($warning_list);
}
#############################################################
#
sub split_file_in_two(\@$\@) {

    my ($num_lines_in_file, $split_at_this_line_num, $new_head_filename, $new_tail_filename);
    my ($entry_tally, $num_entries_to_split_off, $file_to_split, $j, $file_tail_len, @file_num_entries);

    my ($files, $i, $file_num_entries) = @_;

    if ($i) {
	# work out at what point to split file because the other files to be 
	# added to ready_for_processing directory contains x entries too.

	# how many entries in previous files?
	for ($j=0; $j<$i; $j++) {
	    $entry_tally += $$file_num_entries[$j];
	}

	# get number of entries to split off
	$num_entries_to_split_off = $MAX_PROCESSING_SIZE - $entry_tally;
    }
    else {
	$num_entries_to_split_off = $MAX_PROCESSING_SIZE;
    }

    $file_to_split = $$files[$i];

    # create file containing =< 15000 entries (number of entries dependent 
    # on size of any other files taken for processing)
    $split_at_this_line_num = `grep -n '^\/\/' $file_to_split | sed -n "${$num_entries_to_split_off}p" | sed 's/:.*//'`;
    $new_head_filename = ".".$file_to_split.".".timeDayDate("yyyy-mm-dd-time").".head";
    system("head -$split_at_this_line_num $file_to_split > $new_head_filename");
    
    # create file containing those entries which won't be going for processing this time
    $num_lines_in_file = `wc -l $file_to_split`;
    $file_tail_len = $num_lines_in_file - $split_at_this_line_num;
    $new_tail_filename = ".".$file_to_split.".".timeDayDate("yyyy-mm-dd-time").".tail";
    system("tail -$file_tail_len $file_to_split > $new_tail_filename");
    $verbose && print STDERR "Moving $new_tail_filename to $file_to_split\n";
    copy($new_tail_filename, $file_to_split); # overwrite original with beheaded file
    unlink($new_tail_filename);

    return($new_head_filename);
}
#############################################################
#
sub move_entries_to_load_into_position(\@$) {

    my ($num_entries, @files_to_add_to_ready_for_processing, $new_process_file);
    my ($total_num_entries, $i, $j, $file, @file_num_entries);

    my ($files, $project_path) = @_;

    $total_num_entries = 0;

    # find out how many entries are in each input file, now sitting in the uncompressed_with_accs dir
    for ($i=0; $i<@$files; $i++) {

	print STDERR "Looking at $$files[$i]\n";

	if (defined($$files[$i]) && ($$files[$i]  !~ /\.\~[0-9\.]+\~$/)) { # if it's not a backup file...

	    print STDERR "hello100\n";

	    $num_entries = `grep -c ^ID $$files[$i]`;
	    push(@file_num_entries, $num_entries);
	    $total_num_entries += $num_entries;

	    if ($total_num_entries == $MAX_PROCESSING_SIZE) {
		    # copy more than one file
		    for ($j=0; $j<($i+1); $j++) {

			$verbose && print STDERR "Moving $$files[$j] into $project_path/ready_for_processing/\n";
			copy($$files[$j], "$project_path/ready_for_processing/");
			unlink($$files[$j]);
		    }
		    last;
	    }
	    elsif ($total_num_entries > $MAX_PROCESSING_SIZE) {
		print STDERR "hello101\n";

		$new_process_file = split_file_in_two(@$files, $i, @file_num_entries);

		if ($i) {
		    # copy more than one file
		    for ($j=0; $j<$i; $j++) {
			$verbose && print STDERR "Moving $$files[$j] to $project_path/ready_for_processing/";
			copy($$files[$j], "$project_path/ready_for_processing/");
			unlink($$files[$j]);
		    }
		}
		
		$new_process_file =~ /.+\/\.([^\/]+)$/;
		$verbose && print STDERR "Moving $new_process_file to $project_path/ready_for_processing/$1\n";
		copy($new_process_file, "$project_path/ready_for_processing/$1"); #remove leading dot
		unlink($new_process_file);
		last;
	    }
	}
    }

    if ($total_num_entries < $MAX_PROCESSING_SIZE) {
	# move all files over to ready_for_processing directory
	foreach $file (@$files) {
	    if ($file  !~ /\.\~[0-9\.]+\~$/) { # if it's not a backup file...
		$verbose && print STDERR "Moving $new_process_file to $project_path/ready_for_processing/$1\n";
		copy($file, "$project_path/ready_for_processing/");
		unlink($file);
	    }
	}
    }
}
#############################################################
#
sub process_files($$$$$$$$) {

    my (@uncompressed_files, $file, $files, @split_files, $warning_list);
    my (@temp_split_files, $project_code, @ftp_files, @ready_for_processing_files);
    my ($assignment_success, @acc_list, @temp_split_bqv_files, $num_accs_required);
    my ($existing_accs, @uncompressed_with_accs_files, $split_file_found);
    my ($files_to_move);

    my ($dbh, $load_db, $project_path, $project_name, $REPORT, $sth_get_seqver, $logger, $test) = @_;

    $project_code = get_project_code($dbh, $project_name);

    @ftp_files = glob("$project_path/ftp/*");
    if (@ftp_files) {

	copy_and_archive_original_files($project_path, @ftp_files);
	$files_to_move = unzip_files($dbh, $project_path);

	foreach $file (@$files_to_move) {
            # remove leading dot on new file name
	    if ($file =~ /.+\/\.([^\/]+)$/) {
		$verbose && print STDERR "Copying $file to $project_path/uncompressed/$1\n";
		copy($file, "$project_path/uncompressed/$1");
	    }
	    else {
		$verbose && print STDERR "Copying $file to $project_path/uncompressed/\n";
		copy($file, "$project_path/uncompressed/");
	    }

	    unlink($file);
	}
    }

    $warning_list = "";

    # split any files in uncompressed directory
    @uncompressed_files = glob("$project_path/uncompressed/*");
    if (@uncompressed_files) {

	$warning_list = add_new_accs_into_compressed_files($dbh, $project_code, @uncompressed_files, $logger);

	foreach $file (@uncompressed_files) {

	    if ($file  !~ /\.\~[0-9\.]+\~$/) { # if file is not a backup file...
		$verbose && print STDERR "Copying $file to $project_path/uncompressed_with_accs/\n";
		copy($file, "$project_path/uncompressed_with_accs/");
		unlink($file);
	    }
	}
    }

    @uncompressed_with_accs_files = glob("$project_path/uncompressed_with_accs/*");
    if (@uncompressed_with_accs_files) {
	# move-over 15K entries max
	move_entries_to_load_into_position(@uncompressed_with_accs_files, $project_path);
    }

    @ready_for_processing_files = glob("$project_path/ready_for_processing/*");

    print "ready_for processing file 1 from $project_path/ready_for_processing/*: $ready_for_processing_files[0]\n";
    if (@ready_for_processing_files) {
	# files are split and renamed with a dot prefix to the filename
	$verbose && print STDERR "Splitting uncompressed files (containing preassigned accessions in ready_to_process directory)\n";
	split_file_into_bqv_and_normal_entry_files($dbh, $project_path, $project_name, $project_code, @ready_for_processing_files);

        # files in split_seq are renamed by removing the  
	# leading dot in the filename
	@temp_split_files = glob("$project_path/split_seq/.*");
	@temp_split_bqv_files = glob("$project_path/split_bqv/.*");
	push(@temp_split_files, @temp_split_bqv_files);

	foreach $file (@temp_split_files) {

	    if ($file =~ /(.+\/)\.(\d+_[A-Z]+\d+\.(seq|bqv))$/) {
		#print STDERR "1 = $1\n";
		#print STDERR "2 = $2\n";
		$verbose && print STDERR "Moving $file to $1$2\n";
		copy($file, $1.$2);
		unlink($file);
	    }
	}
    }

    # if there are files to load, fire off the load subroutine
    @split_files  = glob("$project_path/split_seq/*");

    $split_file_found = 0;
    foreach $file (@split_files) {
	if ($file !~ /\.\~[0-9\.]+\~$/) { #ignore backup files
	    $split_file_found = 1;
	    print STDERR "found split file\n";
	    last;
	}
    }

    if (! $split_file_found) {
	@split_files = glob("$project_path/split_bqv/*");
    }

    $split_file_found = 0;
    foreach $file (@split_files) {

	print "file in split\n";
	if ($file !~ /\.\~[0-9\.] +\~$/) {
	    $split_file_found = 1;
	    last;
	}
    }

    print STDERR "in process files\n";

    if ($split_file_found) {
	# load sequences and bqvs
	load_entries_into_database($dbh, $load_db, $project_path, $REPORT, $sth_get_seqver, $project_code, $logger, $test, $verbose);
    }
    else {
	print STDERR "no split file found\n";
    }

    return($warning_list);
}
#############################################################
#
sub main(\@) {

    my ($dbh, $REPORT, @bqv_files, $file, $report_file, $database, $project_path);
    my ($parent_id, $logger, $sth_get_seqver, $test_mode, $project_name, $detail_id);
    my ($warning_list);

    my $args = shift;

    # script is called from run_gpscan.pl like this:
    # genome_project_pipeline /@enapro <project_name> <-test>
    # where <project_name> = sangerhs or brassica 
    # and -test is optional

    ($database, $project_path, $project_name, $test_mode, $parent_id) = get_args(@$args);

    ## lock directory so files can be processed
    if (directory_is_locked($project_path, $project_name)) {
	exit;
    }
    else {
	create_lock($dbh, $project_path);
    }

    # make a connection so progress can be logged
    $dbh = DBI->connect( 'dbi:Oracle:'.$database, '', '', {RaiseError => 1, PrintError => 1, AutoCommit => 0} ) || die "Can't connect to database: $DBI::errstr\n ";

#    $project_log_id  = log_start_of_project_processing($dbh, $parent_id, $project_job_id, "$project_name genome project run";);
    $logger = DBLog_test->new(dsn => '/@'.$database,
			 module => 'GPSCAN', 
			 proc   => 'LOADER',
			 parent => $parent_id
			 );

    ($REPORT, $report_file) = make_new_report_file($project_path, $project_name);
    write_report_header($REPORT);

    $sth_get_seqver = prepare_seq_version_sql($dbh);

    # process new and old data
    $warning_list = process_files($dbh, $database, $project_path, $project_name, $REPORT, $sth_get_seqver, $logger, $test_mode);

    close($REPORT);
    # copy to submitter reports directory
    $verbose && print STDERR "Copying $report_file to $project_path/ena_reports/\n";
    copy($report_file, "$project_path/ena_reports/");

    email_submitter_with_report($dbh, $project_path, $project_name, $report_file, $warning_list, $test_mode);

    tar_up_latest_putff_reports($project_path);

    remove_lock($dbh, $project_path);

    $logger->finish();
    $dbh->disconnect;

    housekeeping("$project_path/$project_name/archive", 30, $test_mode);
}

#############################################################
#

main(@ARGV);

