#!/ebi/production/seqdb/embl/tools/bin/perl

#-------------------------------------------------------------------------------
# delete_entry.pl
# deletes entry from database ( cascade from physicalseq )
# 11-SEP-2000  Carola Kanz 
# 07-NOV-2000  Carola Kanz   accepts input file for deleting multiple entries
# 22-JUN-2004  Carola Kanz   added con entries
# 29-JUN-2004  Quan Lin      added warning when deleting an entry that's part of a con entry
#                            added a flag to delete an entry that's part of a con
# 08-DEC-2004  Carola Kanz   added annotated con entries
# 06-FEB-2006  Quan Lin      removed -del flag that removes a CON segment
#                            added a flag -dst to delete rows in accpair table where CON acc 
#                            are secondaries to it's own segments 
#                            removed possibility of using entry name as input
# 13-MAR-2006  Quan Lin      if accession is part of other entries, deletion is not allowed
# 09-JUN-2006  Quan Lin      EMBL entries with sequence version > 1 must not be deleted
#-------------------------------------------------------------------------------------------


use strict;
use DBI;
use DBD::Oracle;
use dbi_utils;

my $usage = "\nUSAGE:     $0 <user>/<passwd>@<db> <accession#>|-f<filename> -dst\n".
            "\nPARAMETER: -f<filename> a file that contains a list of accession#\n".
    "\nOPTION:    -dst: delete rows in accpair table where CON acc are secondaries to it's own segments\n\n";                             

(@ARGV == 2 || @ARGV == 3 ) || die $usage;

my $login = $ARGV[0];

my $file = '';
my $acc = '';
my $delete = '';


if ( $ARGV[1] =~ /^\-f/ ) {
  $file = $';
}
else {
  $acc = $ARGV[1];
  # remove blanks and tabs and convert to upper case
  $acc =~ s/[ \t]//g; $acc = "\U$acc";
}

if ($ARGV[2]){

  if ($ARGV[2] eq "-dst"){

    $delete = "yes";
  }
  else {
    die $usage;
  }
}


### --- if file: open -----------------------------------------------------------
if ( $file ne '' ) {
  open ( IN, $file )    || die ( "can't open $file: $!\n" );
}

### --- login to Oracle ---------------------------------------------------------
my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );


### --- set auditremark ---------------------------------------------------------
dbi_do ( $dbh, 
    "begin auditpackage.remark := 'entry $acc deleted by delete_entry.pl'; end;")
;


if ( $file ne '' ) {
  while ( <IN> ) {
    chomp;
    del_entry ( $_ );
  }
}
else {
  del_entry ( $acc );
}

close ( IN )   if ( $file ne '' );
dbi_logoff ( $dbh );


################################################################################

sub del_entry {
  my $accno = shift;
 
  my ( $dbcode, $seq_version ) = dbi_getrow ( $dbh, 
                                              "select d.dbcode, b.version 
                                                 from dbentry d, bioseq b
                                                where d.primaryacc#='$accno'
                                                  and d.bioseqid = b.seqid");
  
  if ( $dbcode eq 'E' and $seq_version > 1 ){
      print "ERROR: Sequence version of EMBL entry $accno is $seq_version, $accno cannot be deleted.\n";     
      return;
  }

  my $entry_type = dbi_getvalue ( $dbh,
                                  "select entry_type from dbentry
                                   where primaryacc# = '$accno'");
                                 
  
  if ( !defined $entry_type ) {
    print "ERROR: $accno does not exist\n";
    return;
  }

  # check if the accno is part of another entry
  my (%acc_in_other) = check_accno ($accno);

  if (%acc_in_other){

      print "ERROR: $accno is part of the following entries:\n";
      printf "\n%-12s%-5s\n", "Accession", "Status";
      foreach my $acc (keys (%acc_in_other)){
	  printf "%-12s%-5s\n", $acc, $acc_in_other{$acc};
      }
      print "\nPlease update these entries before deleting $accno\n";
      return;
  }
    
  if ( $entry_type != 1 && $entry_type != 4 ) {

    ### find out if the entry to be deleted is part of a con entry

    my $con_seg = dbi_getvalue ($dbh,
			        "SELECT distinct c.seg_seqid
                                 FROM con_segment_list c, dbentry d
                                 WHERE d.bioseqid = c.seg_seqid
                                 AND ( d.primaryacc# = '$accno')");

    if ($con_seg ) {
        
      my ($con_acc_status)  = get_con_acc_status ($con_seg);
      my %con_acc = %$con_acc_status;
      
      print "\nERROR: $accno not deleted because it is part of the following con entry:\n";
      print "\nAccession\tStatus\n";
      
      foreach my $key (keys (%con_acc)){
        print "$key\t$con_acc{$key}\n";
      }	                        
    }
    else {
      delete_entry_from_physicalseq ( $dbh, $accno );
    }
  }
  elsif ( $entry_type == 1 ) {  ## CON entry
    my @primary = check_con_seg ($dbh, $accno);
    my $file_name;
    if (@primary){
        $file_name = "$accno.secondaries";
	open (OUT, "> $file_name") or die "cannot open $file_name:$!";

        if ($delete eq "yes"){
            print OUT "The following secondarie have been deleted from accpair table\n\n";
            print "\nThe deleted secondaries are listed in $file_name\n\n";
        }
        else {
            print OUT "The following secondaries exist in the accpair table\n\n";
            print "\nSecondaries exist in the accpair table are listed in $file_name\n\n";
        }

	foreach my $pri_acc (@primary){
	    
	    if ($delete eq "yes"){
		del_secondary ($pri_acc,$accno);
	        print OUT "$pri_acc - $accno pair deleted from accpair table\n";
	    }
	    else {
		print OUT "$pri_acc - $accno exist in accpair table\n";
	    }
	}
        close (OUT); 
    }
    else {
	print "$accno was not used as secondaries\n\n";
    }
    
    delete_con_entry ( $dbh, $accno );
   
  }
  elsif ( $entry_type == 4 ) {
    delete_anncon_entry ( $dbh, $accno );
  }
}

sub get_con_acc_status {

    my ($con_seg_id) = @_;
    my (%con_acc_status);

    my $sql =  "SELECT d.primaryacc#, d.entry_status
                FROM con_segment_list c, dbentry d
                WHERE d.bioseqid = c.con_seqid
                AND c.seg_seqid = $con_seg_id";
    
    my (@table) = dbi_gettable ($dbh,$sql);

    foreach my $row (@table){

	my ($accno, $status) = @{$row};
        $con_acc_status{$accno}= $status;
    }

    return \%con_acc_status;
}

sub delete_entry_from_physicalseq {
  my ( $dbh, $accno ) = @_;

  ### --- get physeqid ------------------------------------------------------------
  my $physeqid = dbi_getvalue ( $dbh, 
              "SELECT distinct ( b.physeq ) 
                 FROM dbentry d, bioseq b
                WHERE d.bioseqid = b.seqid
                  AND d.primaryacc# = '$accno'");             

  if ( !defined $physeqid ) {
    print "ERROR: cannot delete $accno\n";
  }
  else {
    ### --- delete entry ( cascade from physicalseq )
    dbi_do ( $dbh, "DELETE from physicalseq
                       WHERE physeqid = $physeqid");

    print "entry $accno deleted\n";
      
    dbi_commit ( $dbh );
  }
}

sub delete_con_entry {
  my ( $dbh, $accno ) = @_;

  my $bioseqid = dbi_getvalue ( $dbh,
             "select bioseqid
                from dbentry
               where primaryacc# = '$accno'");
    
  if ( !defined $bioseqid ) {
    print "ERROR: cannot delete $accno\n";
  }
  else {
    ### --- delete entry 
    dbi_do ( $dbh, "DELETE from con_segment_list
                     WHERE con_seqid = $bioseqid" );
    dbi_do ( $dbh, "DELETE from conff
                     WHERE seqid = $bioseqid" );
    dbi_do ( $dbh, "DELETE from bioseq
                     WHERE seqid = $bioseqid" );

    print "entry $accno deleted\n";
      
    dbi_commit ( $dbh );
  }
}

sub delete_anncon_entry {
  my ( $dbh, $accno ) = @_;

  my $physeqid = dbi_getvalue ( $dbh, 
              "SELECT distinct ( b.physeq ) 
                 FROM dbentry d, bioseq b
                WHERE d.bioseqid = b.seqid
                  AND d.primaryacc# = '$accno'");

  my $bioseqid = dbi_getvalue ( $dbh,
             "select bioseqid
                from dbentry
               where primaryacc# = '$accno'");
                  
  if ( !defined $bioseqid || !defined $physeqid ) {
    print "ERROR: cannot delete $accno\n";
  }
  else {
    ### --- delete entry 
    dbi_do ( $dbh, "DELETE from con_segment_list
                     WHERE con_seqid = $bioseqid" );
    dbi_do ( $dbh, "DELETE from conff
                     WHERE seqid = $bioseqid" );
    dbi_do ( $dbh, "DELETE from bioseq
                     WHERE seqid = $bioseqid" );

    dbi_do ( $dbh, "DELETE from physicalseq
                       WHERE physeqid = $physeqid " );

    print "entry $accno deleted\n";
      
    dbi_commit ( $dbh );
  }
}

sub check_con_seg {

    my ( $dbh, $accno ) = @_;

    my $sql = "SELECT a.primary
               FROM accpair a, dbentry d, con_segment_list c
               WHERE a.secondary ='$accno'
               AND d.primaryacc# = a.primary
               AND d.bioseqid = c.seg_seqid 
               AND c.con_seqid = (SELECT db.bioseqid 
                                    FROM dbentry db 
                                   WHERE db.primaryacc# = '$accno')";

    my @primary = dbi_getcolumn($dbh, $sql);

    return @primary;
}

sub del_secondary {

    my ( $primary, $secondary ) = @_;
  
    dbi_do ($dbh, "DELETE FROM accpair WHERE primary = '$primary' and secondary = '$secondary'");
}

sub check_accno {

    my ($accno) = @_;
    my %acc_status;

    my $sql1 = "select bioseqid
                  from dbentry
                 where primaryacc# = '$accno'";

    my ($bioseqid) = dbi_getvalue ($dbh, $sql1);
   
    my $sql2 = "select distinct d.primaryacc#, d.entry_status 
                  from location_tree lt1, 
                       location_tree lt2,
                       seqfeature s, 
                       dbentry d 
                 where lt1.seqid = '$bioseqid' 
                   and lt1.parentid = lt2.locnodeid 
                   and lt2.locnodeid = s.location 
                   and s.bioseqid != '$bioseqid'
                   and d.bioseqid = s.bioseqid";
  
    my (@table) = dbi_gettable ($dbh,$sql2);

    foreach my $row (@table){

	my ($primary_acc, $status) = @{$row};
        $acc_status{$primary_acc} = $status;
    }

    return (%acc_status);
}
