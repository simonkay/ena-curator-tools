#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/journal_check_align.pl,v 1.11 2011/06/20 09:39:35 xin Exp $
#
#  (C) EBI 2001
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#
#  check every days the citation status
#  every 6 month a reminder letter is send
#  if a citation is steel accepted , unpublished or no plans to publish
#
#
#  MODIFICATION HISTORY:
###############################################################################

#  Initialisation
use strict;
use DBI;
use dbi_utils;
use seqdb_utils;
use SeqDBUtils;

my $exit_status = 0;

my $testing = 1; ## Testing is set if using devt (ie rollback and email(s) go to user not submitter

#print within the log file
print "-- $0 log ------------\n";

# handle the command line.
( @ARGV == 1 ) || die "\n USAGE: journal_check.pl <username/password\@instance>\n\n";
if ($ARGV[0] =~ /enapro/i){
    $testing = 0;
}
else{
    print " Running on $ARGV[0], all transactions will be rolledback and emails sent to you\n";
}

# --- connect to database --------------------------------------------------------
my $dbh = dbi_ora_connect( $ARGV[0] );
$dbh->{LongReadLen} = 50000;
$dbh->{LongTruncOk} = 1;
my $sql = "select  a.alignid, a.alignacc,nvl(a.confidential,'N'),nvl(a.hold_date,''),sd.email_address
       from   align a, v_submission_details sd
       where  a.idno = sd.idno
       and    a.unpublished = 'Y'
       and    a.entry_status = 'S'  
       and    nvl(a.date_reminder,a.first_created) < add_months (sysdate,-6) 
       and    a.first_created > add_months (sysdate,-24) ";
my $sql2 = $dbh->prepare(
         "select ANNOTATION 
            from align_files 
           where alignid=?");
my $sql3 = $dbh->prepare(
         "update align
          set date_reminder = sysdate
          where alignid=?");

my $cursor = dbi_open $dbh, $sql;

while ( my @values = dbi_fetch $cursor) {
    
    my ( $alignid, $alignacc, $confidential, $hold_date, $email_address ) = @values;
    (defined($hold_date)) || ($hold_date = "none");
    my $definition = getDefinition($alignid);
    
    #send letter
    my $msg = "Dear Colleague,"
             ."We received a submission to the Alignment database EMBL-Align from \n"
             ."you for which we have no citation information.\n"
             ."\n"
             ."We can only guarantee that the data is released and that the citation \n"
             ."information is updated, if authors inform us when articles are \n"
             ."published.\n"
             ."\n"
             ."Therefore please enter citation information, and/or permission to \n"
             ."release the entry if it is not already public. \n"
             ."\n"
             ."You may also extend your hold date using this form if the entry is still\n"
             ."confidential.\n"
             ."\n"
             ."ALIGNMENT NUMBER: $alignacc\n";
    
    if ( $confidential eq 'Y' ) {
        $msg .= "HOLD DATE: $hold_date\n";
    }
    
    $msg .= "DEFINITION $definition\n"
           ."\n"
           ."EMBL-Align, Citation update:\n"
           ."============================================================================\n"
           ."Journal: [                                                          ]\n"
           ."\n"
           ."Volume:  [           ]    Pages:  [           ]  Year:  [           ]\n"
           ."\n"
           ."Authors: [                                                          ]\n"
           ."\n"
           ."Title:   [                                                          ]\n"
           ."-------------------------------------------------------------------------------\n"
           ."\n"
           ."If you have not yet published, please check here: [    ]\n"
           ."\n"
           ."If you have no plans to publish, please check here: [     ]\n";
    
    if ( $confidential eq 'Y' ) {
        $msg .= "\n"
	       ."If you want to extend your hold date please enter a new date here (DAY-MON-YEAR):\n"
	       ."[       ]\n";
    }
    
    $msg .= "\n"
           ."If you have any further queries about your alignment please e-mail :\n"
	   ."update\@ebi.ac.uk\n\n";

#############################################################################

    # --- email to submitter  --------------------------------------------------
    my $time = scalar localtime();
    my ( $day, $mon, $mday, $hour, $year ) = split( /\s+/, $time );
    my $subject = "update citation : $mday-$mon-$year ".$definition;
    $subject =~ s/\'/\'/g;
    $subject =~ s/\"/\"/g;
    $subject =~ s/\n//sg;
    my $address = lc $email_address;
    $testing && ($address = $ENV{'USER'}."\@ebi.ac.uk");
    open( MAIL, "| /usr/sbin/sendmail -oi -t" );
    print MAIL "To: $address\n";
    print MAIL "From: <update\@ebi.ac.uk>\n";
    print MAIL "Subject: $subject\n";
    print MAIL $msg;
    close(MAIL);

    # print within the log file
    print "$alignacc\treminder sent to submitter $address\n";

    # then update
    $sql3->bind_param(1, $alignid);
    $sql3->execute || dbi_error($DBI::errstr);
    $testing || dbi_commit($dbh);
}

# --- disconnect from database ---------------------------------------------------
dbi_close($cursor);
if ($testing){
    dbi_rollback($dbh);
}
else{
    dbi_commit($dbh);
}
dbi_logoff($dbh);

sub getDefinition{
    my $alignid = shift;
    my $definition;
    $sql2->bind_param(1, $alignid);
    $sql2->execute || die $sql2->errstr;
    my @annotationLines = split /[\n\r]+/, $sql2->fetchrow;
    foreach my $line (@annotationLines){
	if ($line =~ s/^DE   //){
	    $definition .= "$line ";
	}
    }
    return $definition;
}    


exit($exit_status);
