#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# livelist_infoplus.pl
#
# Takes the livelist and adds more info to it such as what happened to a
# particular entry.  The additional info is extracted from the antiload
# reports.
#
# author: Gemma
#
###########################################################################

use strict;
use SeqDBUtils2 qw(rangify);
use DBI;
use LWP::Simple;   
use LWP::UserAgent;
use Data::Dumper;


my $LIVELIST_DIR = '/ebi/production/seqdb/embl/updates/livelist/';
#my $LIVELIST_DIR = '/ebi/production/seqdb/embl/updates/livelist_test/';
my $REPORTS_DIR  = '/ebi/production/seqdb/embl/data/collab_exchange/reports/';

############################################
#

sub expand_range($) {
 
    my ($first_acc, $last_acc, $first_acc_prefix, $last_acc_prefix);
    my ($first_acc_num, $last_acc_num, $i, @acc_list);

    my $acc_range = shift;
   
    if ($acc_range =~ /^[A-Z]+\d+$/) {  # single acc rather than a range
	push(@acc_list, $acc_range."\n");
    }
    else {
	($first_acc, $last_acc) = split("-", $acc_range);

	if ($first_acc =~ /^([A-Z]+)(\d+)/){
	    $first_acc_prefix = $1;
	    $first_acc_num = $2;
	}
	if ($last_acc =~ /^([A-Z]+)(\d+)/){
	    $last_acc_prefix = $1;
	    $last_acc_num = $2;
	}
	
	if ($first_acc_prefix eq $last_acc_prefix) {
	    
	    for ($i=$first_acc_num; $i<($last_acc_num+1); $i++) {
		push(@acc_list, $first_acc_prefix.$i."\n");
	    }
	}
	else {
	    print "Cannot expand range $acc_range because accession prefixes differ\n";
	    push(@acc_list, $acc_range."\n");
	}
    }

    return(\@acc_list);
}

############################################
#

sub add_accs_to_list($$) {

    my ($acc_list);

    my $acc_range = shift;
    my $FH = shift;

    $acc_list = expand_range($acc_range);

    print $FH @$acc_list;
}

############################################
#

sub get_last_updated_date_from_ncbi_or_ddbj($$) {

    my ($url, $userAgent, $req, $result, $rescontent, $update_date);

    my $collab = shift; # 'ddbj' or 'ncbi'
    my $acc = shift;

    $userAgent = LWP::UserAgent->new;
    $userAgent->timeout(1000);

    if ($collab eq 'ncbi') {
	$url = 'http://www.ncbi.nlm.nih.gov/entrez/sutils/girevhist.cgi?val='.$acc.'&log$=seqview';
    }
    else {
        # ddbj
	$url = 'http://getentry.ddbj.nig.ac.jp/search/get_entry?database=ddbj&accnumber='.$acc;
    }

    #print "url = $url\n";

    $req = new HTTP::Request GET => $url;
    $result = $userAgent->request($req);

    if ( $result->is_success ) {
	$rescontent = $result->content;

	if ($collab eq 'ncbi') {
	    if ($rescontent =~ /.+?>Status<.+?>([JFMASOND][a-z]{2}\s\d{}1,2\s\d{4}\s\d{2}:\d{2}\s[APM]{2})</) {
		$update_date = "Last updated at NCBI: $1";
	    }
	    else {
		$update_date = "not found at NCBI";
	    }
	}
	else {
	    # ddbj  
	    if ($rescontent =~ /<PRE>\s+LOCUS\s+.+?(\d{2}\-[A-Z]{3}\-\d{4})/) {
		$update_date = "Last updated at DDBJ: $1";
	    }
	    else {
		$update_date = "not found at DDBJ";
	    }
	}
    }
    else {
	$update_date = "";
    }

    return($update_date);
}

############################################
#

sub look_up_acc_in_db($$$) {

    my ($status, $last_public, $info, $collab_info);

    my $sth = shift;
    my $acc = shift;
    my $collab = shift;

    $sth->execute($acc);
    ($status, $last_public) = $sth->fetchrow_array();

    if (defined($status)) {
	$info = "enapro:".$status;
	
	if (defined($last_public)) {
	    $info .= "\tlast public:$last_public";
	}
    }
    else {
	$collab_info = get_last_updated_date_from_ncbi_or_ddbj($collab, $acc);
	$info = "not in enapro, ".$collab_info;
	$status = "not in enapro";
    }

    $sth->finish;

    return($info, $status);
}

############################################
#

sub grep_for_accession_in_report($) {

    my ($grep_cmd, $dir_num, @reports_subdirs, $antiload_info, $check_files);
    my (@file_list);

    my $acc = shift;


    @reports_subdirs = ('normal',
			'wgs',
			'con',
			'ann',
			'tpa',
			'mga',
			'bqv');
    $dir_num = 0;

    while ((! $antiload_info) && ($dir_num < 7)) {
	$check_files = "$REPORTS_DIR".$reports_subdirs[$dir_num]."/*.report";
	@file_list = glob($check_files);

        # if there are report files present in the dir, 
	# grep for the accession
	if ( @file_list ) {
	    $grep_cmd = "grep -P \";$acc;\" $check_files";
	    $antiload_info = `$grep_cmd`;
	}

	$dir_num++;
    }

    if (!$antiload_info) {
	$antiload_info = "not found in reports";
    }

    return($antiload_info);
}

############################################
#

sub connect_to_db_and_prepare_sql() {

    my ($dbh, $sql, $sth);

     $dbh = DBI->connect('DBI:Oracle:','@enapro','',
            {
            RaiseError => 1, 
            PrintError => 0,
            AutoCommit => 0
            } )
    or die "Could not connect to log database: ".DBI->errstr;

    $sql = "select st.status, db.last_public from dbentry db, cv_status st where db.statusid = st.statusid and db.primaryacc# = ?";
    $sth = $dbh->prepare($sql);

    return($dbh, $sth);
 }

############################################
#

sub process_livelists($) {

    my (@ll_files, $ll_file_pattern, $line, $file, $extra_info, $acc);
    my (@accs, @acc_ranges, $acc_range, $dbh, $db_extra_info, $sth);
    my ($WRITENOTFOUNDNACCS, %status_numbers, $status, $num_accs_checked);
    my ($acc_not_located);

    my $collab = shift;  # 'ddbj' or 'ncbi'

    # get filenames of newest 'missing' and 'zombies' livelists
    $ll_file_pattern = $LIVELIST_DIR.$collab."/livelist_????_???????_*-*-20??";
    @ll_files = `ls -1t $ll_file_pattern |head -2 `;


    if (@ll_files) {
	# connect to database (to get status of accession)
	($dbh, $sth) = connect_to_db_and_prepare_sql();


	foreach $file (@ll_files) {

	    %status_numbers = ();
	    chomp($file);
	    open(READLIST, "<$file");
	    @accs = ();
	    
	    while ($line = <READLIST>) {
		
		if ($line =~ /^[DG]\s+([A-Z]+\d+)/) {    
		    push(@accs, $1);
		}
	    }

	    close(READLIST);

	    @acc_ranges = rangify(@accs);
	    open(WRITELIST, ">$file.extrainfo");
	    open($WRITENOTFOUNDNACCS, ">$file.toDownload");

	    $num_accs_checked = 0;
	    $acc_not_located = 0;

	    foreach $acc_range (@acc_ranges) {

		$extra_info = "not found in reports";

		if ((defined($acc_range)) && ($acc_range =~ /^([A-Z]+\d+)/)) {

		    $acc = $1;
		    $extra_info = grep_for_accession_in_report($acc);
		    chomp($extra_info);
		    $extra_info =~ s/\/ebi\/production\/seqdb\/embl\/data\/collab_exchange/\$COLLAB\/../;

		    if ($extra_info !~ /stored$/) {

			($db_extra_info, $status) = look_up_acc_in_db($sth, $acc, $collab);

			if (!defined($status_numbers{$status})) {
			    $status_numbers{$status} = 0;
			}
			$status_numbers{$status}++;
			
			$extra_info .= "\t".$db_extra_info;
			
			# add to a list for getting from ncbi/ddbj if 
			# not found in enapro
			if ($db_extra_info =~ /^not in.+\-\d{4}/) {
			    add_accs_to_list($acc_range, $WRITENOTFOUNDNACCS);
			}
		    }
		}

		if (defined($acc_range)) {
		    print WRITELIST "$acc_range\t$extra_info\n";
		}

		if ($extra_info eq "not found in reports") {
		    # if extra_info is unchanged, no data was found in the reports
		    $acc_not_located++;
		}

		$num_accs_checked++;
	    }

	    print STDERR "###################################################\n";
	    print STDERR "Livelist file for which extra info is being sought: $file\n";
	    print STDERR "Extra info for ".($num_accs_checked-$acc_not_located)."/".$num_accs_checked." accession ranges has been found\nPlease find them here: $file.extrainfo\n\n";

	    close(WRITELIST);
	    close($WRITENOTFOUNDNACCS);
	}
	
	$dbh->disconnect();
    }
    else {
	# if there are no files
	print "There are no livelist files of the pattern $ll_file_pattern to process\n";
    }
}

############################################
#

sub get_args(\@) {
    
    my ($arg, $collab, $usage);

    my $args = shift;

    $usage = "/ebi/production/seqdb/embl/developer/gemmah/seqdb/seqdb/tools/livelist/perl/livelist_infoplus.pl (ncbi|ddbj)\n\n"
	. "This script reads the missing and zombie livelist files\n"
	. "in  $LIVELIST_DIR/(ncbi|ddbj)\n"
	. "and creates new files from them.  Some files have the .extrainfo\n"
	. "suffix.  Some have the .toDownload suffix. The .extrainfo files contain:\n"
	. " - ranges of accessions from the livelists.  The rest of the info is taken from the first accession in the range:\n"
	. "     - the message in the antiload loading reports (if any)\n"
	. "     - the status of the entry in enapro (if it's there)\n"
	. "     - if the entry is in enapro, the date it was last public\n"
	. "     - if the entry is not in enapro, the date it was last updated at (ncbi|ddbj)\n\n"
	. "The .toDownload file contains a list of the accessions which need\n"
	. "to be downloaded from the NCBI or DDBJ (to be done manually).\n\n";

    foreach $arg (@$args) {

	if (($arg =~ /ncbi/i) || ($arg =~ /ddbj/i)) {
	    $collab = lc($arg);
	}
	elsif (($arg =~ /-h(elp)?/) || ($arg =~ /-usage/)) {
	    die $usage;
	}
    }

    if (! $collab) {
	die "You must supply ddbj or ncbi as an argument.\n";
    }

    return($collab);
}

############################################
#

sub main(\@) {

    my ($collab);

    my $args = shift;

    $collab = get_args(@$args);

    process_livelists($collab);

#    rangify_accessions_with_same_error("livelist_DDBJ_missing_14-5-2009.extrainfo");
}

############################################
#

main(@ARGV);
