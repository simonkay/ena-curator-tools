#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# Little script to update clobs: to be run manually - make sure you change
# the $database variable and ds directory when updating other ds's.
#
#===============================================================================

use strict;
use DBD::Oracle qw (:ora_types);
use DBI;
use dbi_utils;

################################################################################

sub read_file {

    my ($file, $variable) = @_;
    open( IN, "<$file" )
	or die "Cannot read $file: !$\n";
    $$variable = do{local $/; <IN>};
    close(IN);
}

################################################################################

sub main {

    my $seqalign = "";
    my $clustal = "";
    my $ds_path = "/ebi/production/seqdb/embl/data/dirsub/ds/70216";
    my $database = '/@devt';

    read_file ("${ds_path}/alignment.dat_new", \$seqalign);
    read_file ("${ds_path}/alignment.aln_new", \$clustal);


    my $dbh = dbi_ora_connect ($database);

    my $sql = "update DATALIB.ALIGN_FILES 
                      set SEQALIGN = ?, CLUSTAL = ? where alignid = 1173";

    my $stmt = $dbh->prepare($sql);

    $stmt->bind_param(1, $seqalign, {ora_type => ORA_CLOB, ora_field=>'seqalign'});
    $stmt->bind_param(2, $clustal,  {ora_type => ORA_CLOB, ora_field=>'clustal'});
    
    $stmt->execute();

    dbi_commit($dbh);
    dbi_logoff($dbh);
}

################################################################################

main;
