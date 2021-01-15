#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/archive_dsdir.pl,v 1.14 2010/02/23 11:15:52 faruque Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Archives all DS directories which are older than 120 days ( ~4 months )
#  and deletes them afterwards. should run as a daily cronjob.
#
#  MODIFICATION HISTORY:
#
#  31-AUG-2000  Carola Kanz      Created.
#  22-SEP-2001  Nicole Redaschi  Use environmental variables.
#                                Added option -test.
#  22-JAN-2003  Carola Kanz      use system to delete directory ( rarely there
#                                are subdirectories )
#  28-SEP-2006  F. Nardone       Use the new archiving strategy.
#  02-AUG-2007  Quan Lin         check if files are readable and writable before archiveing
#===============================================================================

use strict;
use warnings;
use DirHandle;

use Utils qw(my_system);

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $exit_status = 0;
my $usage = "\nUSAGE: $0 [-test | -h]\n\n";

( @ARGV == 0 || @ARGV == 1 ) || die $usage;

my $test = 0;

if ( defined $ARGV[0] ) {
  if ( $ARGV[0] eq "-test" ) {
    $test = 1;
  }
  else {
    print( $usage );
    exit( $exit_status );
  }
}

my $ds      = ( $test ) ? $ENV{"DS_TEST"} : $ENV{"DS"};
my $archive = ( $test ) ? $ENV{"ARCHIVE_TEST"} : $ENV{"ARCHIVE"};

# current settings - defined in curator env and in ~datalib/.cron_env
#DS=/ebi/production/seqdb/embl/data/dirsub/ds
#DS_TEST=/ebi/production/seqdb/embl/data/dirsub/ds_test
#ARCHIVE=/ebi/production/seqdb/embl/data/dirsub/ds_archive
#ARCHIVE_TEST=/ebi/production/seqdb/embl/data/dirsub/ds_archive_test


chdir( $ds ) || die( "ERROR: cannot chdir to '$ds'\n$!" );

( defined $ds && defined $archive ) || die ( "ERROR: environment is not set\n" );

my $dh = DirHandle->new ( $ds ) || die ( "ERROR: cannot open directory '$ds': $!\n" );
my @directories = sort( 
  grep( ! -f($_),   # directories only ( -d does not work... )
    grep( $_ !~ m/^\./,
      $dh->read()
    )
  )
);


foreach my $dir ( @directories ) {

  if ( $dir =~ m/\D/ ) {

    print "WARNING: non-ds directory name '$dir'\n";

  } elsif ( -M $dir > 120 ) {

    my @bits = $dir =~ /(\d{1,3})/g;
    pop( @bits );
    my $arch_subdir =  join( '/', @bits );

    my $tarFile = "$dir.tar";
    my $gzipFile = "$tarFile.gz";

    my @problemFiles = problem_files_in_directory ($dir);
    if (scalar(@problemFiles) > 0) {
	printf "ERROR: Skipping $ds/$dir, there are %d file(s) that are not readable/writable by $ENV{USER}\n%s\n",
		scalar(@problemFiles), join("\n ", @problemFiles);
    } elsif ((-e $tarFile) && (! -r $tarFile || ! -w $tarFile)) {
	print "ERROR: intermediate file $tarFile already exists, $dir is not archived\n";
    } else {
	print "archive $dir to $arch_subdir/$gzipFile\n";
	my_system ( "tar cf $tarFile $dir" );
	my_system( "gzip $tarFile" );

	unless( -d( "$archive/$arch_subdir" ) ) {
	    mkdir( "$archive/$arch_subdir" ) or die ( "ERROR: cannot create directory '$archive/$arch_subdir'\n$!" );
	}

	my_system ( "mv $gzipFile $archive/$arch_subdir" );
	my_system( "rm -r $dir" );
    }

  } else {

    print "*** $dir\n";
  }
}

print "Data processed by $0 on ". ( scalar localtime ) . "\n";

#=============================================================
# subs
#=============================================================

sub problem_files_in_directory {

    my ($dir) = @_;

    my @files = (glob ("$dir/*"),glob ("$dir/.*")); # include invisible files
    my @problemFiles = ();

    foreach my $file (@files){
	if (! -r $file || ! -w $file){
	    push(@problemFiles, $file);
	    # could return at this point 
	}	
    }
# could give full list of problem files
    return @problemFiles;
}


exit($exit_status);
