#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/seq_update.pl,v 1.34 2014/07/11 11:15:11 blaise Exp $
#
#  (C) EBI 2000
#
#  DESCRIPTION:
#
#  Processes all the .newseq files in the current directory. For each of
#  them the following steps are taken:
#  1. The latest version of the entry is unloaded from the db
#     as a .dat file. 
#  2. The .newseq file and the .dat file are then aligned with EMBOSS, and
#     the .ali file is created to be checked by curator.
#     NB a global alignment is tried, and if it has a low score, an alignment 
#     is tried with the reverse-complement new sequence, then a local 
#     alignment, then a reverse local alignment.
#  3. An 'updated' version of the EMBL flat file (.fflupd file) is created
#     by 'merging' the file unloaded from the db and the .newseq file. The
#     following changes are made to the entry:
#     - sequence length on ID-line and SQ-line are updated
#     - location of source feature is updated
#     - non-confidential entries: new submission reference added and old
#       one updated accordingly
#       confidential entries: submission reference updated
#  3. The program displays a command to compare the old and new versions of
#     the entry (to be excuted by curator)
#
#  The new files can be updated with newfeatures (or by hand) or directly
#  loaded into the db if no further updates are required. Two scripts are
#  created to test-load (updcheck.csh) and load (upd.csh) all the updated
#  files, resp.
#
#  NOTE: file *** upd.csh *** is parsed in script *** seq_update_ack.pl***;
#  check if the parsing is affected if format of upd.csh is changed !
#
#  MODIFICATION HISTORY:
#
#  30-AUG-2000 Nicole Redaschi     Ported from VMS NEWSQS.COM.
#  13-JUN-2001 Carola Kanz         * changed file extensions: *.dat for files
#                                    retrieved from database, *.fflupd for new
#                                    entry version to be loaded
#                                  * create file updcheck.csh which loads with
#                                    parse_only option and runs ckprot
#                                  * delete /translation qualifiers from *.fflupd
#                                  * update latest submission_ref and add new one
#                                    for non conf. entries ( see header update_ff )
#  27-JUN-2001 Carola Kanz         changed format file upd.csh ( equal to load.csh
#                                  created by assign_accno.pl ) 
#  10-JUN-2001 Carola Kanz         if one of the system calls fail, files upd.csh, 
#                                  updcheck.csh ( and *.embl, if existing ) are
#                                  deleted and seq_update.pl terminates
#  09-AUG-2001 Peter Stoehr        usage notes
#  03-SEP-2001 Nicole Redaschi     file protection of files set to 660.
#  06-SEP-2001 Nicole Redaschi     uppercase ac/id in file names. use getff.pl.
#  22-SEP-2001 Nicole Redaschi     added option -test. 
#  25-SEP-2001 Nicole Redaschi     use option -test in call to getff.pl.
#  25-OCT-2001 Nicole Redaschi     replaced buggy call of localtime with get_mtime.
#  29-NOV-2002 Nadeem Faruque      Use stretcher instead of fasta in alignment
#                                  parses score and does a reverse alignment if negative
#                                  and matcher if neither global alignment is good.
#  09-DEC-2002 Nadeem Faruque      Redirects STDERR (override with -verbose) to 
#                                  make output more sparse.
#  28-JAN-2003 Nadeem Faruque      Change alignment file names to all end in .ali
#                                  Bail error messages also output to STDERR 
#  28-JUL-2006 Nadeem Faruque      Calls seqret for every .newseq files to ensure
#                                  they are in the GCG format expected by
#                                  SeqDBUtils's compose_ff subroutine.
#  
#  11-JUL-2014 Blaise Alako        Changed parameter to matcher. The initial script relied on
#                                  EMBOSS 2.0, in EMBOSS 6.6.0 
#                                  -gapLength    becomes -gapextend
#                                  -gappenalty   becomes -gapopen
#
#===============================================================================


use strict;
use DirHandle;
use File::stat;
use DBI;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Processes all the .newseq files in the current directory.\n".
    "          Performs all the steps required to prepare a sequence update\n".
    "          for an entry (see detail below).\n\n".
    " USAGE:   $0\n".
    "          <user/password\@instance> [-test] [-h]\n\n".
    "   <user/password\@instance>\n".
    "                   where <user/password> is taken automatically from\n".
    "                   current unix session\n".
    "                   where <\@instance> is either \@enapro or \@devt\n\n".
    "   -test           checks for test vs. production settings\n\n".
    "   -h              shows this help text\n\n".
    "   -v              verbose, stderr output to console\n\n".
    "   -no_align       skip alignment steps\n\n".
    " For each .newseq file the following steps are taken:\n\n".
    " 1. The latest version of the entry is unloaded from the database.\n".
    "    The .newseq file and the .dat are then compared with EMBOSS's\n".
    "    stretcher global alignment program which produces a .ali file\n".
    "    If a simple check of the score is done.\n".
    "    Low scoring initial alignments are supplemented by the best\n".
    "    scoring alternative (reverse, local and reverse-local alignments)\n".
    "    and the curator advised accordingly.\n".
    " 2. An 'updated' version of the EMBL flat file (.fflupd file) is created\n".
    "    by 'merging' the file unloaded from the database and the .newseq file.\n".
    "    The following changes are made to the entry:\n".
    "    - sequence length on ID-line and SQ-line are updated\n".
    "    - location of source feature is updated\n".
    "    - for non-confidential entries: a new submission reference is added\n".
    "      and the old one is updated\n".
    "    for confidential entries: the existing submission reference is\n".
    "    updated\n".
    " 3. The new .fflupd files can be loaded into the database if no further\n".
    "    updates are required. Two scripts are created to test-load\n".
    "    (updcheck.csh) and load (upd.csh) all the fflupd files.\n\n";

( @ARGV >= 1 && @ARGV <= 4 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide ( 1 );

my $login   = $ARGV[0];
my $test    = 0;
my $verbose = 0;
my $doAlign = 1;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] eq "-test" ){
      $test = 1;}
   elsif ( $ARGV[$i] eq "-v" || $ARGV[$i] eq "-verbose"){
      $verbose = 1;}
   elsif ( $ARGV[$i] eq "-no_align"){
      $doAlign = 0;}
   else {
      die ( $usage );}
}

die if ( check_environment ( $test, $login ) == 0 );

# Output is too cluttered; redirect STDERR to eliminate these lines
#   Connecting to database PRDB1
#   Created file ********.dat
#   Finds the best *****  alignment between two sequences
if ($verbose == 0){
#    print "STDERR directed to temporary file newsqs.log\n\n";
    print "Working on $login\n";
    open(STDERR, "> newsqs.log") || die "Could not create the file newsqs.log";
}

#-------------------------------------------------------------------------------
# get names of .newseq files.
#-------------------------------------------------------------------------------

my $dh = DirHandle->new ( "." ) || die ( "ERROR: cannot open directory: $!\n" ); 
my @files = sort grep { -f } grep { /\.newseq$/ } $dh->read ();
if ( ! @files ){
    my $errortxt = "\nThere are no .newseq files in this directory!\n\n";
   print $errortxt;
   if ($verbose == 0){
       print STDERR "\nERROR: $errortxt\n";
       close (STDERR);
       print "see newsqs.log for any other information\n";
   }
   exit;
}

# filenames, etc.

my $parse_update    = "updcheck.csh";
my $load_update     = "upd.csh"; # do not change name or format without changing seq_update_ack.pl
my $getff           = "getff.pl";
my $putff           = "putff";
my $ckprots         = "ckprots.pl";
my $putff_log       = "load.log";
my $ckprots_log     = "ckprots.log";

open ( PU, "> $parse_update" ) || die "ERROR: cannot open file $parse_update: $!\n";
open ( LU, "> $load_update" )  || die "ERROR: cannot open file $load_update: $!\n";
print PU "#!/bin/csh\n\ncat \\\n";
print LU "#!/bin/csh\n\ncat \\\n";

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

#-------------------------------------------------------------------------------
# process each file
#-------------------------------------------------------------------------------

my $nof_ok = 0;
foreach my $newseq ( @files )
{
   # ensure that they are in gcg format
    system "seqret $newseq gcg::$newseq";

   # get accession number from file name.

   my $ac = uc ( $newseq );
   $ac =~ s/\.NEWSEQ//;

   my $dat    = "$ac.dat";
   my $ali    = "$ac.ali";
   my $seq    = "$ac.seq";
   my $oldseq = "$ac.oldseq";
   my $fflupd = "$ac.fflupd";
   my $tmp    = "$ac.tmp";
   my $status   = "";
   # get last modification date of .newseq file ( needed for submissionref update )

   my $newseq_time = get_mtime ( $newseq, "DD-MON-YYYY" );

   # unload latest version of entry from db.
   # (use wrapper script to get uppercase filename)

   print "\n-- $ac --------------------------------------------------------------------\n";
   my $command = "$getff $login -a$ac";
   if ( $test )
   {
      $command .= " -test";
   }

   ( system ( $command ) ) && 
       bail_int ( $dbh, "$command failed", $load_update, $parse_update );
    if (! ( -e $dat ) ){
	print "Could not getff \"$ac\" with\n"
	    . " $command"
	    . " skipping it";
	next;
    }

   if ($doAlign){
       # use EMBOSS stretcher to do local alignment of the old and the new sequences
       my $score = doAlignment($ac, $newseq, 'stretcher', '');
       
       if ($score > 0){
	   print "Alignment $ac.ali Score = $score\n";}
       else{
	   print "********************************************************************************\n".
	       "**** Bad Alignment $ac.ali Score = $score ****\n";
	   my $revScore =  doAlignment($ac, $newseq, 'stretcher', '-sreverse1');
	   if ($revScore > 0){
	       print "**** Reversed Alignment $ac.ali Score = $revScore\n";}
	   else {
	       (system ("rm $ac.rev.ali"))&&
		   bail_int ( $dbh, 
			      "Unable to delete $ac.rev.ali, the unwanted output from an attempted reverse alignment", 
			      $load_update, $parse_update, "$ac.dat" );
	       print "**** a reverse global alignment is no better ($revScore)\n";
	       
	       # Try matcher's local alignment in case the submittor omitted a large part of their current sequence
	       $score = doAlignment($ac, $newseq, 'matcher', '');
	       $revScore = doAlignment($ac, $newseq, 'matcher', '-sreverse1');
	       if ($score > $revScore){
		   (system ("rm $ac.local.rev.ali"))&&
		       bail_int ( $dbh, 
				  "Unable to delete $ac.rev.ali, the unwanted output from an attempted local reverse alignment", 
				  $load_update, $parse_update, "$ac.dat" );
		   print "****\n**** Local Alignment $ac.local.ali Score = $score\n".
		       "**** Suspected partial sequence submitted\n";
	       }
	       else {
		   (system ("rm $ac.local.ali"))&&
		       bail_int ( $dbh, 
				  "Unable to delete $ac.ali, the unwanted output from an attempted local alignment", 
				  $load_update, $parse_update, "$ac.dat" );
		   print "****\n**** Local Alignment $ac.local.rev.ali Score = $score\n".
		       "**** Suspected partial reverse sequence submitted\n";
	       }
	   }
       }
   }


# print a blank line to seperate the alignment info from the base span warnings
   print"\n";

   # rename files.

   rename ( $seq, $oldseq ) if ( -e $seq );
   rename ( $newseq, $seq );

   # create new EMBL flat file.

   compose_ff ( $dat, "", $seq, $fflupd );

   # delete /translation qualifiers from *.fflupd
   # add new submission

   $status = update_ff ( $dbh, $fflupd, $tmp, $ac, $newseq_time );

   print "\nCheck modifications with: emdiff $dat $fflupd \&\n";

    if ($status ne "public"){
	print "\n*** Entry $ac is $status ***\n";
    }
    else{
	print "*** Check the name and address of the new submission reference in public entry $ac.fflupd\n";
    }

   # add line to command scripts.

   print PU "$fflupd \\\n";
   print LU "$fflupd \\\n";

   $nof_ok++;
}

# finish command scripts.

print PU "> load.dat\n\n";
print LU "> load.dat\n\n";

print PU "$putff $login load.dat -parse_only -no_error_file >& $putff_log\n";
print LU "$putff $login load.dat -audit 'sequence update' -no_error_file >& $putff_log\n";

print PU "$ckprots $putff_log >& $ckprots_log\n";

print PU "rm -f load.dat\n";
print LU "rm -f load.dat\n";

print PU "cat $ckprots_log\n";  # display ckprot logfile after run
print LU "cat $putff_log\n";    # display load logfile after run

close ( PU ) || die ( "ERROR: cannot close file $parse_update: $!\n" );
close ( LU ) || die ( "ERROR: cannot close file $load_update: $!\n" );

chmod ( 0770, $parse_update );
chmod ( 0770, $load_update );

if ( $nof_ok == 0 ) 
{
   unlink ( $parse_update ) || die ( "ERROR: cannot remove file $parse_update: $!\n" );
   unlink ( $load_update )  || die ( "ERROR: cannot remove file $load_update: $!\n" );
}

print "\n".($#files+1)." file(s) processed, $nof_ok files(s) ok\n";


# disconnect from database

dbi_rollback ( $dbh );
dbi_logoff ( $dbh );

if ($verbose == 0){    
    close(STDERR);
    unlink ( <"newsqs.log"> ) || warn "cannot remove newsqs.log\n";
}

#===============================================================================
# subroutines 
#===============================================================================

#--------------------------------------------------------------------------------
# - delete /translation qualifiers
#
# - add new submissionref / update latest one:
#   non conf. entry:
#    * add new submissionref ( RL line copied from last submissionref, date
#      changed to file date of .newseq file )
#    * delete RP line of last one
#    * insert RC line in last one: 'revised by [nof new submissionref]'
#   conf. entry:
#    * no new submissionref
#    * update the latest one: 
#      - update RP line
#      - add RC line: 'revised by author [file date of .newseq file]'
#   ( RC lines in the latest submissionrefs are overwritten )
#
#   *** the submissionref can also be added in the publication form -- if the
#   format is to be changed, the form also has to be updated ***
#--------------------------------------------------------------------------------
sub update_ff 
{
   my ( $dbh, $infile, $tmp, $ac, $new_date ) = @_;
  
   open ( OUT, ">$tmp" ) || bail ( "cannot open file $tmp: $!", $dbh );
   open ( IN, $infile )  || bail ( "cannot open file $infile: $!", $dbh );

   my $in_transl = 0;
   my $RA = "";
   my $RL = "";
   my $curr_RN = 0;
   my $dont_print = 0;

   my $status = dbi_getvalue ( $dbh, "select STATUS 
                                        from cv_status, dbentry
                                      where dbentry.primaryacc# = '$ac'
                                        and dbentry.statusid = cv_status.statusid");
   print "status = $status\n";
   my $conf;
   if ($status ne "public"){
       $conf = 'Y';
   }
   else{
       $conf = 'N';
   }
   print "conf = $conf\n";
   my $max_subref = dbi_getvalue ( $dbh,
         "select nvl ( max( c.orderin ), 0 ) 
            from citationbioseq c, dbentry d, publication p
           where d.primaryacc#='$ac' 
             and d.bioseqid = c.seqid
             and c.pubid = p.pubid
             and p.pubtype = 0" );
     
   my $max_ref = dbi_getvalue ( $dbh,
         "select nvl ( max ( c.orderin ), 0 ) 
            from citationbioseq c, dbentry d
           where d.primaryacc#='$ac' 
             and d.bioseqid = c.seqid" );

   my $new_seqlen = 0;

   while ( <IN> ) 
   {
      $dont_print = 0;

      if ( /^ID   .* (\d+) BP.\n$/ ) 
      {
	 # seqlen of updated sequence for RP line change
	 $new_seqlen = $1;
      }

      # dont print translation - set switch if translation is parsed
      if ( /\/translation=/ ) 
      {
	 $in_transl = 1;
      }
      elsif ( $in_transl == 1 && ( /FT {19}\// || !/FT {19}/ )) 
      {
	 $in_transl = 0;
      }

      # parse reference number
      if ( /^RN   \[(.*)\]/ ) 
      {
	 $curr_RN = $1;
      }

      if ( $curr_RN == $max_subref ) 
      {
	 # inside the latest submission reference: apply changes documented in header
	 # and keep data for duplication

	 if ( /^RC   / ) 
	 {
	    # ignore old RC lines - they are overwritten
	    $dont_print = 1;
	 }
	 elsif ( /^RP   / ) 
	 {
	    # print new RC line before handling RP line
	    if ( $conf eq "N" ) 
	    { 
	       print OUT "RC   revised by [".($max_ref+1)."]\n"; 
	    }
	    else 
	    { 
	       print OUT "RC   revised by author [$new_date]\n"; 
	       print OUT "RP   1-${new_seqlen}\n"; 
	    }
	    $dont_print = 1;   ## delete/overwrite old RP line
	 }
	 elsif ( /^RA   / ) 
	 {
	    $RA .= $_      if ( $conf eq 'N' );
	 }
	 elsif ( /^RL   / ) 
	 {
	    $RL .= $_      if ( $conf eq 'N' );
	 }
      }

      #### print flatfile
      print OUT $_  if ( $in_transl == 0 && $dont_print == 0 );

      if ( /^XX/ && $curr_RN == $max_ref ) 
      {
	 # finished with the latest reference: add new submission reference for
	 # non confidential entry
	 $curr_RN = 0;
	 if ( $conf eq "N" ) 
	 {
	    ### print new submissionref
	    print OUT "RN   [".($max_ref+1)."]\n";
	    print OUT "RP   1-${new_seqlen}\n";
	    print OUT $RA;
	    print OUT "RT   ;\n";
	    $RL =~ s/Submitted \(.*\)/Submitted \($new_date\)/;
	    print OUT $RL;
	    print OUT "XX\n";
	 }
      }
   }
   close ( IN );
   close ( OUT );
   rename ( $tmp, $infile );
   return $status;
}


sub bail_int 
{   
   my ( $db, $errortxt, @files ) = @_;

   # disconnect from Oracle
   dbi_rollback ( $db );
   dbi_logoff ( $db );

   foreach ( @files ) {
      unlink ( $_ );}
   print "\nERROR: $errortxt\n";
   if ($verbose == 0){
       print STDERR "\nERROR: $errortxt\n";
       close (STDERR);
       print "see newsqs.log for any other information\n";
   }
   exit;
}

sub doAlignment{
    # probably don't need to take all these arg but did not want to rely on these variables being global
    my $ac          = shift;
    my $newseq      = shift;
    my $program     = shift;
    my $extraParam  = shift;   # may include the reverse flag
    my $score   = -1;                # Just in case the only error is that no Score line is found in the alignment, 
                                     # have a default negative score
    my $aliFileName = "$ac";
    if ($program    eq 'matcher'){
	$aliFileName .= ".local";}
    if ($extraParam eq '-sreverse1'){
	$aliFileName .= ".rev";}
    $aliFileName .= ".ali";
    #The following depend on EMBOSS 2.0 , parameter to to matcher and stretcher changed in later version of EMBOSS (6.6.0)
    #my $command = $program." $newseq $ac.dat -outfile $aliFileName $extraParam -awidth3 60 -gappenalty 16 -gaplength 4";
    my $command = $program." $newseq $ac.dat -outfile $aliFileName $extraParam -awidth3 60 -gapopen 16 -gapextend 4";

# printing the alignment command is a good idea but leaves the output more cluttered
#    print "$command\n";
#    ( system ( $command." 2> /dev/null") ) &&

    ( system ( $command ) ) &&
	bail_int ( $dbh, $program." alignment failed for $ac", $load_update, $parse_update, "$ac.dat" );
    
    #Read alignment score from the file (probably should have taken it directly from the output)
    open (ALI_FILE, $aliFileName);
#    print "Created the alignment file $aliFileName\n";
    while(<ALI_FILE>){
	my $latestLineIn   = $_ ;
	if (($program eq 'stretcher') && ($latestLineIn =~ /^# Identity:/  )){
					  my $identicalScore =  $latestLineIn;
					  $identicalScore    =~ s/^\D*(\d+)\/.*/$1/ ;
					  my $maxScore =  $latestLineIn;
					  $maxScore    =~ s/^[^\/]*\/(\d+)\D.*/$1/ ;
					  if ($identicalScore == $maxScore){
					      print "**** New sequence may be identical, check the file\n";}
				      }
	if ($latestLineIn =~ /^# Score:/){  
	    $latestLineIn =~ s/[^0-9\-]*(\-?\d*)\D*$/$1/;
	    $score = $latestLineIn;
	    last;
	}
    }
    close(ALI_FILE);
    return $score;
}
