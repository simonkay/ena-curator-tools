#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/check_align.pl,v 1.40 2011/06/20 09:39:35 xin Exp $
#
#  (C) EBI 2000
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#
#  Check and Update the Alignment submission:
#       Update table ALIGN if hold date expired
#       Synchronize table ALIGN_DBENTRY with DBENTRY
#       warn a curator if an acc_number is no longer public
#       check wich alignments can be published on the ftp site
#       create the file .dat and .aln
#       send every day a report to datasub 
#
#  MODIFICATION HISTORY:
#
# 21-NOV-2000 lombard      :added the check for the entry status. 
#                           This script removes entries in the ftp
#                           server when confidential = Y or entry_status = D
# 28-NOV-2000 lombard      :change ora_utils to dbi_utils, add the database 
#                           as a first param in the command line.
# 15-DEC-2000 lombard      :change path, bug with sendmail.
# 09-JAN-2001 lombard      :wrong comparison in the first check. 
# 15-JAN-2001 lombard      :change  a.bioseqtype!=1 to  a.bioseqtype!=5
#                           5=PRT 1=DNA 4=RNA.
# 01-FEB-2001 lombard      :bug with the ftp_path
#                           change alignid to alignacc ($sql1)
# 13-FEB-2001 lombard      :change datasubs to update.
# 15-FEB-2001 lombard      :added messages to the mail that align_check.
# 12-MAR-2001 lombard      :if entry_status=D First_created = ''.
# 17-MAY-2001 lombard      :added a message for an updated alignment. 
# 06-JUL-2001 lombard      :added a modification for the citation.
#                           Change the unpublished statment from Y to N 
#                           if a citation becomes published. 
# 16-SEP-2001 lombard      :created the mail subroutin. Instead of a global 
#                           email check_align send individual email to datasubs
# 08-JAN-2002 lombard      :the message 'hold date expired' appear only for 
#                           non 'deleted' alignment (entry_status!=D)
# 21-MAY-2003 lombard      :- the database name is in a variable
#                           - creates different output of a flatfile if 
#                             it's an update or a new entry
# 07-JUN-2003 lombard      :- changed the email's header 
# 26-JAN-2005 lombard      :fixed bug for the the unpublished statment from Y 
#                           to N it checks now for no confidential entry  
# 07-JUN-2005 lombard      :takes in concideration accession with a version 
#                           number
# 31-JAN-2005 Carola Kanz   replaced dropped view v_dbentry_tax by direct query
###############################################################################

#  Initialisation
use strict;
use DBI;
use RevDB;
use dbi_utils;
use seqdb_utils;
use SeqDBUtils;
use sendEmails;

#  Variable declarations
my ($primary, $hold_date, $error, $confidential, $order_in, $status, $sql);
my ($alignacc, $alignid, @values, @alignid, @alignaccs, @not_publish, @row);
my ($sql1, $sql2, $sql3, $opt_connStr, $i);

# handle the command line. 
(@ARGV == 1) || die "\n USAGE: align_check.pl <username/password\@instance>\n\n";
$opt_connStr = $ARGV[0];

my $ftp_path = "/ebi/ftp/pub/databases/embl/align/";
my $unload_align_path = "/ebi/production/seqdb/embl/tools/curators/scripts/alignment/";
my $messages = "";
my $header = "";
my $exit_status = 0;

# --- connect to database --------------------------------------------------------
my $dbh = dbi_ora_connect ($opt_connStr,{AutoCommit => 0, PrintError => 1, LongReadLen=> 1048575});

############################################################################
### update table ALIGN if hold date has expired
$sql = $dbh->prepare(
       "select alignacc
        from align
        where confidential = 'Y'
        and entry_status = 'S'
        and to_char(hold_date, 'YYYYMMDD') < to_char(sysdate,'YYYYMMDD')");

$sql->execute || dbi_error($DBI::errstr);

$sql2 = $dbh->prepare(
        "update align
         set confidential = 'N',
             hold_date = null
         where alignacc = ?");

$i=0;
while (@row = $sql->fetchrow_array) {
    $alignacc = $row[0];

    if (!$i) {
	$messages = "\n-----------------------------------------------\n".
	    " Alignments whose hold dates have expired today\n".
	    "-----------------------------------------------\n";
    }

    $messages .= "$alignacc\n";

    $sql2->bind_param(1, $alignacc);
    $sql2->execute();
    $dbh->commit();

    if ( $@ ) {
	warn "Database error: $DBI::errstr\n";
	$dbh->rollback(); #just die if rollback is failing
    }
    $i++;
}

# email the messages (1/4)
if ($messages ne "") {
    $header = "Alignments whose hold dates have expired today";
    mail(\$messages, $header);
    $messages = "";
}

#############################################################################
### synchronize table ALIGN_DBENTRY with DBENTRY

# this query checks if a primary accession number from align_dbentry has
# the same confidential and status information as in dbentry. The query 
# takes in consideration accessions with or without a version number. 
# The query deletes '.version' (C.f.: substr, decode). 

$sql = $dbh->prepare(
       "select ad.alignid
       ,ad.order_in
       ,d.primaryacc#
       ,d.entry_status
       ,d.confidential
       ,d.hold_date
  from  dbentry d
     ,(
        select nvl(substr(primaryacc#,  1  ,  decode(instr(primaryacc#,'.'), 0 ,length(primaryacc#), instr(primaryacc#,'.')-1 )),'X')
ad_accession
              ,nvl(ad.entry_status,'X') ad_entry_status
              ,nvl(ad.confidential,'X') ad_confidential
              ,ad.alignid
              ,ad.order_in
        from   align a
              ,align_dbentry ad
        where  a.bioseqtype!=5
        and    ad.alignid=a.alignid
        and    a.entry_status!='D'
     ) ad
 where  ad.ad_accession  =  d.primaryacc#
 and    (ad_entry_status !=  d.entry_status or ad_confidential !=  d.confidential)");

$sql->execute || dbi_error($DBI::errstr);

$sql1 = $dbh->prepare(
        "select so.organism
           from dbentry d,
                seqfeature s,
                sourcefeature so
          where d.primaryacc# = ?
            and s.bioseqid = d.bioseqid
            and so.featid = s.featid
            and so.PRIMARY_SOURCE = 'Y'");

$sql2 = $dbh->prepare(
        "select min (name_txt) 
           from ntx_synonym
          where tax_id = ?
            and name_class = 'scientific name'");

$sql3 = $dbh->prepare(
        "update align_dbentry 
         set    confidential = ?,
                entry_status = ?,
                organism = ?,
                description = ?,
                hold_date = ?
         where  alignid = ?
         and    order_in = ?");

while (@values = $sql->fetchrow_array) {
    ($alignid, $order_in, $primary, $status, $confidential, $hold_date) = @values;

    $hold_date = "" if (!defined $hold_date);

    $sql1->bind_param(1, $primary);
    $sql1->execute || dbi_error($DBI::errstr);

    my $tax_id = $sql1->fetchrow_array();

    $sql2->bind_param(1, $tax_id);
    $sql2->execute || dbi_error($DBI::errstr);

    my $organism = $sql2->fetchrow_array();
    if ((defined $organism) && ($organism =~ /'/ )) {
        $organism =~ s/'/''/g;
    }

    # the organism name (description) should have a maximum of 40 characters to fit in the flat file
    substr ($organism, 40) = "" if ( length($organism) > 40 );

    $sql3->bind_param(1, $confidential);
    $sql3->bind_param(2, $status);
    $sql3->bind_param(3, $tax_id);
    $sql3->bind_param(4, $organism);
    $sql3->bind_param(5, $hold_date);
    $sql3->bind_param(6, $alignid);
    $sql3->bind_param(7, $order_in);
    $sql3->execute();
    $dbh->commit();

    if ( $@ ) {
	warn "Database error: $DBI::errstr\n";
	$dbh->rollback(); #just die if rollback is failing
    }
}

#############################################################################
### check the public alignments and warn the curator if an acc_number is 
### no longer public
 
$sql = $dbh->prepare(
       "select a.alignacc, ad.primaryacc#, ad.confidential
        from align a, align_dbentry ad
        where a.bioseqtype != 5 
        and a.confidential = 'N'
        and a.first_public is NOT NULL
        and ad.alignid = a.alignid
        and (ad.entry_status != 'S'
        or ad.confidential = 'Y')");

$sql->execute || dbi_error($DBI::errstr);

$i=0;
while ( @values = $sql->fetchrow_array ) {
    ($alignacc, $primary, $confidential) = @values;

    if (!$i) {
	$messages .= "\n----------------------------------------------\n".
	    " Primary accessions which are no longer public\n".
	    "----------------------------------------------\n";
    }

    $messages .= "  Alignment $alignacc: $primary ";
    $error = ($confidential eq 'Y')?'(confidential)':'(not standard)';
    $messages .= "$error\n";
    $i++;
}

# email the messages (2/4)
 if ($messages ne "") {
     $header = "Primary accessions which are no longer public";
     mail(\$messages, $header);
     $messages = "";
}

#############################################################################
### check the entry_status of each public alignment and remove from the ftp
### if the status = D 
$sql = $dbh->prepare(
       "select alignacc, confidential
        from align
        where first_public is NOT NULL
        and ( entry_status != 'S' or confidential = 'Y' )");

$sql->execute || dbi_error($DBI::errstr);

$sql1 = $dbh->prepare(
	"update align 
         set first_public = ''
         where alignid = ?");

$i=0;
while ( @values = $sql->fetchrow_array ) {
    ($alignacc, $confidential) = @values;
    
    if ((-s $ftp_path.$alignacc.".dat") && (-s $ftp_path.$alignacc.".aln")) {

	sys ("rm ".$ftp_path.$alignacc.".dat",__LINE__);
	sys ("rm ".$ftp_path.$alignacc.".aln",__LINE__);

	my $alignid = $alignacc;
	$alignid =~ s/^ALIGN_0*//;

	$sql1->bind_param(1, $alignid);
	$sql1->execute();
	$dbh->commit();

	if ( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    $dbh->rollback(); #just die if rollback is failing
	}

	if (!$i) {
	    $messages .= "\n---------------------------------------------\n".
		" Alignment accessions removed from FTP server\n".
		"---------------------------------------------\n";
	}

	$messages .= "$alignacc ";
	$error = ($confidential eq 'Y')?'(confidential)':'(status = D)';
	$messages .= "$error.\n"; 
	$i++;
    }
}

# email the messages (3/4)
if ($messages ne "") {
    $header = "Alignment accessions removed from FTP server";
    mail(\$messages, $header);
    $messages = "";
}

#############################################################################
### Change the unpublished statment from Y to N if a citation becomes
### published. 

$sql = $dbh->prepare(
       "select alignid
        from   align 
        where  unpublished = 'Y'  
        and    confidential = 'N'
        and    entry_status = 'S'");

$sql->execute || dbi_error($DBI::errstr);

$sql1 = $dbh->prepare("SELECT annotation from ALIGN_FILES where alignid = ?");
my $unpublished = 'N';

$sql2 = $dbh->prepare("update align set unpublished = ? where alignid = ?");

while ( @values = $sql->fetchrow_array ) {
    $alignid = $values[0];
  
    $sql1->bind_param(1, $alignid);
    $sql1->execute || dbi_error($DBI::errstr);

    my $annotation = $sql1->fetchrow_array();
    my (@annotation) = split (/\n/,$annotation);

    foreach my $line (@annotation) {
	if ($line  =~ /^RL   .+ (\d+).*:(\w+)-(\w+)\((\d+)\)\.\s*$/) {
	    if ($1 == 0 or $2 eq '0' or $3 eq '0' or $4 == 0) {
		$unpublished = 'Y';
		last;
	    }
	}
	if ($line  =~ /^RL   Unpublished./){
	    $unpublished = 'Y';
	    last;
	} 
    }
    if ($unpublished eq 'N') {
	$sql2->bind_param(1, $unpublished);
	$sql2->bind_param(2, $alignid);
	$sql2->execute();
	$dbh->commit();
	
	if ( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    $dbh->rollback(); #just die if rollback is failing
	}
    }

    $unpublished = 'N';
}

#############################################################################
### check which alignments can be published on the ftp site

$sql = $dbh->prepare(
       "select alignid, alignacc
        from   align 
        where  entry_status='S'
        and    confidential = 'N'
        and    first_public is NULL");

$sql->execute || dbi_error($DBI::errstr);

$sql1 = $dbh->prepare(
        "select ad.primaryacc#, ad.order_in, ad.confidential
         from align_dbentry ad, align a 
         where ad.alignid = a.alignid
         and a.bioseqtype != 5 
         and ad.alignid = ?
         and ad.alignseqtype = 'S'
         and (nvl(ad.entry_status,'X') != 'S'
         or  nvl(ad.confidential,'X') = 'Y')");

$sql2 = $dbh->prepare(
	"update align_dbentry 
         set confidential='N',
         entry_status='S'
         where alignid = ?
         and order_in  = ?");

$sql3 = $dbh->prepare(
        "update align 
         set first_public = sysdate
         where alignid = ?");

my $msgWritten;

$i=0;
my $j=0;
my $messages2 = "";
while ( @values = $sql->fetchrow_array ) {
    ($alignid, $alignacc) = @values;

    $sql1->bind_param(1, $alignid);
    $sql1->execute || dbi_error($DBI::errstr);

    my $found = 0;
  
    $msgWritten = 0;
    while ( ( @row = $sql1->fetchrow_array ) ) {
	($primary, $order_in, $confidential) = @row;

	if (!$i) {
	    $messages.= "\n----------------------------------------------------\n".
		" Alignments which can't be published to the ftp site\n".
		"----------------------------------------------------\n";
	    $i++;
	}

        #check on the revision database    
	if ($primary =~ /\.\d+$/) {

	    my ($entry, $killed) = get_primary_entry($primary);  

	    if (!$msgWritten && ((!$entry) || ($killed))) {
          	$messages .= "Problematic primaries found in $alignacc:\n";
		$msgWritten = 1;
	    }

	    if (!$entry) {
		$messages .= "  $primary (not in revision database)\n";
	    } elsif ($killed) {
		$messages .= "  $primary (killed)\n";
	    } else { 
		if (!defined $confidential) { 
	
		    $sql2->bind_param(1, $alignid);
		    $sql2->bind_param(2, $order_in);
		    $sql2->execute();
		    $dbh->commit();

		    if ( $@ ) {
			warn "Database error: $DBI::errstr\n";
			$dbh->rollback(); #just die if rollback is failing
		    }
		}
	    }

        # check on enapro
	} else {

	    if (!$msgWritten) {
          	$messages .= "Problematic primaries found in $alignacc:\n";
		$msgWritten = 1;
	    }
	    
	    if (!defined $confidential) {
		$confidential = ""; 
		$messages .= "  $primary (not found in database)\n";
	    } else {
		$error = ($confidential eq 'Y')?'confidential':'not standard';
		$messages .= "  $primary ($error)\n";
	    }
	}
	$found = 1;
    }
  
    # if no primary entries have been reported as 'bad'
    if ( ! $found ) {
	$sql3->bind_param(1, $alignid);
	$sql3->execute();
	$dbh->commit();

	if ( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    $dbh->rollback(); #just die if rollback is failing
	}

	if (!$j) {
	    $messages2.= "\n----------------------------------------------------\n".
		" Alignments which can't be published to the ftp site\n".
		"----------------------------------------------------\n";
	    $j++;
	}

	if (-s $ftp_path.$alignacc.".dat") {  
	    $messages2 .= "** $alignacc is updated on the ftp site\n"; 
	} else {
	    $messages2 .= "** $alignacc is published on the ftp site\n";
	}

	if (-s $ftp_path.$alignacc.".dat") {
	    sys ($unload_align_path."unload_align.pl $opt_connStr ".$alignacc." -u", __LINE__);          
	} else {
	    sys ($unload_align_path."unload_align.pl $opt_connStr ".$alignacc, __LINE__);   
	}

	sys ($unload_align_path."unload_align.pl $opt_connStr ".$alignacc.' -clustal', __LINE__);
	if (-e $alignacc.".dat") {
	    sys ("mv ".$alignacc.".dat"." ".$ftp_path,__LINE__);
	}
	if (-e $alignacc.".aln") {
	    sys ("mv ".$alignacc.".aln"." ".$ftp_path,__LINE__);
	}
    }
}

# email the messages (4/4)
if ($messages ne "") {
    $header = "Alignment can't be published to the ftp site";
    mail(\$messages, $header);
    $messages = "";
}
if ($messages2 ne "") {
    $header = "Alignment successfully published/updated ftp site";
    mail(\$messages2, $header);
    $messages2 = "";
}

# --- disconnect from database ---------------------------------------------------

dbi_commit($dbh);
dbi_logoff($dbh);

# --- email subroutine -----------------------------------------------------------
# each error messages or update messages should appear in different emails

sub mail {
    my ($messages, $header) = @_;

    my $time = scalar localtime();
    my ($day, $mon, $mday, $hour, $year) = split(/\s+/, $time);
    my $subject = "Alignment check: $mday-$mon-$year - $header";
    
    send_email_with_string_msg("update.email", "Web Demon <wwwd\@ebi.ac.uk>", $subject."\n", $$messages);
}



=head2 get_primary_entry

 Usage   : get_primary_entry($primary_identifier)
 Description: get an entry from  the revision database with the primary identifier
 Return_type :$entry_id= string of the entry related to the primary identifier
 Args    : $primary_identifier= string of the primary identifier

=cut

sub get_primary_entry {
    my ($primary_identifier) = @_;
  
    my ($entry_id, $killed);

    # connect to the revision database
    my $rev_db = RevDB->new('rev_select/mountain@erdpro');
    
    $@ = '';
    eval {
      ($entry_id) = $rev_db->select_entry_id_sequence_acc_no_like($primary_identifier);
      $killed = $rev_db->select_is_killed($primary_identifier);
    };
    
    if ($@) {
      print STDERR "ERROR: $@";
    }

    # disconnect to the revision database
    $rev_db->disconnect();

    return ($entry_id,$killed);
}

exit $exit_status;
