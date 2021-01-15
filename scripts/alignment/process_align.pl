#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/process_align.pl,v 1.19 2007/07/24 12:30:14 gemmah Exp $
#
#  (C) EBI 2000
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#  
#  before the migration ask for the ds number that datasub have to provide
#  after the migration create the ds number automatically
#  store the information of the info.txt
#
#  store all the file (.aln, .TXT, .dat, .ffl, .notes)
#  under the ds directories   
#  print the next instruction
#
#  MODIFICATION HISTORY:
#
# 24-NOV-2000 lombard      : send a report to datasubs ("next instruction")
#                            change the header
#                            add error message 
# 29-NOV-2000 lombard      : cp the explanation file under the ds directory   
# 15-DEC-2000 lombard      : change path
# 06-JUL-2001 lombard      : added the login in the command line
#                            change ora_utils to dbi_utils
# 21-SEP-2001 lombard      : add modification for migration
# 01-OCT-2001 lombard      : post migration modification:
#                            - change the ds path
#                            - delete the mandatory ds number
#                            - add loadsubinfo.pl script 
#                            - use the oracle sequence to create the ds number
# 04-AUG-2004 lombard      : insert event_code=5 (specific for alignment) in 
#                            the submission_history table
###############################################################################

#  Initialisation

use strict;
use DBI;
use dbi_utils;
use seqdb_utils;
use SeqDBUtils;

my $ds_path ="/ebi/production/seqdb/embl/data/dirsub/ds/"; # production
#my $ds_path ="/ebi/production/seqdb/embl/data/dirsub/ds_test/"; # test
my $clob_path="/ebi/production/seqdb/embl/tools/curators/scripts/alignment/load_clob"; # added in temporarily for back ups
my $webin_path ="/ebi/production/seqdb/embl/data/old_webin/.webin/";

# I could add [ds number] not sure yet about the necessity

# handle the command line. 
( @ARGV == 2 )
    || die "\n USAGE: process_align.pl <username/password\@instance> <webin directory>\n\n";

my $login = $ARGV[0]; 

# default dir is webin dir
my $default_dir= $ARGV[1];

my $message="";
# --- connect to database -----------------------------------------------------

my $session = dbi_ora_connect ($login);
 
# creates a ds number
my $sql = "SELECT dirsub_dsno.nextval FROM dual";
my $ds = dbi_getvalue($session, $sql);

$message .= "ds_$ds\n";

# --- cp the file from webin dir to $path -------------------------------------
my $dsdir = $ds_path.$ds;

mkdir ($dsdir,0777);
if (! (-e $dsdir)) {
    die "\n$dsdir has _not_ been created\n\n";
} else {
    print "\n$dsdir has been created\n\n";
}

sys ("cp ".$webin_path.$default_dir."/alignment.dat ".$ds_path.$ds."/", __LINE__);
sys ("cp ".$webin_path.$default_dir."/alignment.aln ".$ds_path.$ds."/", __LINE__);
sys ("cp ".$webin_path.$default_dir."/alignment.ffl ".$ds_path.$ds."/", __LINE__);
sys ("cp ".$webin_path.$default_dir."/INFO.TXT ".$ds_path.$ds."/", __LINE__);
sys ("cp ".$webin_path.$default_dir."/submitted ".$ds_path.$ds."/", __LINE__);


if (-s $webin_path.$default_dir."/COMMENT.CURATOR") {
    sys ("cp ".$webin_path.$default_dir."/COMMENT.CURATOR ".$dsdir."/", __LINE__);
}

if (-s $webin_path.$default_dir."/citation.cmt") {
    sys ("cp ".$webin_path.$default_dir."/citation.cmt ".$dsdir."/", __LINE__);
}

if (-s $webin_path.$default_dir."/cons.notes") {
    sys ("cp ".$webin_path.$default_dir."/cons.notes ".$dsdir."/", __LINE__);
}

if (-s $webin_path.$default_dir."/Explanation1") {
    sys ("cp ".$webin_path.$default_dir."/Explanation1 ".$dsdir."/", __LINE__);
}

sys ("cp ".$webin_path.$default_dir."/alignment.dat ".$clob_path."/alignment$ds.dat", __LINE__);
sys ("cp ".$webin_path.$default_dir."/alignment.aln ".$clob_path."/alignment$ds.aln", __LINE__);

# -test is ds_test mode
sys ("/ebi/production/seqdb/embl/tools/curators/scripts/loadsubinfo.pl $login -f".$dsdir."/INFO.TXT -ds".$ds, __LINE__);


# fill submission_history table
my $update= "insert into submission_history 
                    (idno, event_date, event_code) 
             values ($ds, sysdate, 5)";

dbi_do($session, $update);
dbi_commit($session);
dbi_logoff($session);

$message .= "to check the data first do:\n";
$message .='$ALIGN/load_align.pl '.$login." ".$ds."\n";

$message .= "if the data is fine, load it into the database:\n";
$message .= '$ALIGN/load_align.pl '.$login." ".$ds." -save\n";

# --- email to datasub --------------------------------------------------------
my ($time)=scalar localtime();
my ($day,$mon,$mday,$hour,$year)=split(/\s+/,$time);
my ($subject) = "Process Alignment DS${ds}: $mday-$mon-$year";
my ($address) = 'datasubs@ebi.ac.uk';
open(MAIL, "|sendmail -oi -t");
print MAIL "To: $address\n";
print MAIL "From: Web Demon <wwwd\@ebi.ac.uk>\n";
print MAIL "Subject: $subject\n"; 
print MAIL $message; 
close (MAIL);
print "alignment processed\n";

