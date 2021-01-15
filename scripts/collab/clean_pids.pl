#!/ebi/production/seqdb/embl/tools/bin/perl
#
#

#use lib '/ebi/services/tools/seqdb/perllib';
use strict;
use DBI;
use dbi_utils;

my $EXT = '.uniq';
my $LOG_EXT = '.report';

main ();

sub main {
   #
   #
   #
   my (%OPT) = read_command_line ();

   open (REPORT, ">$OPT{file_name}${LOG_EXT}") or die ("Can't open '$OPT{file_name}${LOG_EXT}' for writing/\n$!\n");

   my ($dbh, $cursor) = init_db ($OPT{connection});
   
   if (1 == $OPT{flatfile}) {
      clean_file ($OPT{file_name}, \*REPORT, $dbh, $cursor);

   } else {
      open (LIST, "<$OPT{file_name}") or die ("Can't open '$OPT{file_name}' for reading/\n$!\n");

      while (my $fname = <LIST>) {
         chomp ($fname);
         clean_file ($fname, \*REPORT, $dbh, $cursor);
      }

      close (LIST);
   }

   dbi_logoff ($dbh);

   close (REPORT);

}


sub clean_file {
   #
   #
   #

   my ($fname, $report_fh, $dbh, $cursor) = @_;

   unless (-f ($fname)){
      print ($report_fh "\nERROR: ${fname} does not exist\n");
      return;
   }

   unless (open (IN, "<${fname}") ){
      print ($report_fh "\nCan't open '${fname}' for reading/\n$!\n");
      return;
   }

   unless (open (OUT, ">${fname}${EXT}") ){
      print ($report_fh "\nCan't open '${fname}${EXT}' for writing/\n$!\n");
      close (IN);
      return;
   }

   my $accno = get_accno (\*IN, \*OUT, $report_fh);

   unless ($accno){
      close_failure (\*IN, \*OUT, "${fname}${EXT}");
      return;
   }

   print ($report_fh "\n${fname}  AC: $accno\n");

   print_until_feattable (\*IN, \*OUT);

   my $pids_ref = get_protein_ids ($cursor, $accno);
   
   unless (print_clean_feattable (\*IN, \*OUT, $report_fh, $pids_ref) ){
      close_failure (\*IN, \*OUT, "${fname}${EXT}");
      return;
   }

   print_the_rest (\*IN, \*OUT);

   close (OUT);
   close (IN);
}


sub close_failure {
   #
   #
   #
   my ($in_fh, $out_fh, $fname) = @_;

   close (OUT);
   close (IN);
   unlink ($fname);
}


sub get_accno {
   #
   #
   #

   my ($in_fh, $out_fh, $report_fh) = @_;

   # get to the beginning of the ff
   #
   my $line;
   while ($line = <$in_fh>) {
      last if (substr ($line, 0, 5) eq 'LOCUS');
   }

   print ($out_fh $line);

   while ($line = <$in_fh>) {
      print ($out_fh $line);
      last if (substr ($line, 0, 9) eq 'ACCESSION');
   }

   my $accno;
   if ($line =~ /ACCESSION\s+(\w+)\s/) {
      $accno = $1;

   }else{
      print ($report_fh "ERROR: wrong format of line\n$line\n");
      return '';
   }

   return $accno;
}



sub print_until_feattable {
   #
   #
   #

   my ($in_fh, $out_fh) = @_;

   while (my $line = <$in_fh>) {
      print ($out_fh $line);
      last if (substr ($line, 0, 8) eq 'FEATURES');
   }
}



sub print_clean_feattable {
   #
   #
   #

   my ($in_fh, $out_fh, $report_fh, $pids_h) = @_;

   my $line = <$in_fh>;

   while ( substr($line, 0, 1) eq ' ') {

      print ($out_fh $line);

      if (substr($line, 5, 3) eq 'CDS') {
         $line = print_cds_feat ($in_fh, $out_fh, $report_fh, $pids_h);
         unless ($line) {
            return (0);
         }
         print ($report_fh "   -------\n");

      } else {
         $line = <$in_fh>;
      }
   }

   print ($out_fh $line);

   return (1);
}


sub print_cds_feat {
   #
   #
   #

   my ($in_fh, $out_fh, $report_fh, $pids_h) = @_;

   my $pid_regexp = qr/^ {21}\/protein_id="(\w+)\./; #"

   my ($line, @cds_lines, @ff_pids);
   while ( defined($line = <$in_fh>) && (substr($line, 5, 1) eq ' ') ) {

      if ($line =~ m/$pid_regexp/) {
         push (@ff_pids, $1);
      }

      push (@cds_lines, $line);
   }

   my @matching_pids = grep ({${$pids_h}{$_}} @ff_pids);

   my ($good_pid, $whence);

   if ($#matching_pids > 0) {# more than one valid pid -> take the first one
      ($good_pid) = (@matching_pids);
      $whence = 'DB*';

   } elsif ($#matching_pids == 0){# one valid pid -> take it
      ($good_pid) = (@matching_pids);
      $whence = 'DB';

   } else {# no valid pids -> take the first one
      ($good_pid) = (@ff_pids);
      $whence = 'FF';
   }

   foreach my $cds_line (@cds_lines) {

      if ($cds_line =~ m/$pid_regexp/) {

         if ($1 eq $good_pid) {
            print ($out_fh $cds_line);
            print ($report_fh "   Kept (${whence}):$cds_line");

         } else {
            print ($report_fh "   Removed:  $cds_line");
         }

      } else{
         print ($out_fh $cds_line);
      }
   }

   return $line;
}


sub init_db {
   # Connect to Oracle and initialize the query.
   #
   #
   my ($connection) = @_;
  $connection =~ s/^\/?\@?//;
   my $dbh = DBI->connect( "dbi:Oracle:$connection",'','',
    { RaiseError => 1,
      PrintError => 0,
      AutoCommit => 0 } );

   my $sql = "
SELECT
       c.protein_acc
FROM
       dbentry d,
       cdsfeature c
WHERE
       c.bioseqid = d.bioseqid
   AND d.primaryacc# = :1";

   my $cursor = dbi_open ($dbh, $sql);

   return ($dbh, $cursor);
}


sub get_protein_ids {
   #
   #
   #

   my ($cursor, $accno) = @_;

   my $rv = dbi_bind($cursor, $accno);

   unless($rv){
     die ("Cannot execute query!");
   }

   my @pids = $cursor->fetchall_arrayref ();


   my %pids_h;
   foreach (@{$pids[0]}) {
      $pids_h{${$_}[0]} = 1;
   }

   return \%pids_h;
}


sub print_the_rest {
   #
   #
   #

   my ($in_fh, $out_fh) = @_;

   while (my $line = <$in_fh>) {
      print ($out_fh $line);
   }
}


sub read_command_line {
   #
   #
   #

   my %OPT;

   my $USAGE = "
Usage:
 $0 <conn> [-ff] <file name>

 Takes a list of putff error files names in <file name> in NCBI format and writes a
 file <file name>$EXT with one protein id per CDS for each file in the list.
 A file <file name>$LOG_EXT will contain a log of operations.

 With the -ff flag <file name> refers to an individual flatfile rather than a list of names.

";

   $OPT{connection} = shift (@ARGV);

   if ($ARGV[0] && ($ARGV[0] =~ /-ff/i) ) {
      $OPT{flatfile} = 1;
      $OPT{file_name} = $ARGV[1];

   } elsif ( defined($OPT{file_name} = $ARGV[0]) ){
      $OPT{flatfile} = 0;

   }

   if (!defined($OPT{file_name}) ) {
      die ($USAGE);
   }

   unless ( -f ($OPT{file_name}) ) {
      die ("ERROR: $OPT{file_name} does not exist\n");
   }

   unless ( -r ($OPT{file_name}) ) {
      print (STDERR "ERROR: you do not have permission to read file $OPT{file_name}\n");
      print (`ls -l $OPT{file_name}`);
      exit;
   }

   return %OPT;
}

