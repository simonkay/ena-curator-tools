#!/ebi/services/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/deprecated/usedin.pl,v 1.3 2002/05/01 15:23:19 ckanz Exp $
#
#  (C) EBI 2001
#
#  MODULE DESCRIPTION:
#
#  Checks .ffl files for presence of /usedin and /label qualifiers.
#
#  MODIFICATION HISTORY:
#
#  06-SEP-2001 Nicole Redaschi     Created.
#  23-SEP-2001 Nicole Redaschi     added option -test.   
#  04-DEC-2001 Carola Kanz         processes only AJ*.ffl files
#                                  renamed files without /usedin to *.ffl_no_usedin 
#  01-MAY-2002 Carola Kanz         processes all *.ffl files ( excludes filenames 
#                                  starting with a number )
#===============================================================================

use strict;
use DirHandle;
use SeqDBUtils;

# filenames, etc.

my $load_no_usedin  = "load_no_usedin.csh";
my $parse_no_usedin = "loadcheck_no_usedin.csh";
my $load_usedin     = "load_usedin.csh";
my $parse_usedin    = "loadcheck_usedin.csh";
my $load_label      = "load_label.csh";
my $parse_label     = "loadcheck_label.csh";
my $putff           = "putff";
my $ckprots         = "ckprots.pl"; # .aliases are not sourced!
my $putff_log       = "load.log";
my $ckprots_log     = "ckprots.log";

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Checks *.ffl files ( excludes 01.ffl etc. files ) for presence\n".
            "          of /usedin and /label qualifiers.\n\n".
            " USAGE:   $0\n".
            "          <user/password\@instance> [-test] [-h]\n\n";

( @ARGV >= 1 && @ARGV <= 2 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

#hide ( 1 );

my $login = $ARGV[0];
my $test  = 0;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] eq "-test" )
   {   
      $test = 1;
   }
   else
   {
      die ( $usage );
   }
}

die if ( check_environment ( $test, $login ) == 0 );

#-------------------------------------------------------------------------------
# get the DS number from the current working directory
#-------------------------------------------------------------------------------

my $ds = get_ds ( $test ) || die;

#-------------------------------------------------------------------------------
# loop over all *.ffl files.
#-------------------------------------------------------------------------------

my $dh = DirHandle->new( "." ) || die ( "ERROR: cannot open directory: $!\n" ); 
my @files = sort 
            grep { -f } 
            grep { /^[A-Za-z].*\.ffl$/ }
            $dh->read(); 

my @usedin = ();       # names of files with /usedin
my @label = ();        # names of files with /label
my @usedin_label = (); # names of files with /usedin and /label
my @none = ();         # names of files without /usedin or /label

my $files_with_usedin = 0; # number of files with /usedin

foreach my $file ( @files )
{
   my $usedin = 0;
   my $label = 0;
   my $out_file = $file."_no_usedin";
   open ( OUT, "> $out_file" ) || die "ERROR: cannot open file $out_file: $!";
   open ( IN, "< $file" ) || die "ERROR: cannot open file $file: $!";
   while ( <IN> )
   {
      if ( /^FT {19}\/usedin=/ )
      {
	 $usedin = 1;
	 next;
      }
      elsif ( /^FT {19}\/label=/ )
      {
	 $label = 1;
      }
      print OUT $_;
   }
   close ( IN )  || die "ERROR: cannot close file $file: $!";
   close ( OUT ) || die "ERROR: cannot close file $out_file: $!";

   if ( $usedin && $label )
   {
      push ( @usedin_label, $out_file );
      print "WARNING: file $file contains both /usedin and /label.\n";
   }
   elsif ( $usedin )
   {
      push ( @usedin, $out_file );
   }
   elsif ( $label )
   {
      push ( @label, $file );
   }
   else
   {
      push ( @none, $file );
   }

   if ( ! $usedin )
   {
      unlink ( $out_file ) || die "ERROR: cannot remove file $out_file: $!";
   }
   else
   {
      $files_with_usedin++;
   }
}

#-------------------------------------------------------------------------------
# exit here, if none of the files contained /usedin
#-------------------------------------------------------------------------------

if ( $files_with_usedin == 0 )
{
   print "\nOK: no /usedin qualifiers found.\n\n";
   exit;
}

#-------------------------------------------------------------------------------
# create new load scripts: they need to be executed as follows:
#
# 1. $parse_no_usedin: check files that have been stripped of /usedin
# 2. $load_no_usedin:  load  files that have been stripped of /usedin
# 3. $parse_label:     check files with /label qualifiers
# 4. $parse_label:     load  files with /label qualifiers  
# 5. $parse_usedin:    check files with /usedin qualifiers
# 6. $load_usedin:     load  files with /usedin qualifiers
#
# NOTE: this procedure is necessary, because all segments(exons) of a feature
# location that refer to "foreign" entries must be in the db in order to load
# the feature location. on the other hand, all /label pointed to by /usedin
# must be in the db in order to load the /usedin.
#-------------------------------------------------------------------------------

open ( PNU, "> $parse_no_usedin" ) || die ( "ERROR: cannot open file $parse_no_usedin: $!\n" );
open ( LNU, "> $load_no_usedin" )  || die ( "ERROR: cannot open file $load_no_usedin: $!\n" );
open ( PL,  "> $parse_label" )     || die ( "ERROR: cannot open file $parse_label: $!\n" );
open ( LL,  "> $load_label" )      || die ( "ERROR: cannot open file $load_label: $!\n" );
open ( PU,  "> $parse_usedin" )    || die ( "ERROR: cannot open file $parse_usedin: $!\n" );
open ( LU,  "> $load_usedin" )     || die ( "ERROR: cannot open file $load_usedin: $!\n" );

print PNU "#!/usr/bin/csh\n\ncat \\\n";
print LNU "#!/usr/bin/csh\n\ncat \\\n";
print PL  "#!/usr/bin/csh\n\ncat \\\n";
print LL  "#!/usr/bin/csh\n\ncat \\\n";
print PU  "#!/usr/bin/csh\n\ncat \\\n";
print LU  "#!/usr/bin/csh\n\ncat \\\n";

foreach ( @none ) 
{
   print PNU "$_ \\\n";
   print LNU "$_ \\\n";
}
foreach ( @usedin ) 
{
   print PNU "$_ \\\n";
   print LNU "$_ \\\n";
}
foreach ( @usedin_label ) 
{
   print PNU "$_ \\\n";
   print LNU "$_ \\\n";
}
foreach ( @label ) 
{
   print PL "$_ \\\n";
   print LL "$_ \\\n";
}
# now again with the /usedin qualifier
foreach my $file ( @usedin ) 
{
   my $ffl = $file;
   $ffl =~ s/_no_usedin//;
   print PU "$ffl \\\n";
   print LU "$ffl \\\n";
}
foreach my $file ( @usedin_label ) 
{
   my $ffl = $file;
   $ffl =~ s/_no_usedin//;
   print PU "$ffl \\\n";
   print LU "$ffl \\\n";
}

print PNU "> load.dat\n\n";
print LNU "> load.dat\n\n";
print PL  "> load.dat\n\n";
print LL  "> load.dat\n\n";
print PU  "> load.dat\n\n";
print LU  "> load.dat\n\n";

print PNU "$putff $login load.dat -ds $ds -parse_only -no_error_file >& $putff_log\n";
print LNU "$putff $login load.dat -ds $ds -no_error_file >& $putff_log\n";
print PL  "$putff $login load.dat -ds $ds -parse_only -no_error_file >& $putff_log\n";
print LL  "$putff $login load.dat -ds $ds -no_error_file >& $putff_log\n";
print PU  "$putff $login load.dat -ds $ds -parse_only -no_error_file >& $putff_log\n";
print LU  "$putff $login load.dat -ds $ds -no_error_file >& $putff_log\n";

print PNU "$ckprots $putff_log >& $ckprots_log\n";
print PL  "$ckprots $putff_log >& $ckprots_log\n";
print PU  "$ckprots $putff_log >& $ckprots_log\n";

print PNU "rm -f load.dat\n";
print LNU "rm -f load.dat\n";
print PL  "rm -f load.dat\n";
print LL  "rm -f load.dat\n";
print PU  "rm -f load.dat\n";
print LU  "rm -f load.dat\n";

print PNU "cat $ckprots_log\n";  # display ckprot logfile after run
print LNU "cat $putff_log\n";    # display load logfile after run
print PL  "cat $ckprots_log\n";  # display ckprot logfile after run
print LL  "cat $putff_log\n";    # display load logfile after run
print PU  "cat $ckprots_log\n";  # display ckprot logfile after run
print LU  "cat $putff_log\n";    # display load logfile after run

close ( PNU ) || die ( "ERROR: cannot close file $parse_no_usedin: $!\n");
close ( LNU ) || die ( "ERROR: cannot close file $load_no_usedin: $!\n");
close ( PL )  || die ( "ERROR: cannot close file $parse_label: $!\n");
close ( LL )  || die ( "ERROR: cannot close file $load_label $!\n");
close ( PU )  || die ( "ERROR: cannot close file $parse_usedin: $!\n");
close ( LU )  || die ( "ERROR: cannot close file $load_usedin: $!\n");

chmod ( 0770, $parse_no_usedin );
chmod ( 0770, $load_no_usedin );
chmod ( 0770, $parse_label );
chmod ( 0770, $load_label );
chmod ( 0770, $parse_usedin );
chmod ( 0770, $load_usedin );
