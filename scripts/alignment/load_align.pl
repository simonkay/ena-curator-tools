#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/load_align.pl,v 1.35 2007/12/20 10:08:44 gemmah Exp $
#
#  (C) EBI 2000
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#
#  load an alignment files into the database
#  USAGE: load_align.pl <ds number> [-save]
#  checks alignment files
#  interactive report for curator
#
#  MODIFICATION HISTORY:
# 21-NOV-2000 lombard      : fill entry_status = S in the ALIGN table
# 27-NOV-2000 lombard      : change ora_utils to dbi_utils, add the database 
#                            as a first param in the command line
# 15-DEC-2000 lombard      : save ALIGN_000000.dat file in the ds directory
#                            add a check for the directory
#                            if the submittor is in the ds directory, don't
#                            need to move the ALIGN_000000.dat file.
#                            die -> bail(cf dbi file)
# 05-JAN-2001 lombard      : bug with bioseqtype, add ($1 eq 'RNA')
# 09-JAN-2001 lombard      : add bioseqtype=2 for RNA
# 15-JAN-2001 lombard      : change bioseqtype 5=PRT 1=DNA 4=RNA
# 28-JAN-2001 lombard      : add protein stat to fill the align_dbentry table
# 09-FEB-2001 lombard      : restrict description to 40 caracters
# 20-FEB-2001 lombard      : define the tax_id as an integer
#                            problem with ' for the description 
# 02-MAR-2001 lombard      : modification for the protein alignment 
#                            the description and the acc number 
#                            are not mandatory ($3 optional)                  
# 21-JUN-2001 lombard      : save the check list within a file (align.check)
#                            added a number in front of each acc. number or
#                            error messages (represent the column order_in 
#                            in the table align_dbentry)
# 06-JUL-2001 lombard      : added a modification for the citation
#                            when a citation is unpublished or accepted, 
#                            the unpublished column (in the align table) is set
#                            to 'Y'.
#                            if a citation is 'no plan to publish' 
#                            then it is set to 'O'.
#                            if the citation is 'published' 
#                            then it is set to 'N'.
# 01-OCT-2001 lombard      : post migration modification:
#                            - hold date line
#                            - ds path
# 25-APR-2002 lombard      : rewrote the code and added subroutin
#                            added mail send to submitter when informations 
#                            are loaded 
# 08-OCT-2002 lombard      : do not use of the oracle procedure 'load_clob'
#                            load the clob from memory instead
# 10-OCT-2002 lombard      : added RaiseError
# 08-MAY-2003 lombard      : added journal spelling check before loading.
#                            load_align check if the journal name is spelled
#                            like a NLM abbreviation (or EMBL abbreviation).
# 21-MAY-2003 lombard      : merged 3 sql queries for journal into one
#                            put the output of the journal comparaison in 
#                            the file 'load.check'
# 01-JUL-2004 lombard      : reconized NUC in the ID line
#                            reconized issue number in a citation and pages 
#                            number can be [a-zA-Z0-9_] characters
###############################################################################

#  Initialisation

use Cwd; #library wich contain cwd()
use strict;
use DBD::Oracle qw (:ora_types);
use DBI;
use dbi_utils;
use SeqDBUtils;

my $opt_connStr;
my $opt_ds;
my $opt_save;

usage ();

# constant
my $ds_path = "/ebi/production/seqdb/embl/data/dirsub/ds/$opt_ds";
if ($opt_connStr =~ /devt/i){
    $ds_path = "/ebi/production/seqdb/embl/data/dirsub/ds_test/$opt_ds";
}
my $unload_align_path = "/ebi/production/seqdb/embl/tools/curators/scripts/alignment/";
my $clob_path = $unload_align_path."load_clob";
my $webin_path = "/ebi/production/seqdb/embl/data/old_webin/.webin/";
my $default_dir="";
my ($accnos,$id);

### create an align_id numbers ###
 
# --- connect to database -----------------------------------------------------

my $session = dbi_ora_connect ($opt_connStr);

# --- create the acc number and the id

if ($opt_save && $opt_save eq "-save") {
    ($id, $accnos) = create_acc_number($session);
}

# --- parse alignment.ffl -----------------------------------------------------

my %align_ff_info = parse_aln_ffl ("$ds_path/alignment.ffl");

#--- create clob file ---------------------------------------------------------

if ($align_ff_info{annotation}) {
    $align_ff_info{annotation} =~ s/'/''/g; #'

    open (ANN, ">$ds_path/annotation${opt_ds}.aln")  || bail ("can't open ${ds_path}/annotation${opt_ds}.aln: $!");
    print ANN $align_ff_info{annotation};
    close (ANN)  || die ("can't close ${ds_path}/annotation${opt_ds}.aln: $!");
}

if ($align_ff_info{feature}) {
    $align_ff_info{feature} =~ s/'/''/g; #'

    open (FEA, ">$ds_path/features${opt_ds}.aln")  || bail ("can't open ${ds_path}/features${opt_ds}.aln: $!");
    print FEA $align_ff_info{feature};
    close (FEA)  || bail ("can't close ${ds_path}/features${opt_ds}.aln: $!");
}

if ($opt_save && $opt_save eq "-u") {
    # --- update of the alignment from webin_align directory
  
    my $webinId = parse_submitted_file();
    $default_dir = "*:$webinId";
        
    sys ("cp ".$webin_path.$default_dir."/alignment.dat $ds_path/alignment.dat", __LINE__);
    sys ("cp ".$webin_path.$default_dir."/alignment.aln $ds_path/alignment.aln", __LINE__);
}

# --- SQL request -------------------------------------------------------------

### fill ALIGN table
if ($opt_save && $opt_save eq "-save") {

    load_align_info($session, $id ,$accnos, %align_ff_info);
    
### fill ALIGN_FILES
    my $annotation = "";
    my $features = "";
    my $seqalign = "";
    my $clustal = "";
    

    if (-s $ds_path."/annotation${opt_ds}.aln") {
        read_file ("${ds_path}/annotation${opt_ds}.aln", \$annotation);
    }

    if (-s $ds_path."/features${opt_ds}.aln") {
        read_file ("${ds_path}/features${opt_ds}.aln", \$features);
    }
    
    read_file ("${ds_path}/alignment.dat", \$seqalign);
    read_file ("${ds_path}/alignment.aln", \$clustal);
    
    $session->{RaiseError} = 1;

    eval {
        insert_clob ($session, $id, \$annotation, \$features, \$seqalign, \$clustal);
    };
    
    if ($@) {
        warn "Transaction aborted because $@";
        dbi_logoff($session);
    }

    $session->{RaiseError} = 0;   
}

### ALIGN_DBENTRY

open (CHK,">$ds_path/load.check") || die "$ds_path/load.check can not open: $!\n";
check_journal_name(\*CHK, $session, %align_ff_info);

for (my $index =0 ;$index <= $#{$align_ff_info{order_in}};$index++) {
    
    my %aligndb_info = align_dbentry_info(\*CHK, $session, $index, %align_ff_info);

### fill ALIGN_DBENTRY table
    
    if ($opt_save && $opt_save eq "-save") {
        load_aligndb_info($session, $index, $id, \%aligndb_info, \%align_ff_info);
    }
}
close (CHK);

# --- delete files database ---------------------------------------------------

if ($opt_save && $opt_save eq "-save") {
    
    dbi_commit($session);
    
    print "ds:$opt_ds Alignment:$accnos is loaded into the database ($opt_connStr).\n";
    my $pwd= cwd();
    
    sys ($unload_align_path.'unload_align.pl '.$opt_connStr.' '.$accnos, __LINE__);
    if ($pwd ne $ds_path) {
        sys ("mv ".$accnos.".dat"." ".$ds_path, __LINE__);
    }
    
    send_email();  
}

# --- disconnect from database ------------------------------------------------

dbi_logoff($session);

###############################################################################
#--- subroutine ---------------------------------------------------------------

sub usage{

    my $usage_msg= "\n USAGE: $0 <username/password\@instance> <ds number> [-save | -u]\n".  
        "   -save:  load all information in the database.\n".
        "   -u: update both the .aln and .dat files in the DS". 
        " directory and the .aln and .dat files in the load". 
        " clob directory from the webin_align directory\n\n";
    
    # handle the command line. 
    ( @ARGV >= 2 && @ARGV <= 3 )|| die "$usage_msg";
    
    $opt_connStr=$ARGV[0];
    $opt_ds = $ARGV[1];
    
    if ( @ARGV == 3){
        $opt_save = $ARGV[2];
        $opt_save = lc ($opt_save);
        if (($opt_save ne "-save") && ($opt_save ne "-u")){
            print " Error: wrong argument";
            print "$usage_msg";
            exit;
        }
    }  
}

# select next ALIGN_accno from the datbase sequence (alignid)
# return an id (number) and the accession number (string) 
sub create_acc_number{

    my ($session )=@_;
    my ($call) = "select 'ALIGN_'
              || substr ( to_char ( alignid.nextval,'099999' ), 2 )
              from dual";
    my ($acc) = dbi_getvalue($session, $call);
    $id = $acc;
    $id =~ s/ALIGN_//;
    $id =~ s/^0*//;
    return $id, $acc;
}

# parses the submitted file from the webin directory
# then return the webin accession number
sub parse_submitted_file{

    my $webinId="";
    # --- open file ---  
    open (IN, "$ds_path/submitted")  || die ("can't open $ds_path/submitted are you sure you entered the correct ds?");
    # --- parse the file ---
    while (<IN>) {
        if ( /^Webin-Align.+:(An\d+)/) {
            $webinId=$1;
        }
    }
    close (IN)  || bail ("can't close $ds_path/submitted: $!");
    return $webinId; 
}

#open the ds file and parse the .ffl file
#the function return a hash with all the flatfile information 
sub parse_aln_ffl{
 
    my ( $path ) = @_;
    my %ff_info = ();
    my ($abbrev) = "";
    my ($flag)=0;
    my $journal_name = "";
    my ($acc, $pacc, $alignseqtype, $desc);
    # initialisation
    $ff_info{'hold_date'} = "";
    $ff_info{'confidential'} = 'N';
    $ff_info{'unpublished'} = 'N';
    $ff_info{'annotation'} = "";
    $ff_info{'feature'} = "";
    $ff_info{'description'} = [];
    $ff_info{'primaryacc'} = [];
    $ff_info{'seqtype'} = [];
    $ff_info{'order_in'} = [];
    $ff_info{'seqname'} = [];
    $ff_info{'journal_name'} = [];

    # --- open file ---------------------------------------------------------------

    open (IN, "$path")  || die ("can't open $path are you sure you entered the correct ds?");

    # --- parse the file ----------------------------------------------------------

    while (<IN>) {
        
        if ( (/^DE/ .. /^CC/) || (/^CC/ .. /^XX/) ) {
    $ff_info{annotation} .= $_;} 
        
        if ( /^ID   ALIGNMENT\s+\S+;\s+(\S+);\s+(\d+)\s+symbols \((\d+) sequences\)/ ){
            if ($1 eq 'DNA' or $1 eq 'NUC') {
                $ff_info{'bioseqtype'} = 1; #DNA
            } elsif ($1 eq 'RNA') {
                $ff_info{'bioseqtype'} = 4; #RNA
            } else {
                $ff_info{'bioseqtype'} = 5; #protein
            }

            $ff_info{'symbols'} = $2;
            $ff_info{'numseq'} = $3;
        }
        # hold date 
        elsif ( /^\*\*   Hold_Date = (\S+)/ or 
                /^HD \* confidential (\S+)/) {
            $ff_info{'hold_date'} = $1;
            $ff_info{'confidential'} = 'Y';
        }
        #citation
        elsif (/^RL   (.+) (\d+).*:(\w+)-(\w+)\((\d+)\)\.\s*$/) {
            if ($1) {
                $journal_name = $1;
                $journal_name =~ s/ +$//g;
                push (@{$ff_info{'journal_name'}},$journal_name);
            }

            if ($2 == 0 or $3 eq '0' or $4 eq '0' or $5 == 0) {
                $ff_info{'unpublished'} = 'Y';
            }
        }    
        elsif (/^RL   Unpublished.\s*$/) {
            $ff_info{'unpublished'} = 'Y';
        }
        #No plans to publish. become Unpublished. in the database
        elsif (/^RL   Unpublished. [No Plans]/ or /^RL   No plans to publish./)
        {
            s/No plans to publish./Unpublished./;
            s/Unpublished. [No Plans]/Unpublished./;
            $ff_info{'unpublished'} = 'O';
        }
        elsif (/^SO   (\d+)\s+(\S+)\s+(\S+)?\s+/) {
            push (@{$ff_info{order_in}},$1);
            $abbrev = $2;
            $acc = $3;
            $abbrev =~ s/'/''/g; #'
            push (@{$ff_info{seqname}},$abbrev);

            if($ff_info{'bioseqtype'} != 5) {
                if ($acc eq 'CONSTRUCTED') {
                    $alignseqtype = 'C';
                    $desc = substr($_,39);
                    $desc =~ s/\s+$//;
                    $desc =~ s/'/''/g; #'
                    $pacc="";
                } elsif ($acc eq 'CONSENSUS') {
                    $alignseqtype = 'Z';
                    $desc = substr($_,39);
                    $desc =~ s/\s+$//;
                    $desc =~ s/'/''/g; #'
                    $pacc="";
                } else {
                    $alignseqtype = 'S';
                    $desc = "";
                    $pacc = $acc;
                }
            } else {
                $alignseqtype = 'P';
                $pacc = substr($_,26,12);
                $pacc =~ s/\s+$//;
                $desc = substr($_,39);
                $desc =~ s/\s+$//;
                $desc =~ s/'/''/g; #'
            }
            push (@{$ff_info{'description'}},$desc);
            push (@{$ff_info{'primaryacc'}},$pacc);
            push (@{$ff_info{'seqtype'}},$alignseqtype);
        }
        elsif (/^FT\s+(.*)?$/) {
            $ff_info{'feature'} .= $_ ;
        }
    }
    
    close (IN)  || bail ("can't close $ds_path: $!");
    
    return %ff_info;
    
}

# sql which insert all information in ALIGN oracle table
sub load_align_info{

    my ($session, $id, $acc,  %ff_info)=@_;
    my ($time)= scalar localtime();
    my ($day,$mon,$mday,$hour,$year)=split(/\s+/,$time);
    $mon = uc ($mon);
    
    my ($sql) = "INSERT INTO ALIGN
                     ( ALIGNID,
                       ALIGNACC,
                       BIOSEQTYPE,
                       ENTRY_STATUS,
                       CONFIDENTIAL,
                       IDNO,
                       SYMBOLS,
                       NUMSEQ,
                       UNPUBLISHED,
                       FIRST_CREATED,
                       HOLD_DATE)
               VALUES ( $id,
                       '$acc',
                       $ff_info{bioseqtype},
                       'S',
                       '$ff_info{confidential}',
                       '$opt_ds',
                       $ff_info{symbols},
                       $ff_info{numseq},
                       '$ff_info{unpublished}',
                       to_date ('$mday-$mon-$year','DD-MON-YYYY' ),
                       to_date ( '$ff_info{hold_date}', 'DD-MON-YYYY' ))";

    dbi_do( $session, $sql );
}

# sql which insert all information in ALIGN_DBENTRY oracle table
sub  load_aligndb_info{

    my ($session, $index, $id, $aligndb_info_ref, $align_info_ref) = @_;

    my ($sql) = "INSERT INTO ALIGN_DBENTRY
                        ( ALIGNID,
                          ORDER_IN,
                          SEQNAME,
                          ALIGNSEQTYPE,
                          PRIMARYACC#,
                          ENTRY_STATUS,
                          CONFIDENTIAL,
                          HOLD_DATE,
                          ORGANISM,
                          DESCRIPTION)
                   VALUES ( $id,
                         ${$$align_info_ref{order_in}}[$index],
                         '${$$align_info_ref{seqname}}[$index]',
                         '${$$align_info_ref{seqtype}}[$index]',
                         '${$$align_info_ref{primaryacc}}[$index]',
                         '$$aligndb_info_ref{status}',
                         '$$aligndb_info_ref{confidential}',
                         '$$aligndb_info_ref{hold_date}',
                         decode ($$aligndb_info_ref{tax_id}, 0, null, $$aligndb_info_ref{tax_id} ),
                         '$$aligndb_info_ref{organism}')";

    dbi_do( $session, $sql );
}

sub read_file {
    my ($file, $variable) = @_;
    open( IN, "<$file" )
	or die "Cannot read $file: !$\n";
    $$variable = do{local $/; <IN>};
    close(IN);
}

sub insert_clob {
    my ( $session,$id,$annotation,$features,$seqalign,$clustal) = @_;
    
    my $stmt = $session->prepare (
          "INSERT INTO DATALIB.ALIGN_FILES (
          ALIGNID,
          ANNOTATION, 
          FEATURES, 
          SEQALIGN, 
          CLUSTAL) 
       VALUES (?, ?, ?, ?, ?)");

    $stmt->bind_param (1, $id);
    $stmt->bind_param (2, $$annotation, {ora_type => ORA_CLOB, ora_field=>'annotation'});
    $stmt->bind_param (3, $$features, {ora_type => ORA_CLOB, ora_field=>'features'});
    $stmt->bind_param (4, $$seqalign, {ora_type => ORA_CLOB, ora_field=>'seqalign'});
    $stmt->bind_param (5, $$clustal, {ora_type => ORA_CLOB, ora_field=>'clustal'});
    
    $stmt->execute ();
}

# sql request which search for the submitter e-mail 
sub search_email{ 

    my ($email_address);

    my($session, $ds) = @_;
    
    my $sql_mail = "SELECT s.email_address
                  FROM   v_submission_details s, align a
                  WHERE  s.idno = a.idno
                  AND    a.idno = $ds";
    
    my (@results) = dbi_gettable($session, $sql_mail);

    my $row = $results[0];
    if (defined($$row[0])) {
	$email_address = $$row[0];
    }

    if (!(defined($email_address))){
	print STDERR "No email address found in v_submission_details for ds $ds\n"
	    ."trying the old submission_details\n";	
	$sql_mail = "SELECT s.email_address
                  FROM   submission_details s, align a
                  WHERE  s.idno = a.idno
                  AND    a.idno = $ds";
    
	$email_address = dbi_getvalue ($session, $sql_mail);
    }
    if (!(defined($email_address))){
	print STDERR "No email address found in submission_details for ds $ds\n";
    }
    return $email_address;  
}

# send an email to the submitter and save the email in the ds directory
sub send_email {
   
    #letter message 
    my $msg="
Dear Colleague,

Thank you for your recent alignment submission. This submission has
been assigned the following accession number:

$accnos

We suggest you cite this number when referring to the corresponding
alignment in publications or in communications to us.

";

    if ($align_ff_info{confidential} eq 'Y') {
        $msg .= "Your alignment will be released on the $align_ff_info{hold_date}.";
    }

    $msg .= "
Please note that it will take 2 days for the data to be fully available
on both the FTP site and via SRS.

Data can be retrieved after release by the following methods:

- Alignment data with ALIGN prefix accession numbers are available in
the EMBL-Align database - a databank of SRS.
Instructions on retrieval and querying EMBL-Align can be found at
 http://www3.ebi.ac.uk/Services/webin/help/webin-align/align_SRS_help.html

- EBI FTP server: by anonymous FTP from ftp.ebi.ac.uk in directory
pub/databases/embl/align

- EBI File server: by sending an e-mail message to
netserv\@ebi.ac.uk including the line HELP ALIGN or GET
ALIGN:$accnos.dat for EMBL format or GET
ALIGN:$accnos.aln for Clustal W format.

- EBI WWW server: URL ftp://ftp.ebi.ac.uk/pub/databases/embl/align/

Thank you for using Webin-Align!

Flatfile
----------------------------------------------------------------------
";

  
# --- email to submitter  --------------------------------------------------
    my ($subject) = "Alignment notification $accnos";

# define submitter email address  
    my ($sub_email_address) = lc search_email($session,$opt_ds);
    
    open (MAIL, "| /usr/sbin/sendmail -oi -t");
    print MAIL "To: $sub_email_address\n";
    print MAIL "From: Datasubs <datasubs\@ebi.ac.uk>\n";
    print MAIL "Subject: $subject\n"; 
    
    open (MSG,">$ds_path/email_sent.dat") || die "email_sent.dat not created:$!\n";
    print MSG $msg;
    print MAIL $msg; 
    
    open (DAT,"$ds_path/${accnos}.dat") || die "$ds_path/${accnos}.dat not found:$!\n";
    while (<DAT>) {
        print MSG;
        print MAIL;
    }
    
    close (DAT);
    close (MSG);
    close (MAIL); 
    
    print "mail sent\n";

}

# check the taxonomy for all accession numbers in the alignment  
# print out report : number of sequence, scientific name of the organism, 
#                    and status of the node (deleted, confidential, standard)
# create a file report in the ds directory
# return hash with all the taxonomy information for align_dbentry table
sub align_dbentry_info {

    my ($FH, $session, $index, %align_ff_info)=@_;
    my %aligndb_info = ();
    
    if (${$align_ff_info{primaryacc}}[$index] eq '') {
        $aligndb_info{organism}=${$align_ff_info{description}}[$index];
        $aligndb_info{tax_id}=0;
        $aligndb_info{status}="";
        $aligndb_info{confidential}="";
        $aligndb_info{hold_date}="";
        print $FH "${$align_ff_info{order_in}}[$index] constructed / consensus\n";
        print "${$align_ff_info{order_in}}[$index] constructed / consensus\n";
    } else {
        my $primary_identifier = ${$align_ff_info{primaryacc}}[$index];
        $primary_identifier =~ s/\.\d+$//; 
        my $sql_dbentry_info="select entry_status, 
                           confidential, 
                           hold_date
                           from dbentry  
                           where primaryacc# = '$primary_identifier'";
        my $cursor=dbi_open $session,$sql_dbentry_info;
        ($aligndb_info{status},$aligndb_info{confidential},$aligndb_info{hold_date})=dbi_fetch $cursor;
        dbi_close $cursor;
        
        #protein case
        if ($align_ff_info{'bioseqtype'} == 5) {
            
            print "${$align_ff_info{description}}[$index]\n";
            $aligndb_info{organism}=${$align_ff_info{description}}[$index];
            $aligndb_info{tax_id}=0;
            $aligndb_info{status}="";
            $aligndb_info{confidential}="";
            $aligndb_info{hold_date}="";
        }
        elsif (!defined $aligndb_info{status}) {
            print $FH "${$align_ff_info{order_in}}[$index] ${$align_ff_info{primaryacc}}[$index] doesn't exist\n";
            print "${$align_ff_info{order_in}}[$index] ${$align_ff_info{primaryacc}}[$index] doesn't exist\n";
            $aligndb_info{organism}=${$align_ff_info{description}}[$index];
            $aligndb_info{tax_id}=0;
            $aligndb_info{status}="";
            $aligndb_info{confidential}="";
            $aligndb_info{hold_date}="";
        }
        else {
            my $sql_get_taxid = "SELECT so.organism
                   FROM dbentry d, seqfeature s, sourcefeature so
                   WHERE d.primaryacc#= '$primary_identifier'
                   AND d.bioseqid = s.bioseqid
                   AND s.featid = so.featid 
                   AND so.PRIMARY_SOURCE = 'Y'";
#                    AND ( so.focus = 'Y'
#                    OR  ( so.focus is null 
#                    AND s.order_in = (select min(s2.order_in)
#                                   from seqfeature s2, sourcefeature so2 
#                                   where s.bioseqid = s2.bioseqid 
#                                   and s2.featid = so2.featid )
#                                   AND not exists(select 1 from seqfeature s3,sourcefeature so3
#                                                  where s.bioseqid = s3.bioseqid 
#                                                  and s3.featid = so3.featid
#                                                  and so3.focus = 'Y' )))";

            $aligndb_info{tax_id} = dbi_getvalue($session, $sql_get_taxid);

            my $sql_get_science_name = "select min (name_txt) 
                                    from ntx_synonym
                                    where tax_id = $aligndb_info{tax_id}
                                    and name_class = 'scientific name' ";

            $aligndb_info{organism} = dbi_getvalue($session, $sql_get_science_name);

            # the organism name should have a maximum of 40 characters to fit in the flat file
            substr ($aligndb_info{organism},40)="" if ( length($aligndb_info{organism}) > 40 );
            print $FH "${$align_ff_info{order_in}}[$index] $aligndb_info{organism} \n";
            print "${$align_ff_info{order_in}}[$index] $aligndb_info{organism} \n";
            $aligndb_info{organism} =~ s/'/''/g; #'
            #initialise hold_date if not defined 
            if (!defined $aligndb_info{hold_date}) {$aligndb_info{hold_date} = ""}; 
            
            # check the status
            if ($aligndb_info{status} ne 'S'){
                print "${$align_ff_info{order_in}}[$index] ${$align_ff_info{primaryacc}}[$index] is not a standard entry\n";
                print $FH "${$align_ff_info{order_in}}[$index] ${$align_ff_info{primaryacc}}[$index] is not a standard entry\n";
            }
            
            if ($aligndb_info{confidential} eq 'Y'){
                print "${$align_ff_info{order_in}}[$index] ${$align_ff_info{primaryacc}}[$index] is a confidential entry\n";
                print $FH "${$align_ff_info{order_in}}[$index] ${$align_ff_info{primaryacc}}[$index] is a confidential entry\n";
            }
        }
    }
    return %aligndb_info;
}

sub check_journal_name {
    my ($FH, $session, %align_ff_info) = @_;
    my @alignid_list = ();
    my $issn;
    
    for (my $index =0 ;$index <= $#{$align_ff_info{'journal_name'}};$index++) {  
        compare_journal_name($FH, $align_ff_info{'journal_name'}[$index], $session) ;
    }
}

sub query_journal_table {
    my ($session,$name) = @_;
    my $cursor;
    my $nlm_abbrev = "";
    my $embl_abbrev = "";
    my $issn;
    my $sql_query = "select distinct cv.ISSN# , cv.NLM_ABBREV,  cv.EMBL_ABBREV
                     from JOURNAL_SYNONYM js, CV_JOURNAL cv
                     where (js.JOURNAL_SYN = '$name'
                       or cv.NLM_ABBREV = '$name'
                       or cv.EMBL_ABBREV = '$name'
                       or cv.FULL_NAME =  '$name')
                     and cv.ISSN# = js.ISSN#(+)
";

    $cursor=dbi_open $session,$sql_query;
    ($issn,$nlm_abbrev,$embl_abbrev)=dbi_fetch $cursor;
    dbi_close $cursor;
    
    return ($issn,$nlm_abbrev,$embl_abbrev);
}

sub compare_journal_name {
    
    my ($FH,$journal_name,$session ) = @_;
    my $nlm_abbrev = "";
    my $embl_abbrev = "";
    my $issn;
    
    ($issn,$nlm_abbrev,$embl_abbrev) = query_journal_table($session,$journal_name);
    if (!$issn) {
        print $FH "\nthe journal: \'$journal_name\' doesn't exist\n";
        print "\nthe journal: \'$journal_name\' doesn't exist\n";
    } elsif ($nlm_abbrev and ($nlm_abbrev ne $journal_name)) {
        print $FH "\nissn: $issn\n";
        print $FH "the journal name is \'$journal_name\', it should be $nlm_abbrev \n"; 
        print "\nissn: $issn\n";
        print "the journal name is \'$journal_name\', it should be $nlm_abbrev \n"; 
    } elsif (!$nlm_abbrev and ($embl_abbrev ne $journal_name)) {
        print $FH "\nissn: $issn\n";
        print $FH "the journal name is \'$journal_name\', it should be $embl_abbrev \n";
        print "\nissn: $issn\n";
        print "the journal name is \'$journal_name\', it should be $embl_abbrev \n";
    }   
}
