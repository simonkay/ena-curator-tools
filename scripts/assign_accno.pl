#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/assign_accno.pl,v 1.68 2012/08/14 13:26:44 mjang Exp $
#
#  (C) EBI 2000
#
#  DESCRIPTION:
#
#  Processes all .temp files in current DS directory.
#  (DS number is derived from name of current directoy)
#
#  - assigns accession numbers (currently AL)
#  - creates entrynames (from accession number and organism name:
#    gives warning if /organism is not equal to organism information in DE line)
#  - temorary fixes (#!#) for VMS legacy:
#    variation, organelle, organism (from fixembl.pl)
#    "**   Hold_Date = ..." -> "HD * confidential ..."
#    strip other **-lines with -strip (for myself, curators edit files after this script)
#  - creates load scripts:
#    1. load_parse_only.csh:
#       parse entries  -> load.log
#                      -> *.tax files for ckorgs (create_tax_consult_letter.pl)
#       run ckprots    -> ckprots.log
#    2. load_parse_only_single.csh (same with first entry only for bulk 
#       submissions with >= 25 entries)
#    3. load.csh:
#       store entries in database
#=============================================================================================

use strict;
use DBI;
use DirHandle;
use SeqDBUtils;
use SeqDBUtils2;
use Getopt::Long;
use ENAdb;

# filenames, etc.
my $load          = "load.csh";
my $parse         = "loadcheck.csh";
my $parse_one     = "loadcheck1.csh";
my $accno_file    = "pre_assigned_acc";
my $log_file      = "assign_accno.log";
# log all accession numbers that are assigned by this script
my $log_file_ac   = "/ebi/production/seqdb/embl/tools/log/assign_accno.log";
my $ext           = "ffl";
my $putff         = "putff";
my $ckprots       = "ckprots.pl"; # .aliases are not sourced!
my $putff_log     = "load.log";
my $ckprots_log   = "ckprots.log";

sub myexit($$) {
    my $message = shift;
    my $dbh = shift;
    $dbh->disconnect;
    die $message;
}

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Assigns accession numbers (from '$accno_file' file if present)\n".
            "          to all .temp files in the DS\n".
            "          directory and writes .csh files (to check and load all .ffl\n".
            "          files) ".
            "          OR writes a list of accession numbers into\n".
            "          '$accno_file'\n\n".
            " USAGE:   $0\n".
            "          <user/password\@instance> [<no_of_ac>|-pre_assigned] [-p] [-tpx] [-h] [-test]\n\n".
            "          Assigns accession numbers to all .temp files in the DS\n".
            "          directory. Writes output to <AC>.ffl files.\n".
            "          Creates script files '$parse' (to parse <AC>.ffl\n".
            "          against the database and run ckprots.pl on the 'load.log'\n".
            "          file), '$parse_one' to check just the first entry\n".
            "          for a bulk submission, and '$load' (to load the flatfiles)\n\n".
            "   <user/password\@instance>\n".
            "                        where <user/password> is taken automatically from\n".
            "                        current unix session\n".
            "                        where <\@instance> is either \@enapro or \@enadev \n\n".
            "   <no_of_ac>           where <no_of_ac> is number of accession numbers to\n".
            "                        be written into the file called '$accno_file'\n".
            "                        no check or load command files are produced\n\n".
            "   -p                   creates accession numbers for project entries \n".
            "   -tpx                 creates accession numbers for TPX entries \n".
            "   -wgs<prefix+version> creates accession numbers for wgs sets, needs prefix and version\n".
            "                        e.g. CABB01\n\n".
            "   -tsa<prefix+version> creates accession numbers for tsa sets, needs prefix and version\n".
            "   -test                checks for test vs. production settings\n".
            "   -h                   shows this help text\n\n";

( @ARGV >= 1 && @ARGV <= 4 ) || die $usage; 
( $ARGV[0] !~ /^-h/i ) || die $usage;

my $verbose = 0;
my $login   = $ARGV[0];
my $number_to_preassign = 0;
my $project = 0;
my $tpx     = 0;
my $test    = 0;
my $wgs_prefix = "";
my $tsa_prefix = "";
my $prefix_type_requested = "DS";

# Need to simplify args and eliminate conflicting ones
# possibly have interaction with user when using assign to pressign or use preassigned
#GetOptions( "verbose!"   => \$verbose,
#	    "wgs=s"      => \$wgs_prefix,
#	    "type=s"     => \$prefix_type_requested,
#	    "project=i"  => \$project,
#	    "preassign=i"=> \$number_to_preassign
#	    );
#
#            );
#foreach (@ARGV) {
#    parseId ($_, \@acs, \@gis) || print STDERR "Cannot understand identifier $_\n";
#}

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\d+$/ ) {
       $number_to_preassign = $ARGV[$i];
   } elsif ( $ARGV[$i] eq "-p" ) {
       $project = 1;
   } elsif ( $ARGV[$i] eq "-tpx" ) {
       $tpx = 1;
   }
   elsif ( $ARGV[$i] eq "-test" ) {   
      $test = 1;
   }
   elsif ($ARGV[$i] =~ /-v(erbose)?/) {       
       $verbose = 1;
   }  
   elsif ($ARGV[$i] =~ /-wgs([A-Za-z]{4}\d{2})/) {       
      $wgs_prefix = uc ($1);
   }
   elsif ($ARGV[$i] =~ /-tsa([A-Za-z]{4}\d{2})/) {       
      $tsa_prefix = uc ($1);
   }  
   else {
      die $usage;
   }
}

# I should handle these disputes better instead of dying - still a word of explanation will help:
if ( ( -r "$accno_file" ) && $number_to_preassign ) {
    die ( "You want to preassign $number_to_preassign and use accnos from $accno_file!\n$usage" );
}
if ( $project && $tpx ) {
    die ( "TPX accessions are only available for direct subs and not for projects!\n$usage" );
}

my $database = uc($login);
$database =~ s/^\/\@//;


if (($wgs_prefix || $tsa_prefix) && ($project || $number_to_preassign || $tpx)) {
    die "-wgs or -tsa cannot be used with any other flag\n$usage";
} 

# This bit really should be handled by a single -type=? arg
if ($tpx) {
    $prefix_type_requested = 'TPX';
} elsif ($wgs_prefix) {
    $prefix_type_requested = 'WGS';
} elsif ($tsa_prefix) {
    $prefix_type_requested = 'TSA';
}

if (-e "load.csh") {
    die "ERROR: load.csh exists. If you really intend to assign again, please delete load.csh and rerun assign.\n";
}

die if ( check_environment ( $test, $login ) == 0 );

#-------------------------------------------------------------------------------
# get the DS number from the current working directory
#-------------------------------------------------------------------------------

my $ds = 0;
if ( ! $project ) # project entries are not kept in DS directories
{
   $ds = get_ds ( $test ) || die;
}

#-------------------------------------------------------------------------------
# get list of .temp files (unless we are only writing a pre_assigned_acc file)
# check if BULK.SUBS exist
#-------------------------------------------------------------------------------

my @files = ();
my $number_of_entries = 0;
my $dataclassInFiles = "";

if ( ! $number_to_preassign ) {
    my $dh = DirHandle->new ( "." ) || die ( "ERROR: cannot open directory: $!\n" ); 
    @files = sort grep { -f } grep { /\.temp$/ } $dh->read(); 
    
    # unfortunately BULK.temp will be picked up both in list of .temp files and here.
    # could have been avoided with different file name system (like BULK.SUBS)
    if (-e "BULK.temp"){
	print STDERR "using BULK.temp\n";
	if ((@files) && (scalar(@files) > 1)) {
	    die "ERROR: both BULK.temp and .temp file exist. BULK.temp can be used to make BULK.ffl\n".
		"       or .temp files may be processed to make several .ffl files.\n";
	}
    } elsif (-e "BULK.SUBS"){
	if (@files) {
	    die "ERROR: both BULK.SUBS and .temp file exist. BULK.SUBS can be used to make BULK.ffl\n".
		"       or .temp files may be processed to make several .ffl files.\n";
	} 
	push(@files,"BULK.SUBS"); 
    }
    if (!@files){
	die "ERROR: there are no files to be processed.\n";
    } 

    ($number_of_entries, $dataclassInFiles) = getNumberEntriesAndDataclass(@files);

    $verbose && printf STDERR "%d files containing %d entries of type %s\n", scalar(@files), $number_of_entries, $dataclassInFiles;
    if ( !( $number_to_preassign ) ) {
	if ($dataclassInFiles eq 'TPX') {
	    $tpx = 1; # hopefully we'll remove this
	    $prefix_type_requested = 'TPX';
	}
    }
    if (($wgs_prefix||$tsa_prefix) && (($files[0] ne "BULK.SUBS") && ($files[0] ne "BULK.temp"))) {
	die ("\nERROR: WGS(-like TSA) accessions are assigned in a BULK.SUBS or BULK.temp file. Please provide one of these files.\n");
    }

} else {
    $verbose && print STDERR "Preassigning $number_to_preassign\n";
    $number_of_entries = $number_to_preassign;
}

#-------------------------------------------------------------------------------
# open logfiles
#-------------------------------------------------------------------------------

open ( LOG, ">>$log_file" ) || die ( "ERROR: cannot open file $log_file: $!\n" );
print LOG "==========================================\n"
        . "Data processed on ". ( scalar localtime ) . "\n"
        . "==========================================\n" ;

open ( LOG_AC, ">>$log_file_ac" ) || die ( "ERROR: cannot open file $log_file_ac: $!\n" );

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------
my %attr   = ( PrintError => 0,
	       RaiseError => 1,
               AutoCommit => 0 );
my $dbh = ENAdb::dbconnect($database,%attr)
    || die "Can't connect to database: $DBI::errstr";
$dbh->do(q{ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY'}); # not required?

#--------------------------------------------------------------------------------
# if BULK.SUBS exist assign ac from BULK.SUBS
#--------------------------------------------------------------------------------
# need to have a single system to deal with concatenated and/or single ACs
if (!($number_to_preassign) && (($files[0] eq "BULK.SUBS") || ($files[0] eq "BULK.temp"))) {

    my $acc = '';
    my $out_file = "BULK.ffl";
    my @accnos;

    if (($prefix_type_requested eq 'WGS' || $prefix_type_requested eq 'TSA')
		   	and ($dataclassInFiles ne $prefix_type_requested)){
	die ("BULK.SUBS has dataclass $dataclassInFiles but you asked for $prefix_type_requested. No acc assigned\n");
    }
    elsif ((($dataclassInFiles eq 'WGS') and ($wgs_prefix eq '')) ||
	       (($dataclassInFiles eq 'TSA') and ($tsa_prefix eq ''))) {
	die("WGS(-like TSA) entries need a prefix such as CAAZ02.  Please see the database group to have one allocated.\n\nIf you already have a WGS/TSA prefix, please run the following command:\n     assign -wgs<prefix+version>\nor\n assign -tsa<prefix+version>\n");
    }

    @accnos = create_accnos ( $dbh, $number_of_entries, $project, $prefix_type_requested,
		(($prefix_type_requested eq 'WGS') ? $wgs_prefix: $tsa_prefix), $test );
    $dbh->disconnect;

    # process the file
    print LOG "** file: $files[0]\n";
    open (BULK, "< $files[0]") or die "cannot open $files[0]:$!";
    open (BULK_OUT, ">$out_file") or die "cannot open $out_file:$!";

    while ( <BULK> )  {
	if (/^ID/) {
	    $acc = shift (@accnos);
	}
	### old ID line format
	if ( /^ID   (\w+)\s+(standard|deleted|preliminary);((?: circular )|(?: ))([^;]+); ...; (\d+) BP./ ) {
	    if ( $1 ne "ENTRYNAME" ) {
		s/$1/ENTRYNAME/;
	    }
	} elsif ( /^ID   (\w+);\s*(?:(?:SV)|)\s*(\w+); (\w+); ([^;]+); (\w{3}); (\w{3}); (\d+) BP./ ) {
	### 'new' ID line format
	    s/$1/$acc/;
	} elsif ( (/^AC   /) | (/^AC\s*$/) ) {
          if(/^(AC   )(;.*)/){
                $_=$1.$acc.$2."\n";
           }
          else{
	    $_ = "AC   $acc;\n";}
	}
        elsif ((/^WEBIN BULK/) || (/^No sequence /) || (/^no_seq /) || (/^\s*$/)) {
	    next; # skip webin quirks and empty lines
	}
	print BULK_OUT $_;
    }
   
   close (BULK);
   close (BULK_OUT);
   chmod ( 0660, $out_file );

   ### ----  create load scripts
   if (-e $out_file and !-z $out_file){
     # parse_only script
     create_load_script ( $parse, $out_file, 'bulk', $tpx, '' );

     # load script
     create_load_script ( $load, $out_file, 'bulk_load', $tpx, '-new_log_format');
   }

   close (LOG);  
   close (LOG_AC);

   exit;
}

#-------------------------------------------------------------------------------
# get the accession numbers:
# either read them from file pre_assigned_acc....
#-------------------------------------------------------------------------------

my @accnos;

if ( -r "$accno_file" ) {
    print STDERR "Using accessions from file $accno_file\n";
    @accnos = get_preassigned_accnos ( $dbh, $accno_file, $number_of_entries, $prefix_type_requested);
} else {
    @accnos = create_accnos ( $dbh, (( $number_to_preassign ) ? $number_to_preassign : $number_of_entries), 
			      $project, $prefix_type_requested, $test );
}

# disconnect from database
$dbh->disconnect;

if ( $number_to_preassign ) {
    # write accnos to file pre_assigned_acc ...
    open ( OUT, ">$accno_file" ) || die ( "ERROR: cannot open file $accno_file: $!\n" );    
    print OUT join("\n",@accnos)."\n";
    close ( OUT ) || die ( "ERROR: cannot close file $accno_file: $!\n" );
    chmod ( 0660, $accno_file ); 
    
    # ... and exit!
    print LOG "$number_to_preassign accession numbers written to file $accno_file\n\n" ;
    close ( LOG ) || die ( "ERROR: cannot close file $log_file: $!\n" );
    chmod ( 0660, $log_file ); 
    exit;
}


#-------------------------------------------------------------------------------
# process all .temp files
#-------------------------------------------------------------------------------

my @processed_files = ();

foreach my $file ( @files ) {

  print LOG "** file: $file\n";

  open ( IN, $file ) || die ( "ERROR: cannot open file $file: $!\n" );

  # get the next accno from the list
  my $acc = shift ( @accnos );
  print LOG "** accession#: $acc\n";

  my $newfile = "$acc.$ext";
  open ( OUT, ">$newfile" ) || die ( "ERROR: cannot open file $newfile: $!\n" );
  while ( <IN> )  {
    
    last if ( /^\/\/$/ ); # only handles 1 entry per file!
      
    ### old ID line format
    if ( /^ID   (\w+)\s+(standard|deleted|preliminary);((?: circular )|(?: ))([^;]+); ...; (\d+) BP./ ) {
       
      if ( $1 ne "ENTRYNAME" ) {
        s/$1/ENTRYNAME/;
      }
    }
      
    ### new ID line format
    elsif ( /^ID   (\w+);\s*(?:(?:SV)|)\s*(\w+); (\w+); ([^;]+); (\w{3}); (\w{3}); (\d+) BP./ ) {
      s/$1/$acc/;
    }

    elsif ( (/^AC   /) | (/^AC\s*$/) ) {     
       $_ = "AC   $acc;\n";	
    }

    print OUT $_;
  }
  print OUT $_; # print final //
  close ( OUT ) || die ( "ERROR: cannot close file $acc.$ext: $!\n" );
  chmod ( 0660, $newfile ); 
  
  push @processed_files, $newfile;
 
  close ( IN ) || die ( "ERROR: cannot close file $file: $!\n" );
} 

#-------------------------------------------------------------------------------
# parameter -pre_assigned:
# rewrite file pre_assigned_acc, if there are accession numbers left, 
# otherwise delete the file
#-------------------------------------------------------------------------------

if ( -r "$accno_file" ) {
    if ( $#accnos >= 0 ) { 
	open ( OUT, ">$accno_file" ) || die ( "ERROR: cannot open file $accno_file: $!\n" );
	foreach ( @accnos ) {
	    print OUT "$_\n";
	}
	close ( OUT ) || die ( "ERROR: cannot close file $accno_file: $!\n" );
	chmod ( 0660, $accno_file );
	print LOG "\nWARNING: there are accession numbers left in file $accno_file\n";
    } else {
	unlink ( "$accno_file" ) || print LOG "cannot delete $accno_file: $!\n" ;
    }
}

#-------------------------------------------------------------------------------
# proceed if there are processed files
#-------------------------------------------------------------------------------

if (@processed_files)  {
  ### ----  create load scripts
  # parse_only script
  create_load_script ( $parse, '-', 'parse', $tpx, '');

  # load script
  create_load_script ( $load, '-', 'load', $tpx, '-new_log_format');

  # for bulk submissions ( >= 25 sequences ) also create parse_only load
  # script for the first entry only
  if ( $#processed_files >= 24 ) {
    create_load_script ( $parse_one, $processed_files[0], 'bulk', $tpx );
  }
}


#-------------------------------------------------------------------------------
# if no files were processed, delete concatenated data file and script files
#-------------------------------------------------------------------------------

else  {
  if ( -e "$load" ) {
    unlink ( "$load" );
  }
  if ( -e "$parse" ) {
    unlink ( "$parse" );
  }
}

#-------------------------------------------------------------------------------
# write log file (always clean up old log files, if there are any)
#-------------------------------------------------------------------------------

if ( -e "$putff_log" ) 
{
   unlink ( "$putff_log" ) || die ( "ERROR: cannot delete $putff_log: $!\n" );
}
if ( -e "$ckprots_log" ) 
{
   unlink ( "$ckprots_log" ) || die ( "ERROR: cannot delete $ckprots_log: $!\n" );
}

print LOG "\n" . scalar(@files) . " entries in directory\n"
       . scalar(@processed_files) ." entries to load\n\n" ;
close ( LOG ) || die ( "ERROR: cannot close file $log_file: $!\n" );
chmod ( 0660, $log_file );

close ( LOG_AC ) || die ( "ERROR: cannot close file $log_file_ac: $!\n" );
chmod ( 0660, $log_file_ac );

#===============================================================================
# subroutines 
#===============================================================================

sub getNumberEntriesAndDataclass {

    my @files = @_;
    my %dataclasses;
    my $totalEntries = 0;

    foreach my $file ( @files ) {
	open ( IN, $file );
	while ( <IN> ) {
	    if (/^ID   .*; .*; .*; .*; (\w+); .*; .*\./) {
		if ($1 ne 'XXX') { # XXX is simply undefined and can be 'mixed' with others
		    if (exists($dataclasses{$1})) {
			$dataclasses{$1}++;
		    } else {
			$dataclasses{$1} = 1;
		    }
		}
		$totalEntries++;
	    } 
	}
	close (IN);
    }
    if (scalar(keys %dataclasses) > 1) {
	die ("Multiple dataclasses in use ".join(',',(keys %dataclasses))."\n"
	   . "you can only assign to one at a time\n");
    } 
    
    my $dataclass = 'XXX';
    if (scalar(keys %dataclasses) == 1) {
	$dataclass = (keys %dataclasses)[0];
    }

    return ($totalEntries, $dataclass);
} 

	
sub lockFile {

    my $lockFile = shift;
    my $action   = shift;

    if ( $action eq "make" ) {
	$verbose && print STDERR "Making $lockFile\n";
        if (( -e "$lockFile" ) && (( -M $lockFile ) < 0.05)) { # if exists and less that ~1 hr old
            open LOCK, "<$lockFile"
              or die "$lockFile exists already but cannot read!\n";
            my $existingLock = do { local $/; <LOCK> };
            chomp($existingLock);
	    $dbh->disconnect;
            die "$lockFile exists:-\n \"$existingLock\"\n" . "is someone else assigning?\n";
        }
        else {
	    $verbose && print STDERR "Removing $lockFile\n";
            open LOCK, ">$lockFile"
              or die "Can't create $lockFile file: $!";
	    printf LOCK "Assign started %s by user %s\n", SeqDBUtils2::timeDayDate("timedaydate"), $ENV{'USER'};
            close LOCK;
        }
    }
    else {
        unlink("$lockFile");
    }
    return 1;
}

sub get_preassigned_accnos {
    my ( $db, $filename, $number_of_entries, $prefix_type_requested ) = @_;
    my ( @accnos ) = ();
    
    open ( ACC, "$filename" ) || myexit ( "cannot open file $accno_file: $!\n", $db );
    while ( <ACC> )  {
	s/\s*$//;  # delete trailing \n
	s/^\s*//;  # delete leading white spaces
	push @accnos, $_     if ( /\S+/ );
    }
    close ( ACC ) || myexit ( "cannot close file $accno_file: $!\n", $db );
    
    # check if there are accession numbers that are already used in the database
    my $ac = test_accnos ( $db, @accnos );
    if ( $ac ne '' ) {
	print STDERR "accession number $ac is already used in the database\n\n";
	$db->disconnect;
    }
    # check if there are enough accession numbers for all files
    if ( $#accnos < $number_of_entries ) {
	print STDERR "there are not enough ($number_of_entries) accession numbers in file $accno_file for all entries in DS directory $ds\n\n";
	$db->disconnect;
    }

# should check prefix in database not this hardcoded stuff
    if ( $accnos[0] =~ /^TPX_/ && ($prefix_type_requested ne 'TPX' )) {
	print STDERR "try to assign TPX accession numbers to normal entries\n";
	$dbh->disconnect;
    }
    return ( @accnos );
}


sub create_accnos {
   my ( $dbh, $number_of_entries, $project, $prefix_type, $prefix, $test ) = @_;  
   my @accs;
   my $lock_file   = "/ebi/production/seqdb/embl/data/dirsub/.lock".$database; # NB $database is a global here

   if ($prefix) {
       $lock_file .= "_".$prefix; # wgs get their own lockfile so they don't interfere with normal assigning
   }

   $lock_file .= "_".$prefix_type; # each category gets its own lock - NB prefix table locks itself anyway
   
   lockFile($lock_file,"make");

   # create accession numbers
   my $result = SeqDBUtils2::assign_accno_list($dbh,$number_of_entries,$prefix_type,@accs,$prefix); # fill @accnos
   foreach my $ac1(@accs) {
           # log the accno
      print LOG_AC "$ac1 assigned by ", $ENV{'USER'}, " on ", ( scalar localtime ), $test ? " (test!)\n":"\n";    
   }
   
   lockFile($lock_file,"delete");

   my $comment = "Assigned $accs[0]";
   if (@accs > 1){
       $comment .= "-$accs[-1]";
   } 
   print $comment . ".\n";

   if ($ds != 0){
       SeqDBUtils2::add_submission_history($dbh,$ds,25,$comment);
   }
   return @accs;
}


# check if an accession number is already in the database
sub test_accnos {
   my ( $dbh, @accs ) = @_;
   my $sth = $dbh->prepare ("select count(*) from dbentry where primaryacc# = ?");
   foreach ( @accs ) {
       $sth->execute($_)
	   || die "database error: $DBI::errstr\n ";
       
       if ($sth->fetchrow_array() != 0){
	   return $_;    
       }   
       $sth->finish();
   }
   return '';
}

sub create_load_script {
  ### creates shell scripts for loading/parsing the data
  my ( $loadfname, $fname, $type, $tpx, $new_log_format ) = @_;

  open ( OUT, ">$loadfname" ) || die ( "ERROR: cannot open file $loadfname: $!\n" );
  print OUT "#!/bin/csh\n\n";

  if ($type eq 'bulk_load'){
      if (defined($wgs_prefix) && ($wgs_prefix ne '')) {
	  print OUT "/ebi/production/seqdb/embl/tools/curators/scripts/collab/load_wgs.pl $login $fname -embl -ds $ds -no_error_file\n";
	  }elsif (defined($tsa_prefix) && ($tsa_prefix ne '')) {
		  # this script is temporary name. need to be changed later 20120727
	  print OUT "#/ebi/production/seqdb/embl/tools/curators/scripts/ftp_updates/wgs_loader_only_for_TSA_and_WGS_TPA.pl $login $fname -embl -ds $ds -no_error_file\n";
      } else {
	  print OUT "$putff $login $fname -ds $ds -no_error_file $new_log_format |& tee $putff_log\n";
      }
  } else {
    if ( $type ne 'bulk') {
      # concat all .ffl files for loading
      print OUT "ls -1 | grep .ffl\$ | xargs -i cat {} > load.dat\n\n";
      print OUT "$putff $login load.dat -ds $ds $new_log_format";
    }
    else {
      # for bulk testing only use first entry
      print OUT "$putff $login $fname -ds $ds";
    }
    if ( $tpx ) {
      print OUT " -dataclass TPX";
    }
    if ( $type ne 'load' ) {
      print OUT " -parse_only";
      print OUT " -no_error_file >& $putff_log\n";
    }
    else {
      # for loading show logfile already during the process
      print OUT " -no_error_file |& tee $putff_log\n";
    }
    if ( $type ne 'bulk' ) {
      print OUT "rm -f load.dat\n";
    }
  
    if ( $type ne 'load' ) {
      # for testing run ckprots
      print OUT "$ckprots $putff_log >& $ckprots_log\n";
      print OUT "cat $ckprots_log\n";  # display ckprot logfile after run
    }
  }
  close ( OUT ) || die ( "ERROR: cannot close file $loadfname: $!\n");
  chmod ( 0770, $loadfname );
}

