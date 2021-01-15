#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2003
#
#  MODULE DESCRIPTION:
#
#  Inserts a history event into the EMBL database.
#
#  MODIFICATION HISTORY:
#
# $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/dsHistory.pl,v $
# $Date: 2011/11/29 16:33:38 $
# $Author: xin $
#===============================================================================

use strict;
use DBI;
use SeqDBUtils2;
use SeqDBUtils; # get_ds()
use ENAdb;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage =
    "\n PURPOSE: Add a ds-history event directly to the database.\n\n"
  . " USAGE:   $0\n"
  . "          <user/password\@instance>\n"
  . "          -ds=<ds-number> -e=<event-code> <accession> \"<comment>\" -r[eport_only] -quiet -test\n" . "\n"
  . "          -ds=<ds-number> where <ds-number> is ds number relating to the history event\n"
  . "          <accession>     may be provided instead of a ds number\n"
  . "          <webinID>       may be provided instead of a ds number\n"
  . "          -e=<event-code> where <event-code> is one of the standard event codes\n"
  . "                          or text that uniquely describes an event eg 'upd'\n"
  . "          \"<comment>\"     where <comment> is the comment to be added to the history\n"
  . "                          NB use double quotes if the comment contains an apostrophe\n"
  . "          -r[eport_only]  doesn't make changes, just reports the existing history\n"
  . "          -quiet          if all necessary fields are given, command will run quietly\n"
  . "          -test           checks for test vs. production settings\n"
  . "          -help           shows this text\n" . "\n"
  . "    If not provided on the command line, you will be prompted for the comment text.\n\n";

(@ARGV >= 1)         || die $usage;
($ARGV[0] !~ /^-h/i) || die $usage;

my $maxCommentLengthOut   = 130;
my $maxEventNameLengthOut = 19;
my $database              ;
my $dsNo                  = 0;
my $curator;
my $curatorStatus         = 0; # 1 = active
my $eventCode             = 0;
my $comment               = "";
my $quiet                 = 0;
my $test                  = 0;
my $reportOnly            = 0;
my $eventWord             = "";
my $accessionNumber       = "";         # permit query on an AC and use it to find the ds
my $submissionNumber      = "";         # permit query on a  Hx and use it to find the ds

for (my $i = 0 ; $i < @ARGV ; ++$i) {
    if ($ARGV[$i] =~ /^-/) {
        if ($ARGV[$i] =~ /^\-ds=?(\d+)$/) {
            $dsNo = $1;
        } elsif ($ARGV[$i] =~ /^\-ds$/) {
            # we'll get the DS in the next arg
        } elsif ($ARGV[$i] =~ /^\-e=?(\d+)$/) {
            $eventCode = $1;
        } elsif ($ARGV[$i] =~ /^\-e=?(\w+)$/) {
            $eventWord = $1;
        } elsif ($ARGV[$i] =~ /^\-q(uiet)?$/) {
            $quiet = 1;
        } elsif ($ARGV[$i] =~ /^\-r(eport_only)?$/) {
            $reportOnly = 1;
        } elsif ($ARGV[$i] =~ /^\-t(est)?$/) {
            $test = 1;
        } elsif ($ARGV[$i] =~ /^\-h(elp)?$/) {
            die($usage);
        } elsif ($ARGV[$i] =~ /^\-usage$/) {
            die($usage);
        } else {
            die("Do not understand the term $ARGV[$i]\n" . $usage);
        }
    } else {
        # Accept ds number and/or comment to be unflagged
        if ($ARGV[$i] =~ /^\/\@(\w+)$/) {
            $database = $1;
        } elsif ($ARGV[$i] =~ /^\d+$/) {
            $dsNo = $ARGV[$i];
        } elsif ($ARGV[$i] =~ /^(([A-Za-z]{1}\d{5})|([A-Za-z]{2}\d{6})|([A-Za-z]{4}\d{6,7}))$/) {    # normal accessions
            $accessionNumber = uc($ARGV[$i]);
        } elsif ($ARGV[$i] =~ /^[A-Za-z]{4}\d{8,9}$/) {                                              # WGS
            $accessionNumber = uc($ARGV[$i]);
        } elsif ($ARGV[$i] =~ /^(((Dv)|(Hx)|(An)|(SPIN))\d{6,12})$/) {
            $submissionNumber = $ARGV[$i];
        } else {
            $comment = $ARGV[$i];
        }
    } ## end else [ if ($ARGV[$i] =~ /^-/)
} ## end for (my $i = 1 ; $i < @ARGV...

(@ARGV >= 1) || die $usage;

$quiet and open(STDERR, "> /dev/null");

defined($database) || die $usage;

my %attr   = ( PrintError => 0,
	       RaiseError => 0,
               AutoCommit => 0 );

my $dbh = ENAdb::dbconnect($database,%attr)
    || die "Can't connect to database: $DBI::errstr";



# if accession provided, get ds and try and reconcile it to any ds provided in the args
if ($accessionNumber ne "") {
    if (system("get_entry_status.pl /\@$database $accessionNumber") != 0) {
	exit 1 ;
    }
    my $dsFromAc;
    ($dsFromAc, $curator, $curatorStatus) = SeqDBUtils2::get_ds_and_curator($accessionNumber, $dbh);
    if ((!(defined($dsFromAc))) || ($dsFromAc eq "")) {
        $quiet || print "ERROR: $accessionNumber has no ds!\nPerhaps it is a genome_project entry -  try genome_project_admin.pl /\@$database -ac=$accessionNumber\n"; # it should make more of an effort eg check dbentry.dbcode or if project to use modularised functions from genome_project_admin.pl
	exit 2;
    } else {
        if (($dsNo != 0) && ($dsNo != $dsFromAc)) {    # if conflict
            $quiet || print "$accessionNumber -> ds $dsFromAc\n";
            $quiet || print "ERROR: conflict of ds numbers, I'll ignore the one linked to $accessionNumber\n\n";
            $accessionNumber = "";
        } else {                                            # if no problems
            $quiet || print "Accession $accessionNumber -> ds $dsFromAc\n";
            $dsNo = $dsFromAc;
        }
    } ## end else [ if ((!(defined($dsFromAc...
} ## end if ($accessionNumber ne...

# if submission provided, get ds and try and reconcile it to any ds provided in the args
if ($submissionNumber ne "") {
    my $dsFromSubmission = submissionToDs($dbh, $submissionNumber);
    if ((!(defined($dsFromSubmission))) || ($dsFromSubmission eq "")) {
        $quiet || print "ERROR: $submissionNumber is not known as a submission id in the database or has no ds!\n";
    } else {
        if ($dsFromSubmission == 0) {    # if not already defined, use this ds
            $quiet || print "$submissionNumber has no DS!\n";
            $dsNo = $dsFromSubmission;
        } elsif (($dsNo != 0) && ($dsNo != $dsFromSubmission)) {    # if conflict
            $quiet || print "$submissionNumber -> ds $dsFromSubmission\n";
            $quiet || print "ERROR: conflict of ds numbers, I'll ignore the one linked to $submissionNumber\n\n";
            $submissionNumber = "";
        } else {                                                    # if no problems
            $quiet || print "Submission $submissionNumber -> ds $dsFromSubmission\n";
            $dsNo = $dsFromSubmission;
        }
    } ## end else [ if ((!(defined($dsFromSubmission...
} ## end if ($submissionNumber ...

my @eventCodes = get_event_codes($dbh);

if (($eventCode <= 0) and ($eventWord ne "")) {
    $eventCode = eventWordToCode($eventWord);
}

if ( ($dsNo > 0)
    && (!(dsExistsInDb($dbh, $dsNo)))) {
    print "! ds $dsNo isn't in the database !\n";
    $dsNo = 0;
}

while ($dsNo == 0) {
    if ($dsNo = get_ds($test)) {
        $quiet or print "Using current ds ($dsNo)\n";
        next;
    }
    my $response = "";
    print "which ds number (q to quit): ";
    chomp($response = <STDIN>);
    if ($response =~ /^\s*q(uit)?\s*$/i) {
	$dbh->disconnect;
        die "\nScript exited at user's command\n" ;
    }
    if ($response =~ /\s*[dD]?[sS]?\s*(\d+)\s*/) {
        $dsNo = $1;

        if (!(dsExistsInDb($dbh, $dsNo))) {
            $dbh->disconnect;
            die "\nds $dsNo unknown\n";
        }
    } ## end if ($response =~ /\s*[dD]?[sS]?\s*(\d+)\s*/)
} ## end while ($dsNo == 0)

if (!($reportOnly)) {
    $quiet or print "ds: $dsNo";
    while (!($reportOnly)
           && (   ($eventCode < 1)
               || ($eventCode >= @eventCodes))
      ) {

        # List event codes
        print "\n";
        for (my $i = 1 ; $i < @eventCodes ; ++$i) {
            printf "  Code %2d = \"$eventCodes[$i]\"\n", $i;
        }

        print "   r  to report history\n" . "   q  to quit\n";
        my $response = "";
        print "which event code? : ";
        chomp($response = <STDIN>);
        if ($response =~ /^\s*q(uit)?\s*$/i) {
            $dbh->disconnect;
            die "\nScript exited at user's command\n";
        } elsif ($response =~ /^\s*r(eport)?\s*$/i) {
            $reportOnly = 1;
        } elsif ($response =~ /^\s*(\d{1,2}).*$/) {
            $eventCode = $1;
        } else {
            $eventCode = eventWordToCode($response);
        }
    } ## end while (!($reportOnly) && ...
    if (!($reportOnly)) {
        $quiet or print "code   : $eventCode = $eventCodes[$eventCode]\n";

        while ($comment eq "") {
            my $response = "";
            print "what comment (single line <240 characters) (q to quit):\n";
            chomp($response = <STDIN>);
            if ($response =~ /^\s*q(uit)?\s*$/i) {
                $dbh->disconnect;
                die "\nScript exited at user's command\n";
            } elsif (length($response) >= 240) {
                print "! Too long (" . length($response) . " characters) !\n";
                next;
            } else {
                my $illegalCharacterCount = $response =~ tr/ -~/\*/c;
                if ($illegalCharacterCount > 0) {
                    print "! $illegalCharacterCount illegal characters replaced by *'s !\n";
                }
                $comment = $response;
            }
        } ## end while ($comment eq "")
        $quiet or print "comment: \"$comment\"\n";
        $comment =~ s/\'/''/g;

        my $sth = $dbh->prepare(
            "INSERT INTO submission_history ( idno, event_date,  event_code, comments) 
                      VALUES (? , sysdate, ?, ?)");
        $sth->execute($dsNo, $eventCode, $comment)
          || die "inserting new event for ds $dsNo in database failed $DBI::errstr";
    } ## end if (!($reportOnly))
} ## end if (!($reportOnly))

print showDsHistory($dbh, $dsNo, $maxCommentLengthOut);

if ($reportOnly) {
    print "  submissionID: " . dsToSubmission($dbh, $dsNo) . "\n";
    if (!(defined($curator))) {
	($curator,$curatorStatus) = get_curator_from_ds ($dsNo,$dbh);
    }
    if ($curator eq "") {
        print "  assigned to unknown curator\n";
    } else {
        print "  assigned to curator $curator\n";
    }
} else {
    my $confirmation = "-";
    if ($quiet) {
        $confirmation = "y";
        $dbh->commit();
    } else {
        while ($confirmation eq "-") {
            print "Please confirm this is okay [yN]: ";
            chomp($confirmation = <STDIN>);
            if ($confirmation =~ /^\s*y(es)?\s*$/i) {
                $dbh->commit();
                print "New entry added\n";
            } elsif ($confirmation =~ /^\s*(n(o)?)?\s*$/i) {
                $dbh->rollback();
                print "New entry removed\n";
            } else {
                $confirmation = "-";
            }
        } ## end while ($confirmation eq "-")
    } ## end else [ if ($quiet)
} ## end else [ if ($reportOnly)
$dbh->disconnect;
exit();





sub get_event_codes {
    my $dbh = shift;
    my $eventQuery = $dbh->prepare(q{
	select EVENT_CODE, EVENT from event_codes
	});
    $eventQuery->execute
	|| die "Can't get list of event codes: $DBI::errstr";
    my @eventCodes;
    while (my @results = $eventQuery->fetchrow_array) {
	$eventCodes[ $results[0] ] = $results[1];
    }
    $eventQuery->finish;
    return @eventCodes;
}    

sub dsToSubmission {
    my $dbh     = shift;
    my $dsNo    = shift;
    my @webinID = ();
    my $sth     = $dbh->prepare("SELECT webin_id FROM webin_ds WHERE idno = ?");
    $sth->execute($dsNo)
      || die "selecting webinID for ds $dsNo in database failed: $DBI::errstr";
    while (my @row = $sth->fetchrow_array) {
        push(@webinID, $row[0]);
    }
    $sth->finish();
    if (scalar(@webinID) > 0) {
        return join(', ', @webinID);
    } else {
        return "unknown";
    }
} ## end sub dsToSubmission

sub submissionToDs {
    my $dbh = shift;
    my $wid = shift;
    my $dsNo;
    my $sth = $dbh->prepare("SELECT idno FROM webin_ds WHERE webin_id = ?");
    $sth->execute($wid)
      || die "selecting DS for webinid $wid in database failed: $DBI::errstr";
    my @results = $sth->fetchrow_array;
    $sth->finish();
    if (defined($results[0])) {
        $dsNo = $results[0];
    }
    return $dsNo;
} ## end sub submissionToDs

sub letterInfo {
    my $dbh    = shift;
    my $letter = shift;

    my $type;
    my $letterTypeQuery = $dbh->prepare("SELECT title from standard_letters s join letter_details l on s.letter_code = l.letter_code  where l.letter# = ?");
    $letterTypeQuery->execute($letter);
    ($type) = $letterTypeQuery->fetchrow_array;
    $letterTypeQuery->finish;
    $type =~ s/.* //;    # last work only

    my $letterRemarkQuery = $dbh->prepare("select count(*) from letter_remarks where letter# = ?");
    $letterRemarkQuery->execute($letter);
    (my $remarkLines) = $letterRemarkQuery->fetchrow_array;

    my $remark = "";
    if ($remarkLines > 0) {
        $remark = "+REMARK";
    }

    return sprintf "%s Letter #%d %s", $type, $letter, $remark;
} ## end sub letterInfo

sub eventWordToCode {

    # Make file easy by trying to guess the event code from some text
    my $eventWord        = shift;
    my $escapedEventWord = quotemeta($eventWord);
    my $eventCode        = -1;
    my $matches          = 0;
    for (my $i = 0 ; $i < @eventCodes ; ++$i) {
        if ($eventCodes[$i] =~ /$escapedEventWord/i) {
            $matches++;
            print "$eventWord matches Code $i = \"$eventCodes[$i]\"\n";
            $eventCode = $i;
        }
    }
    if ($matches == 1) {
        return $eventCode;
    } else {
        return -1;
    }
} ## end sub eventWordToCode

sub dsExistsInDb {
    my $dbh  = shift;
    my $dsNo = shift;
    my $sth  = $dbh->prepare("SELECT distinct 1 FROM v_submission_details WHERE idno = ?");
    $sth->execute($dsNo)
      || die "select validity of ds $dsNo in database failed: $DBI::errstr";
    my @results = $sth->fetchrow_array;
    $sth->finish();
    if (defined($results[0])) {
        return $results[0];
    }
    return 0;
} ## end sub dsExistsInDb

sub showDsHistory {
    my $dbh                 = shift;
    my $dsNo                = shift;
    my $maxCommentLengthOut = shift;
    if (!(defined($maxCommentLengthOut))) {
        $maxCommentLengthOut = 200;
    }
    my $maxEventNameLengthOut = shift;
    if (!(defined($maxEventNameLengthOut))) {
        $maxEventNameLengthOut = 20;
    }

    my $reply = sprintf "\nds $dsNo has the history:-\n" . "%-12s %-10s %4s %-" . $maxEventNameLengthOut . "s %s\n", "Date", "User", "Code", "Event", "Remark";
    $reply .=
      "-" x
      length(sprintf "\nds $dsNo has the history:-\n" . "%-12s %-10s  %4s %-" . $maxEventNameLengthOut . "s %s\n", "Date", "User", "Code", "Event", "Remark")
      . "\n";

    my $historyQuery = $dbh->prepare(
        "SELECT TO_CHAR(event_date, 'DD-MON-YYYY'), userstamp,  event_code, comments, LETTER#, TO_CHAR(event_date, 'YYYY-MM-DD')
                               FROM SUBMISSION_HISTORY
                              WHERE IDNO = ?
                           ORDER BY TO_CHAR(event_date, 'YYYY-MM-DD'), timestamp");
    $historyQuery->execute($dsNo)
      || die "select history of ds $dsNo in database failed: $DBI::errstr";
    while (my @row = $historyQuery->fetchrow_array) {
        if (!(defined($row[3]))) {
            $row[3] = "";
        } elsif (length($row[3]) > $maxCommentLengthOut) {
            $row[3] = substr($row[3], 0, ($maxCommentLengthOut - 2)) . "...";
        }

        if ((defined($row[4]) && ($row[4] != 0))) {
            if (($row[2] == 12) ||    #letter sent or resent
                ($row[2] == 15)
              ) {
		if ($row[3] =~ /^Sent by \S+$/) { # ie automatic comment
		    $row[3] = letterInfo($dbh, $row[4]);
		} else {
		    $row[3] .= " ". letterInfo($dbh, $row[4]);
		}
            } else {
                if ($row[3] ne "") {
                    $row[3] .= " - ";
                }
                $row[3] .= "Letter# $row[4]";
            }
        } ## end if ((defined($row[4]) ...
        my $codeText = $eventCodes[ $row[2] ];
        if ($codeText eq "Peptide submission passed to SWISS-PROT") {
            $codeText = "Peptide submission";
        } elsif ($codeText eq "Submitter is no longer contactable") {
            $codeText = "Lost submitter";
        } else {
            $codeText =~ s/Submission received$/submission/;
        }
        $codeText =~ s/submission\b/Sub./i;
        $reply .= sprintf "%s  %-11s  %2d %-" . $maxEventNameLengthOut . "s %s\n", $row[0], $row[1], $row[2], substr($codeText, 0, $maxEventNameLengthOut),
          $row[3];
    } ## end while (my @row = $historyQuery...
    $historyQuery->finish();
    return $reply;
} ## end sub showDsHistory
