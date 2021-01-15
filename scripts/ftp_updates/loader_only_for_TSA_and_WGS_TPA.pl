#!/ebi/production/seqdb/embl/tools/bin/perl
#
#
# loader.pl <user/passw@instance> <collaborator> <entry type>
#
#   Processes and load all new files for the colaborator and entry type specified.
#
#   <collaborator> is one of: 'ncbi' or 'ddbj'
#   <entry type> is one of: '-normal', '-tpa', '-con', '-wgs', '-ann'
# Calls in turn:
#   - gunzip
#   - duplication_anti_load.pl
#   - fix_exchange.pl
#   - wgs_loader.pl if entry type is wgs, mga_loader.pl if entry type is mga
#
#  Sometime    F. Nardone    Created
#  31-Mar-2005     "         fixed tarring of logs
#  13-JUN-2005     "         Do not use project when submitting wgs loader
#                             so we don't get a deadlock if there are more than 5
#                             sets to load.
#   9-SEP-2005     "         sub load_normal uses load_all (as it should have been since the beginning)
#  16-JAN-2006     "         fixed load_wgs so it makes correct chunks.
#  20-OCT-2006     "         ported to anthill
#  21-OCT-2006     "         Do not use 'uncompress' but use 'gunzip' for *.Z files
#

use warnings;
use strict;
use diagnostics;
use Data::Dumper;

use FtpUpdates::Config_only_for_TSA_and_WGS_TPA;
use FtpUpdates::Loader;
use Utils qw(my_opendir my_open my_system my_rename my_unlink);
use Lsf;
use Mailer;
use Putff;
use Lockfile;

use File::Basename;
# "$config->{LOADER} $dbconn $collaborator $type $verbose";

$" = "\n";

main();

sub main {

    my ( $dblogin, $collaborator, $type, $type_code, $key , $verb, $test) = get_args();

    if ( $type =~ /-bqv/i ) {
	   print STDERR "Loader called with bqv flag.  Exiting loader.pl...\n";
	   return(1);
    }
    
    print "key 5=$key \n";

    my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = FtpUpdates::Config_only_for_TSA_and_WGS_TPA->get_config( $collaborator, $type_code, $key , $verb, $test);

    my ($LOCK);

    if (-e $config->{lockfile}) {

	  my $processes = check_for_processes_running($config);

	  if (!$processes) {
	    #renew lock
	    system("rm $config->{lockfile}");
	    $LOCK = Lockfile->new( $config->{lockfile} );
	  }
	  else {
	    # don't allow script to run because lock and active processes are present
	    die( "$collaborator ".$config->{entry_type_name}." locked by ".$config->{lockfile}.": loading aborted\n\n" );
	  }
    }
    else {
	   $LOCK = Lockfile->new( $config->{lockfile} );
    }

    # Uncompress new files
    print STDERR "\n#Uncompress new files.\n" if ( $config->{VERBOSE} );
    uncompress( $config );
    
    # Merge duplicate features
    print STDERR "\n#Merge duplicate features\n" if ( $config->{VERBOSE} );
    merge_duplicates( $config );

    # Fix known errors
    print STDERR "\n#Fixing\n" if ( $config->{VERBOSE} );
    fix_known_errors( $config );

    print STDERR "\n#Loading\n" if ( $config->{VERBOSE} );
    print "config entry_type_name=". $config->{entry_type_name}."\n";
    if ($config->{entry_type_name} =~ /WGS/i || $config->{entry_type_name} =~ /TSA/i ) {
	print STDERR "Running load_wgs() in loader.pl\n" if ($config->{VERBOSE});
	load_wgs($config, $dblogin, $type_code, $key , $verb, $test);
    }
    elsif ($config->{entry_type_name} =~ /TPA/i) {
	print STDERR "Running load_tpa() in loader.pl\n" if ($config->{VERBOSE});
	load_tpa($config, $dblogin);
    }
    elsif ($config->{entry_type_name} =~ /CON/i) {
	print STDERR "Running load_con() in loader.pl\n" if ($config->{VERBOSE});
	load_con($config, $dblogin);
    }
    elsif ($config->{entry_type_name} =~ /NORMAL/i) {
	print STDERR "Running load_normal() in loader.pl\n" if ($config->{VERBOSE});
	load_normal($config, $dblogin);
    }

    print STDERR "loading done\n";

    # Tar all lsf reports in one handy file
    print STDERR "#Grouping Reports\n" if ( $config->{VERBOSE} );
    group_lsf_reports( $config );
    print STDERR "grouping done\n";


    print STDERR "#Removing lock\n" if ( $config->{VERBOSE} );
    $LOCK->remove();
    print STDERR "unlocking done\n" if ( $config->{VERBOSE} );
}

sub check_for_processes_running {
    # find out if there are actually processes running
    # since a lock file has been found

    #my FtpUpdates::Config $config = shift( @_ );
    my $config = shift( @_ );
    my ($process_id, @processes, $grepCmd);

    open(READLOCK, "<".$config->{lockfile}) || print "Could not open lock file $config->{lockfile} to check for process id\n";
    while (<READLOCK>) {
	if ($_ =~ /Process id of script run : (\d+)/) {
	    $process_id = $1;
	    last;
	}
    }
    close(READLOCK);
    
    $grepCmd = "ps -fu datalib | grep $process_id | grep loader.pl | grep -v 'ps -fu'";
    @processes = `$grepCmd`;
    print STDERR "$grepCmd: ".scalar(@processes)." processes found\n" if ( $config->{VERBOSE} );
    
    return(scalar(@processes));
}

sub uncompress {
  # Uncompresses all files in the $config{ftp_local_dir} to the
  # $config{uncompressed_local_dir} using 'uncompress' or 'gunzip' as
  # appropriate.
  # The compressed file is removed

  my $config = shift( @_ );

  my $all_files_ar = get_all_files( $config->{ftp_local_dir} );

  my @files_gzip = grep( /\.(?:Z|gz)$/, @$all_files_ar );
  my @files_to_just_move = grep( m/$config->{grab_orig_file_name_pattern}$/, @$all_files_ar );

  my @unzip_jobs;
  foreach my $gzipped_file ( @files_gzip ) {

    my $command = "gunzip $config->{ftp_local_dir}/$gzipped_file";
    print( STDERR "$command\n" ) if ( $config->{VERBOSE} );
    push( @unzip_jobs, bsub( $config->{LSF_QUEUE}, $command, "$config->{logs_dir}/gunzip.LSF.log" ) );
  }

  if ( bwait( @unzip_jobs ) ) {

    die( "Compression failed" );
  }

  foreach my $file_name ( @files_gzip, @files_to_just_move ) {

    print STDERR "#$file_name#\n";
    $file_name =~ s/\.(?:Z|gz)$//; # Remove the suffix

    my $command;
    if ( -s( "$config->{ftp_local_dir}/$file_name" ) > 0 ) {
      $command = "mv $config->{ftp_local_dir}/$file_name $config->{uncompressed_dir}";
    } else { # remove empty files
      $command = "rm $config->{ftp_local_dir}/$file_name";
    }
    print( STDERR "$command\n" ) if ( $config->{VERBOSE} );
    my_system( $command );
  }
}

sub merge_duplicates {
  # Calls the feature duplication removeal script 'duplication.pl' for all the
  # files in $config->{uncompressed_dir}.
  # The processed files are moved to $config->{unduplicated_dir}.
  # The original files are removed.

  my $config = shift( @_ );

  my $files_ar = get_all_files( $config->{uncompressed_dir} );

  my @jobs;
  foreach my $file_name ( @$files_ar ) {

    my $command = "$config->{DUPLICATION} $config->{uncompressed_dir}/$file_name ".
                   "$config->{unduplicated_dir}/.$file_name";

    print( STDERR "$command\n" ) if ( $config->{VERBOSE} );
    push( @jobs, bsub( $config->{LSF_QUEUE}, $command, "$config->{logs_dir}/duplication.LSF.log" ) );
  }

  if ( bwait( @jobs ) ){

    die( "duplication failed" );
  }
  print STDERR "Done.\n" if ( $config->{VERBOSE} );

  remove_orig_and_rename_new( $files_ar, $config->{uncompressed_dir}, $config->{unduplicated_dir} );
}

sub fix_known_errors {
  # Calls fixncbi for all the files in $config->{uncompressed_dir}.
  # The processed files ends up in $config->{fixed_dir}.
  # The original files are removed.
  #
  my $config = shift( @_ );

  my @jobs;

  my $files_ar = get_all_files( $config->{unduplicated_dir} );

  foreach my $file_name ( @$files_ar ) {

    my $command = "$config->{FIXNCBI} $config->{unduplicated_dir}/$file_name $config->{fixed_dir}/.$file_name";
    print( STDERR "$command\n" ) if ( $config->{VERBOSE} );
    push( @jobs, bsub( $config->{LSF_QUEUE}, $command, "$config->{logs_dir}/fixncbi.LSF.log" ) );
  }

  if ( bwait( @jobs ) ){
    die( "$config->{FIXNCBI} failed" );
  }

  remove_orig_and_rename_new( $files_ar, $config->{unduplicated_dir}, $config->{fixed_dir} );

  print STDERR "Done.\n" if ( $config->{VERBOSE} );
}

sub load_all {
  # Load all files in $config->{fixed_dir} using putff.
  # The error files are moved to the $config->{load_error_dir}
  # The original files are moved to the $config->{archive_data_dir}
  # RETURN: an array containing an arrayref of all the filenames
  #         treated succesfully and an arrayref of all filenames
  #         for which putff exited.
  #

  my $config = shift( @_ );
  my ( $dblogin ) = @_;

  print "moving error files from $config->{fixed_dir} to $config->{load_error_dir}\n";
  move_error_files( $config->{fixed_dir}, $config->{load_error_dir} );
  my $files_ar = get_all_files( $config->{fixed_dir} );

  my $jobs = load_files( $config, $dblogin, $files_ar );

  my $failed_ar = bwait_ids( keys(%$jobs) );

  my @failed_files;
  foreach my $job_id ( @$failed_ar ) {

    if ( defined ( my $fname = $jobs->{$job_id} ) ) {

      push( @failed_files, $fname );
      my_rename( "$config->{fixed_dir}/$fname", "$config->{fatal_error_dir}/$fname" );
      delete( $jobs->{$job_id} );
    }
  }

  return ( [values(%$jobs)],
           \@failed_files   );
}

sub load_normal {
  # Load normal entries

  my $config = shift( @_ );
  my ( $dblogin ) = @_;

  print "load_all called from load_normal\n";
  my ( $loaded_ar, $failed ) = load_all( $config, $dblogin );

  cleanup_loaded_files( $config, $loaded_ar );
}

sub load_con {
  # Load CON entries

  my $config = shift( @_ );
  my ( $dblogin ) = @_;

  print "load_all called from load_con\n";
  my ( $loaded_ar, $failed ) = load_all( $config, $dblogin );

  send_report( $config, $loaded_ar, $failed );

  cleanup_loaded_files( $config, $loaded_ar );
}

sub load_tpa {
  # Load TPA entries

  my $config = shift( @_ );
  my ( $dblogin ) = @_;

  print "load_all called from load_tpa\n";
  my ( $loaded_ar, $failed ) = load_all( $config, $dblogin );

  send_report( $config, $loaded_ar, $failed );

  cleanup_loaded_files( $config, $loaded_ar );
}


sub send_report {
  # Send mails reporting number of entries processed
  # and files that caused fatal errors.

  my $config = shift( @_ );
  my ( $loaded_ar, $failed_ar ) = @_;

  foreach my $fname ( @$loaded_ar ) {

    mail_file_loading_report( $config, $fname );
  }

  if ( exists($failed_ar->[0]) ) {

    mail_failed_files_report( $config, $failed_ar );
  }
}


sub mail_file_loading_report {
  # Send a mail reporting the number of entries stored, changed, unchaged
  # Reads the info from the summary file.

  my $config = shift( @_ );
  my ( $fname ) = @_;

  my %status;
  my $msg;
  my $log_fname = "$config->{logs_dir}/$fname.$config->{putff_log_suffix}";
  if ( -f( $log_fname ) ) {

    @status{qw/stored failed unchanged/} = Putff::parse_err_file( $log_fname );

    $msg = "$fname\n".
    "\n".
    sprintf( "stored    = %8d\n", $status{stored} ).
    sprintf( "failed    = %8d\n", $status{failed} ).
    sprintf( "unchanged = %8d\n", $status{unchanged} ).
    "--------------------\n".
    sprintf( "parsed    = %8d\n", $status{stored} + $status{failed} + $status{unchanged} ).
    "\n".
    "======================\n".
    "\n";

    if ( $status{failed} > 0 ) {

      $msg .= "$status{failed} error files are in $config->{load_error_dir}.\n";
    }

  } else {

    $msg = "ERROR: cannot find $log_fname.\n".
    "Cannot create loading report.\n";
  }

  my $subject;
  if($config->{entry_key_name}  eq 'TPA_WGS'){
    $subject = "$config->{entry_type_name} ($config->{entry_key_name}) loading report";
  }
  else{
    $subject = "$config->{entry_type_name} loading report";
  }
  send_mail( { to      => $config->{notification_addresses},
	       subject => $subject,
	       body    => $msg } );
}


sub mail_failed_files_report {
  # Send a mail reporting the names of all files that
  # caused a fatal error
  #
  my $config = shift( @_ );
  my ( $fnames_ar ) = @_;

  my $msg = "These files generated a fatal error while loading:\n".
         join( ', ', @$fnames_ar ) ."\n".
         "They can be found in $config->{fatal_error_dir}\n";
  my $subject;
  if($config->{entry_key_name}  eq 'TPA_WGS'){
    $subject = "$config->{entry_type_name} ($config->{entry_key_name} ) loading failure report";
  }
  else{
    $subject = "$config->{entry_type_name} loading failure report";
  }
  send_mail({ to      => $config->{notification_addresses},
              subject => $subject,
              body    => $msg                                         } );
}


sub load_wgs {
  # Submit a loading job for each set
  # Do only 3 at a time to avoid Lsf deadlocks when we
  #  reach queue capacity  #

  my $config = shift( @_ );
  my ($dblogin,$type_code,$key ,$verb,$test) = @_;

  my @sets = get_wgs_sets_to_load( $config );

  my $step = 21;
  for ( my $i=0; $i <= $#sets; $i += $step ) {

    my $end = $i + $step - 1;
    if ($end > $#sets) {

      $end = $#sets;
    }
    my @chunk = @sets[$i .. $end];
    print "Now running load_wgs_sets( config, $dblogin, chunk ) where chunk is:\n". join("\n",@chunk)."\n";
    load_wgs_sets( $config, $dblogin, $type_code, $key ,\@chunk,$verb,$test );
  }
}

sub load_wgs_sets {

  my $config = shift( @_ );
  my ($dblogin, $type_code, $key , $sets, $verb, $test) = @_;

  my %jobs;
  foreach my $set ( @$sets ) {
    my $command = "$config->{WGS_LOADER} $dblogin $config->{collaborator} $type_code $key  $set $verb $test > $config->{logs_dir}/$set.loader.log 2>&1";
   # my $command = "$config->{WGS_LOADER} $dblogin $config->{collaborator} $set > $config->{logs_dir}/$set.loader.log 2>&1";
    print STDERR "$command\n";
    my $job_id = bsub( $config->{LSF_QUEUE}, $command, "$config->{logs_dir}/$set.LSF.log" );
    $jobs{$job_id} = $set;
  }

  my $failed_ar = bwait_ids( keys( %jobs ) );
  if ( @$failed_ar ) {

    foreach my $failed_job ( @$failed_ar ) {

      my $set = $jobs{$failed_job};
      my $subject;
      if($config->{entry_key_name}  eq 'TPA_WGS'){
	$subject = "ERROR: $config->{entry_type_name} ($key ) loading $set";
      }
      else{
	$subject =  "ERROR: $config->{entry_type_name} loading $set";
      }
      send_mail( { to      => $config->{notification_addresses},
                   subject => $subject,
                   body    => "There was a fatal error while trying to load this set.\n".
                              "See the log at $config->{logs_dir}/$set.loader.log"           } );
    }
  }
}

sub get_wgs_sets_to_load {
  # Returns an array of all the set id waiting to be loaded  #

  my $config = shift( @_ );

  my $files_ar  = get_all_files( $config->{fixed_dir} );

  print STDERR "There are ".scalar(@$files_ar)." files found in $config->{fixed_dir}\n";

  my %set_ids;
  foreach my $fname ( @$files_ar ) {

    if ( $fname =~ m/$config->{get_set_id_pattern}/ ) {
      print "$fname matches $config->{get_set_id_pattern}\n";
      $set_ids{$1} = 1;
    }
    else {
        print STDERR "$fname does not match $config->{get_set_id_pattern}\n";
    }
  }

  return keys( %set_ids );
}

sub remove_orig_and_rename_new {
  # removes the original file and rename the dot file
  #
  my ( $files_ar, $orig_dir, $new_dir ) = @_;

  foreach my $file_name ( @$files_ar ) {

    my_unlink( "$orig_dir/$file_name" );
    my_rename( "$new_dir/.$file_name", "$new_dir/$file_name" );
  }
}

sub group_lsf_reports {
  my FtpUpdates::Config $config = shift( @_ );

  group_reports( $config, 'LSF' );
  group_reports( $config, 'putff' );
  group_reports( $config, 'loader' ); # only WGS have this

  my $num_log_files = `ls -1 $config->{logs_dir} | wc -l`;
  if ($num_log_files > 0) { # turns $num_log_files into a number from a string
      system( "chmod 0677 $config->{logs_dir}/*" );
  }
}

sub group_reports {
  my $config = shift;
  my $name = shift;

  my $dh =  my_opendir( $config->{logs_dir} );
  my @files = grep( /^[^\.].*\.$name\.log/, readdir( $dh ));
  closedir( $dh ) or die( "ERROR: cannot close '$config->{logs_dir}'\n$!" );

  chdir( $config->{logs_dir} ) or die( "ERROR: cannot chdir to '$config->{logs_dir}'.\n$!" );
  if (@files) {
    my ($day, $month, $year) = (localtime( time() ))[3, 4, 5];# today's date
    $month++;
    $year += 1900;
    my $tar_fname = sprintf( "%d%02d%02d_$name.report.tar", $year, $month, $day);

    unless( -f($tar_fname) ) {

      my $fname = shift( @files );
      my $cmd = "tar -cvf $tar_fname $fname || [[ \$\? -eq 1 ]]";# create archive
      #my $cmd = "tar --ignore-failed-read -cvWf $tar_fname $fname";# create archive
      #my $cmd = "tar -cvWf $config->{logs_dir}/$tar_fname $config->{logs_dir}/$fname || [[ $? -eq 1 ]]" if (-e($config->{logs_dir}/$fname));# create archive 
      print "$cmd\n";
      my_system( $cmd );
      my_unlink( $fname );
    }

    foreach my $fname ( @files ){
      my $cmd = "tar -rvf $tar_fname $fname || [[ \$\? -eq 1 ]]"; # Add to archive
      #my $cmd = "tar --ignore-failed-read -rvf $tar_fname $fname"; # Add to archive
      #my $cmd = "tar -rvf $config->{logs_dir}/$tar_fname $config->{logs_dir}/$fname || [[ $? -eq 1 ]]" if (-e($config->{logs_dir}/$fname));# add to archive
      print "$cmd\n";
      my_system( $cmd );
      my_unlink( $fname );
    }
  }
}


sub get_args {
  # Checks and returns the command line arguments
  #

  my ( $dblogin, $collaborator, $type, $key , $verb, $test ) = @ARGV;

  my $USAGE = "$0 <user/passw\@instance> <collaborator> <entry type> <verbose>\n".
              "\n".
              "  Processes and load all new files for the colaborator and entry type specified.\n".
              "\n".
              "  <collaborator> is one of: '". NCBI ."', '". DDBJ ."'\n".
              "  <entry type> is one of: '-normal', '-tpa', '-con', '-wgs', '-ann'\n".
	      "  <verbose> is an optional flag to give more detail: '-v' alternatively '1' or '0'\n".
              "\n";

  unless( defined( $type ) ) {
    disable diagnostics;
    die( $USAGE );
  }

#  my $type_code =  { -normal => TYPE_NORMAL,
#                     -tpa    => TYPE_TPA,
#                     -con    => TYPE_CON,
#                     -wgs    => TYPE_WGS   }->{$type};
  my ($type_code);

  if ( $type =~ /-normal/i ) {
      $type_code = 'TYPE_NORMAL';
  }  
  elsif ( $type =~ /-_wgs_w_wgs/i ) {
      $type_code = 'TYPE_TPA';
  }
  elsif ( $type =~ /-con/i ) {
      $type_code = 'TYPE_CON';
  }
  elsif ( $type =~ /-wgs/i ) {
      $type_code = 'TYPE_WGS';
  }
  elsif ( $type =~ /-tsa/i ) {
      $type_code = 'TYPE_TSA';
  }
  elsif ( $type =~ /-bqv/i ) {
      $type_code = 'TYPE_BQV';
  }
  elsif (( $type =~ /-mga/i ) && ( $collaborator =~ /DDBJ/i )) {
      $type_code = 'TYPE_MGA';
  }

  unless( defined( $type_code ) ) {
    disable diagnostics;
    die( "'$type' is not a recognised entry type.\n\n$USAGE" );
  }

  unless ( $collaborator =~ /(NCBI|DDBJ)/i ) {

      disable diagnostics;
      die( "'$collaborator' is not a recognised collaborator name.\n\n$USAGE" );
  }

  if (defined($verb) && ($verb =~ /^-v/i)) {
      $verb = 1;
  }
  else {
      $verb = 0;
  }
print "here3 key=$key \n";
  return ( $dblogin, $collaborator,$type, $type_code, $key , $verb, $test );
}

