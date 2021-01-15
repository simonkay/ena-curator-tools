#!/ebi/production/seqdb/embl/tools/bin/perl -w

use lib "/ebi/sp/pro3/shared/lib/perl/";
use lib "/ebi/production/seqdb/embl/tools/perllib/";

use strict;
use SWISS::Entry;
use DBI;
use dbi_utils;

#===================================================================================================
# MODULE DESCRIPTION:
#
# The script is used to check cross-references to EMBL in Swiis-Prot and produces reports.
# It's based on the reporter script
# It has following steps:
# 1. read sp release file and update tables
# 2. run queries on the tables
# 3. produce reports
#
#  MODIFICATION HISTORY:
#
#  18-AUG-2005  Quan Lin        Created.
#  04-NOV-2005  Quan Lin        wgs entries included.
#  10-JAN-2006  Quan Lin        modified sql for rpid_m to compare the latest in the bioseq_audit table.
#  07-NOV-2007  Quan Lin        fixed sql for getting deleted proteinID and deleted acc
#  11-FEB-2008  Rasko & Quan    del_pid.sp, del_acc.sp and sec_acc.sp no longer have overlap
#  27-MAY-2008  Quan Lin        moved from ice to anthill
#  26-NOV-2008  Quan Lin        updated for schema change
#  16-OCT-2009  Quan Lin        replaced the sql for populating xrep_genome table as it's too slow
#======================================================================================================

my $in_file   = "/ebi/uniprot/data/wrelease/current";
my $xref_file = "sp.in";
my $out_dir   = "/ebi/production/seqdb/embl/tools/curators/data/sp_xref";

# handle command line

my $usage =
    "\n PURPOSE: checks cross-references between SP and EMBL\n"
  . "          Without using options it produces six reports: del_acc.sp, sec_acc.sp, migr_pid.sp\n"
  . "          rpid_nm.sp, rpid_m.sp, del_pid.sp for sp\n"
  . "          \n\n"
  . " USAGE:   $0 <user/password\@instance> [-migr] [-tax]\n\n"
  . "          <user/password>:  username=spel, please ask for password.\n"
  . "          <instance>:       enapro for production or devt for testing.\n"
  . " OPTIONS:\n"
  . "          [-migr]:                   produce only migr_pid.sp\n"
  . "          [-tax]:                    produce all reports for the tax_id provided, e.g. -tax9606\n";

die $usage if (@ARGV < 1 or @ARGV > 2);

my $login = lc($ARGV[0]);

#die "$usage\n" if ($login !~ /^spel\//);
#xin die $usage unless ($login =~ /\@(enadev|enapro)/);
#die "\nINFO: Please provide the password\n$usage\n" if ($login =~ /^spel\/\@/);

## xin start
my ($user,$pw,$instance);

if( $login =~ /(.*)\/(.*)\@(.*)/)
{
  $user = $1;
  $pw= $2;
  $instance = $3;

  print "login=$login\tuser=$user\tpassword=$pw\tinstance=$instance\n";
}
else{	 die "please use the correct format of user/password\@instance"; }

## xin stop

my $flag = ($ARGV[1]) ? $ARGV[1] : '';

if ($flag ne '' && $flag ne '-migr' && $flag !~ /-tax/) {

    die $usage;
}

my $tax_id;

if ($flag =~ /-tax(\d+)/) {

    $tax_id = $1;
} elsif ($flag =~ /-tax/) {

    die $usage;
}

# the report file names

my ($report_del_acc, $report_sec_acc, $report_migr_pid, $report_rpid_nm, $report_rpid_m, $report_del_pid);

# counter

my %count = (del_acc => 0,
             sec_acc => 0,
             migr    => 0,
             rpid_nm => 0,
             rpid_m  => 0,
             del_pid => 0);

my %stats_report;

if ($tax_id) {

    $report_del_acc  = "del_acc_$tax_id.sp";
    $report_sec_acc  = "sec_acc_$tax_id.sp";
    $report_migr_pid = "migr_pid_$tax_id.sp";
    $report_rpid_nm  = "rpid_nm_$tax_id.sp";
    $report_rpid_m   = "rpid_m_$tax_id.sp";
    $report_del_pid  = "del_pid_$tax_id.sp";
} else {

    $report_del_acc  = "del_acc.sp";
    $report_sec_acc  = "sec_acc.sp";
    $report_migr_pid = "migr_pid.sp";
    $report_rpid_nm  = "rpid_nm.sp";
    $report_rpid_m   = "rpid_m.sp";
    $report_del_pid  = "del_pid.sp";
} ## end else [ if ($tax_id)

# connect to database
#my $dbh = dbi_ora_connect($login);
my $dsn = "dbi:Oracle:$instance";
my $dbh = DBI->connect( $dsn, $user, $pw ) || die "Can't connect to database: $DBI::errstr";
main();

### --- list of subs ---

sub main {
    my $time;
    $time = `date`;
    print "Started at $time\n";
    my $working_dir = make_dir();
    chdir("$working_dir") || die("ERROR: cannot chdir to $working_dir \n$!");

    make_xref_file();
    load_data();

    my ($table_name);

    if ($tax_id) {

        $table_name = "genome";
        $time       = `date`;
        print "started loading xrep_genome at $time\n";
        load_genome_data();
        $time = `date`;
        print "finished loading xrep_genome at $time\n";
    } else {

        $table_name = "sp";
    }

    print "Refreshing wh_migrated_protein_id and wh_deleted_protein_id tables started at $time\n";

    dbi_do($dbh, "begin datalib.wh_protein_id_pkg.refresh;end;");

    dbi_commit($dbh);
    $time = `date`;

    print "finished refreshing the tables at $time\n";
    if ($flag eq '' or $tax_id) {

        report_del_pid($table_name);    #makes 3 reports
        report_migr_pid($table_name);
        report_rpid_nm($table_name);
        report_rpid_m($table_name);
    } elsif ($flag eq "-migr") {

        report_migr_pid($table_name);
    }

    dbi_logoff($dbh);

    if ($flag ne "-migr") {

        report_stats();
    }
    $time = `date`;
    print "Finished producing the reports at $time\nAll reports are ready in the $working_dir directory\n";

} ## end sub main

# parse sp work release file, get relevent info for building input file
sub make_xref_file {

    print "Reading file $in_file ...\n";
    open(IN,  "< $in_file") or die "cannot open file $in_file: $!";
    open(OUT, "> sp.temp")  or die "cannot open file sp_temp: $!";

    # read an entry at a time
    $/ = "\/\/\n";

    while (<IN>) {

        my $entry = SWISS::Entry->fromText($_);

        my $embl_xrefs = $entry->DRs->getObject('EMBL');

        foreach my $xref ($embl_xrefs->elements) {

            if (@$xref[3] eq "JOINED") {

                printf OUT "%s %s %s %s\n", @$xref[1], "-", $entry->AC, $entry->ID;
            } else {
                printf OUT "%s %s %s %s\n", @$xref[1], @$xref[2], $entry->AC, $entry->ID;
            }
        } ## end foreach my $xref ($embl_xrefs...
    } ## end while (<IN>)

    close(IN);
    close(OUT);

    #    system ('grep -v "^[A-Z][A-Z][A-Z][A-Z]" sp.temp > sp.temp1'); # remove wgs entries
    system("sort -u sp.temp > $xref_file");    # remove duplicates

    unlink "sp.temp";
} ## end sub make_xref_file

# load data to temp tables
sub load_data {
    print "Loading data into tables ...\n";

    #truncate tables;
    dbi_do($dbh, "truncate table spel.xrep_sp");
    dbi_do($dbh, "truncate table spel.sp_acc");

    # load data into xrep_sp table
    my $control_file = "sp.ctl";
    my $bad_file     = "sp.bad";
    my $log_file     = "sp.log";
    my $error_file   = "sp.err";

    open(CTL, "> $control_file") or die "cannot open file $control_file: $!";

    print(CTL <<EOF);
LOAD DATA
APPEND INTO TABLE xrep_sp
FIELDS TERMINATED BY " " (
ACC#, 
PID_TEXT nullif (pid_text="-"), 
PRIMARYID, 
SECONDARYID
)
EOF

    close(CTL);

    my $cmd = "sqlldr $login data=$xref_file control=$control_file log=$log_file bad=$bad_file errors=0";
    if (system "$cmd > $error_file 2>&1") {

        die("ERROR: the sqlloader failed.\n" . "  The command issued was:\n$cmd\n" . "  stdout and stderr are collected in '$error_file'\n");
    } else {

        foreach ($control_file, $log_file, $bad_file, $error_file) {
            unlink();
        }
    }

    # load data into sp_acc table

    my $sql = "insert into spel.sp_acc
	      (select distinct primaryid
 	      from spel.xrep_sp)";

    dbi_do($dbh, $sql);
    unlink "$xref_file";
} ## end sub load_data

sub load_genome_data {

    dbi_do($dbh, "truncate table spel.xrep_genome");

    my $sql = 'insert into spel.xrep_genome 
	              (
                        select /*+ NO_MERGE */ *
                          from
                              (
                               select distinct x.acc#,
                                      x.pid_text,
                                      x.primaryid,
                                      x.secondaryid,
                                      s.organism
                                 from SPEL.xrep_sp x,
                                      DATALIB.DBENTRY d,
                                      DATALIB.SOURCEFEATURE s
                                where x.acc# = d.primaryacc# 
                                  and d.bioseqid = s.bioseqid
                                )' . "where organism = $tax_id" . ')';
# NB this query seems to lack sensitivity - querying for a species will omit all sub-species and strains
# and specificity - entries with more than one source will appear for both organisms (maybe intentional)
    dbi_do($dbh, $sql);
} ## end sub load_genome_data

# Creates three reports for no longer public /protein_ids:
# - del_acc.sp the EMBL accession is no longer public and the entry is not secondary to any other entry
# - sec_acc.sp the EMBL accession is no longer public and the entry is secondary to another entry
# - del_pid.sp the EMBL accession is still public
#

sub report_del_pid {

    print "Producing report $report_del_acc ...\n";
    print "Producing report $report_sec_acc ...\n";
    print "Producing report $report_del_pid ...\n";
    my ($name) = @_;

    open(DEL, "> $report_del_acc") or die "cannot open file $report_del_acc:$!";
    open(SEC, "> $report_sec_acc") or die "cannot open file $report_sec_acc:$!";
    open(OUT, "> $report_del_pid") or die "cannot open file $report_del_pid:$!";

    my $del_pid_sql = "select x.primaryid,            -- SP acc
                              x.pid_text,             -- old pid in SP
                              a.acc,                  -- old EMBL acc
                              a.protein_acc ||'.'|| a.version,  --old pid in EMBL
                              d.statusid,
                              max (to_char (a.deletion_time, 'DD-MON-YYYY'))
                         from datalib.wh_protein_id_deleted a
                         join dbentry d on a.acc = d.primaryacc#
                         join spel.xrep_$name x on substr(x.pid_text,1,8) = a.protein_acc
                         group by x.primaryid, x.pid_text, a.acc, a.protein_acc ||'.'|| a.version, d.statusid";

    my $sth = $dbh->prepare($del_pid_sql);

    my $del_acc_sql = "select d.primaryacc#     -- new primary to which the old acc has become secondary
                  from accpair s
                  join dbentry d on d.primaryacc# = s.primary
                  where ? = s.secondary and d.statusid = 4 and d.first_public is not null";

    my $sth2 = $dbh->prepare($del_acc_sql);

    $sth->execute();

    while (my @row = $sth->fetchrow_array) {

        my ($sp_acc, $protein_acc_from_sp, $acc_from_embl, $protein_acc_from_embl, $statusid, $deletion_time) = @row;

        if ($statusid == 4) {
            printf OUT "%-13s%-15s%-15s%-15s%-15s\n", $sp_acc, $protein_acc_from_sp, $acc_from_embl, $protein_acc_from_embl, $deletion_time;
            $count{del_pid}++;
        } else {
            $sth2->execute($acc_from_embl);
            if (my @row2 = $sth2->fetchrow_array) {
                my ($sec_acc) = @row2;
                printf SEC "%-13s%-15s%-15s%-15s%-15s\n", $sp_acc, $acc_from_embl, $sec_acc, $protein_acc_from_sp, $deletion_time;
                $count{sec_acc}++;
            } else {
                printf DEL "%-13s%-15s%-15s%-15s\n", $sp_acc, $acc_from_embl, $protein_acc_from_sp, $deletion_time;
                $count{del_acc}++;
            }
        } ## end else [ if ($statusid == 4)
    } ## end while (my @row = $sth->fetchrow_array)

    print "   There are $count{del_acc} deleted acc in $report_del_acc\n";
    $stats_report{$report_del_acc} = $count{del_acc};
    close(DEL);

    print "   There are $count{sec_acc} secondary acc in $report_sec_acc\n";
    $stats_report{$report_sec_acc} = $count{sec_acc};
    close(SEC);

    print "   There are $count{del_pid} deleted protein ids in $report_del_pid\n";
    $stats_report{$report_del_pid} = $count{del_pid};
    close(OUT);
} ## end sub report_del_pid

# The reports lists all the instances where the protein_id version in Swiss-Prot is different
#to the one in EMBL and the sequence in the EMBL entry has changed for that protein_id CDS range.

sub report_rpid_nm {

    print "Producing report $report_rpid_nm ...\n";
    my ($name) = @_;

    open(OUT, "> $report_rpid_nm") or die "cannot open $report_rpid_nm: $!";

    my $rpid_nm_sql = "select distinct c.acc,
                              x.pid_text,
                              '->',
                              x.PRIMARYID,
                              c.protein_acc || '.' || c.version,
                              decode(fq.featid, null, '-', 'pseudo'),
                              substr(c_a.dbremark, 1, 1),
                              max(c_a.remarktime)
                         from CDSFEATURE c
                             join CDSFEATURE_audit c_a 
                                  on c.protein_acc = c_a.protein_acc    -- cds -> cds_audit
                                 and c.acc = c_a.acc
                              join XREP_$name x on x.acc# = c.acc                     -- acc is same as in UniProt
                              left outer join FEATURE_QUALIFIERS fq on c.featid = fq.featid
                                        and fq.fqualid = 28 -- /pseudo
                         where c.CHKSUM != c_a.CHKSUM -- different sequence
                           and c.protein_acc = substr(x.pid_text, 1,8) -- same pid
                           and c.protein_acc || '.' || c.version != x.pid_text -- different version
                         group by c.acc,
                               x.pid_text,
                               x.PRIMARYID,
                               c.protein_acc,
                               c.version,
                               decode(fq.featid, null, '-', 'pseudo'),
                               substr(c_a.dbremark, 1, 1)";

    my $sth = $dbh->prepare($rpid_nm_sql);
    $sth->execute();

    while (my @row = $sth->fetchrow_array) {

        my ($prim_id, $pid_text, $arrow, $primaryacc, $seq_accid, $pseudo, $dbremark, $remarktime) = @row;

        printf OUT "%-15s%-13s%-4s%-13s%-15s%-6s%-3s%-15s\n", "$prim_id", "$pid_text", "$arrow", "$primaryacc", "$seq_accid", "$pseudo", "$dbremark",
          "$remarktime";
        $count{rpid_nm}++;
    } ## end while (my @row = $sth->fetchrow_array)
    print "   There are $count{rpid_nm} entries in $report_rpid_nm\n";
    $stats_report{$report_rpid_nm} = $count{rpid_nm};

    close(OUT);

} ## end sub report_rpid_nm

# The reports lists all the instances where the protein_id version in Swiss-Prot is different
# to the one in EMBL and the sequence in the EMBL entry has not changed.This was needed because
# at certain points,GenBank had a bug and changed version even though the sequence hadn't changed.

sub report_rpid_m {

    print "Producing report $report_rpid_m ...\n";
    my ($name) = @_;

    open(OUT, "> $report_rpid_m") or die "cannot open $report_rpid_m: $!";

    my $rpid_m_sql = "select distinct c.acc,
                             x.pid_text,
                             '->',
                             x.PRIMARYID,
                             c.protein_acc || '.' || c.version,
                             decode(fq.featid, null, '-', 'pseudo'),
                             substr(c_a.dbremark, 1, 1),
                             max(c_a.remarktime)
                        from CDSFEATURE c 
                             join CDSFEATURE_audit c_a 
                                  on c.protein_acc = c_a.protein_acc    -- cds -> cds_audit
                                 and c.acc = c_a.acc
                             join XREP_$name x on x.acc# = c.acc
                             left outer join FEATURE_QUALIFIERS fq on c.featid = fq.featid
                                        and fq.fqualid = 28 -- /pseudo
                        where c.CHKSUM = c_a.CHKSUM -- same sequence
                          and c.protein_acc = substr(x.pid_text, 1, 8) -- same pid
                          and c.protein_acc || '.' || c.version != x.pid_text -- different version
                          and c_a.remarktime = (select max(c_a2.remarktime)
                                                   from CDSFEATURE_AUDIT c_a2
                                                   where c_a2.featid = c_a.featid)
                        group by c.acc,
                                 x.pid_text,
                                 x.PRIMARYID,
                                 c.protein_acc,
                                 c.version,
                                 decode(fq.featid, null, '-', 'pseudo'),
                                 substr(c_a.dbremark, 1, 1)";

    my $sth = $dbh->prepare($rpid_m_sql);
    $sth->execute();

    while (my @row = $sth->fetchrow_array) {

        my ($prim_id, $pid_text, $arrow, $primaryacc, $seq_accid, $pseudo, $dbremark, $remarktime) = @row;

        printf OUT "%-15s%-13s%-4s%-13s%-15s%-6s%-3s%-15s\n", $prim_id, $pid_text, $arrow, $primaryacc, $seq_accid, $pseudo, $dbremark, $remarktime;
        $count{rpid_m}++;
    }
    print "   There are $count{rpid_m} entries in $report_rpid_m\n";
    $stats_report{$report_rpid_m} = $count{rpid_m};
    close(OUT);
} ## end sub report_rpid_m

# This reports lists all EMBL accession numbers in Swiss-Prot which are now secondary to another
# EMBL accession number where the protein_id has been maintained in the transition. The new primary
# EMBL accession number and the protein_id is tracked at version level.

sub report_migr_pid {

    print "Producing report $report_migr_pid ...\n";
    my ($name) = @_;
    my $arrow = '->';
    open(OUT, "> $report_migr_pid") or die "cannot open $report_migr_pid: $!";

    my $migr_pid_sql = "select x.primaryid,                     --SP acc
                               x.pid_text,                      -- old pid
                               a.protein_acc ||'.'|| a.version, -- new pid
                               a.old_acc,                       -- old EMBL acc
                               a.acc,                           -- new EMBL acc
                               to_char (a.migration_time, 'DD-MON-YYYY')
                          from datalib.wh_protein_id_migrated a
                          join spel.xrep_$name x on
                                    (substr(x.pid_text,1,8) = a.protein_acc and x.acc# <> a.acc)";

    my $sth = $dbh->prepare($migr_pid_sql);

    $sth->execute();

    while (my @row = $sth->fetchrow_array()) {

        my ($prim_id, $pid_text, $pid_new, $primaryacc_old, $primaryacc_new, $timestamp) = @row;

        printf OUT "%-12s%-15s%-5s%-15s%-15s%-5s%-15s%-13s\n", $prim_id, $pid_text, $arrow, $pid_new, $primaryacc_old, $arrow, $primaryacc_new, $timestamp;
        $count{migr}++;
    }
    print "   There are $count{migr} migrated protein ids in $report_migr_pid\n";
    $stats_report{$report_migr_pid} = $count{migr};
    close(OUT);
} ## end sub report_migr_pid

sub make_dir {

    my $time = `date +"%Y%b%d"`;
    $time =~ s/\n//g;
    my $working_dir = "$out_dir/$time";

    if (!-e "$working_dir") {

        mkdir "$working_dir", 0775 or die "cannot make dir $working_dir: $!";
    }

    return ($working_dir);
} ## end sub make_dir

sub report_stats {

    my $time = `date +"%Y%b%d"`;
    $time =~ s/\n//g;
    my $file;

    if ($tax_id) {

        $file = "${time}_stats_${tax_id}.sp";
    } else {

        $file = "${time}_stats.sp";
    }

    open(OUT, "> $file") or die "cannot open file $file:$!";

    print OUT "stats for the files:\n";
    print OUT "----------------------\n";

    foreach my $file (keys(%stats_report)) {

        if ($tax_id) {

            printf OUT "%-22s%-10s\n", "$file", "$stats_report{$file}";

        } else {

            print OUT "$file\t$stats_report{$file}\n";
        }
    } ## end foreach my $file (keys(%stats_report...

    close OUT;
} ## end sub report_stats
