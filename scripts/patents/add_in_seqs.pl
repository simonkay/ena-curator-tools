#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/add_in_seqs.pl,v 1.2 2009/01/22 14:17:10 gemmah Exp $
#
#
#===============================================================================

use strict;

#---------------------------------------------------------------

sub get_seq_from_ftp_file($$$$) {

    my ($line, $uc_title, $uc_author, $search_title, $seq);
    my ($search_author, $check_title, $find_entry, $found_entry);

    my $ftpfile = shift;
    my $title = shift;
    my $author = shift;
    my $seq_num = shift;

    $uc_author = uc($author);
    $uc_title = uc($title);
    $uc_title = quotemeta($uc_title);

    $check_title = 0;
    $found_entry = 0;
    $find_entry = 0;

    #print "$uc_author, $uc_title\n";

    open(FTPFILE, "<$ftpfile") || die "Cannot find $ftpfile\n";

    while ($line = <FTPFILE>) {

	if ($found_entry) {

	    if ($line =~ /^(     [A-Za-z ]+)/) {
		$seq .= $1."\n";
	    }
	    elsif ($line =~ /\/\//) {
		return($seq);
	    }
	}
	elsif ($find_entry) {

	    if ($line =~ /^AC   [A-Z0-9]{13}_$seq_num;/) {
		$found_entry = 1;
		$find_entry = 0;
	    }
	}
	elsif ($line =~ /^\(XII\)  INVENTOR NAME: $uc_author/i) {
	    $check_title = 1;
	}
	elsif (($check_title) && ($line =~ /^\(XIII\) TITLE: $uc_title/i)) {
	    $find_entry = 1;
	}
	elsif ($line =~ /\-{3}NEW ENTRY\-{5}/) {
	    $check_title = 0;
	}

    }

    close(FTPFILE);
}

#---------------------------------------------------------------

sub main($) {

    my ($ftpfile, $check_for_seq, $title, $author, $sequence_num);
    my ($first_author_retrieved, $title_retrieved, $line, $seq);
    my ($acc, $corrected_entries);

    my $emblfile = shift;

    if (!defined($emblfile)) {
	die "This script requires the input of an embl file whose parent (with the same file prefix) is present in /ebi/ftp/private/epo/public\n";
    }
    elsif ($emblfile =~ /([^\/]+\.s25)\.embl$/) {
	#$ftpfile = "/ebi/ftp/private/epo/public/".$1;

        # using .substd file because the author name is less likely to contain
	# non-english characters
	$ftpfile = "/ebi/production/seqdb/embl/data/patents/data/datasubs/archive/".$1.".substd";
    }
    else {
	die "Entered file has an unrecognised style of file name.  A filename style of e200851_n.s25.embl is expected.\n";
    }


    open(EMBLFILE, "<$emblfile") || die "Cannot open $emblfile\n";

    open(WRITEEMBLFILE, ">$emblfile".".withseqs") || die "Cannot open $emblfile".".withseqs"."\n";


    $check_for_seq = 0;
    $sequence_num = 0;
    $corrected_entries = 0;

    while ($line = <EMBLFILE>) {

	if ($line =~ /^ID   ([A-Z]+\d+);/) {
	    $acc = $1;
	    $first_author_retrieved = 0;
	    $title_retrieved = 0;
	    $sequence_num = 0;
	    $check_for_seq = 0;

	    $seq = "";
	    $title = "";
	    $author = "";
	    print WRITEEMBLFILE $line;
	}
	elsif ($check_for_seq) {

	    if ($line =~ /[A-Za-z]+/) {
		print WRITEEMBLFILE $line;
		$check_for_seq = 0;
	    }
	    elsif ($line =~ /\/\//) {

		$seq = get_seq_from_ftp_file($ftpfile, $title, $author, $sequence_num);
		$corrected_entries++;

		#print "seq = $seq\n";
		print "correcting $acc\n";

		print WRITEEMBLFILE $seq.$line;
	    }
	}
	elsif ($line =~ /^SQ   Sequence 0 /) {
	    $check_for_seq = 1;
	    print WRITEEMBLFILE $line;
	}
	elsif (($line =~ /^RA   (\S+)/) && (!$first_author_retrieved)) {
	    $author = $1;
	    $first_author_retrieved = 1;
	    print WRITEEMBLFILE $line;
	}
	elsif (($line =~ /RT   "([^"\n\r]+)/) && (!$title_retrieved)) {
            $title = $1;
	    $title_retrieved = 1;
	    print WRITEEMBLFILE $line;
	}
        elsif ($line =~ /^DE   Sequence (\d+) /) {
	    $sequence_num = $1;
	    print WRITEEMBLFILE $line;
	}
        else {
  	    print WRITEEMBLFILE $line;  
        }
    }


    close(EMBLFILE);
    close(WRITEEMBLFILE);


    print "\n$corrected_entries entries have been corrected inside $emblfile.withseqs\n";
}

main($ARGV[0]);
