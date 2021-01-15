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
#
#  20 June 2006 F. Nardone    Created
#  26 Oct  2006    =="==      Ported to anthill
#

use warnings;
use strict;
use diagnostics;
use Data::Dumper;
use DBI;

use FtpUpdates::Config;
use FtpUpdates::Loader;
use Utils qw(my_opendir my_open my_system my_rename my_unlink);
use Lsf;
use Mailer;
use Putff;
use Lockfile;

use File::Basename;

main();

sub main {

  my ( $dblogin, $collaborator, $verb ) = get_args();

  my FtpUpdates::Config $config = FtpUpdates::Config->get_config( 
    $collaborator, 'TYPE_MGA', $verb );

  my $LOCK = Lockfile->new( $config->{lockfile} );

  if ( $LOCK == 0 ) {

    print( STDERR "Loading $collaborator $config->{entry_type_name} locked.\n" );
    exit;
  }

  $config->dump_all();

  uncompress( $config );

  # Create flatfile
  merge_header_master( $config );

  print STDERR "\n#Loading\n" if ( $config->{VERBOSE} );
  
  my ( $loaded_ar, $failed ) = load_mga( $config, $dblogin );
  cleanup_loaded_files( $config, $loaded_ar );  

  print STDERR "loading done\n";

  # Tar all lsf reports in one handy file
  print STDERR "#Grouping Reports\n" if ( $config->{VERBOSE} );
  group_lsf_reports( $config );
  
  $LOCK->remove();
}

sub uncompress {
  # Uncompresses all files in the $config{ftp_local_dir} to the
  # $config{uncompressed_local_dir} using 'uncompress' or 'gunzip' as
  # appropriate.
  # The compressed file is removed

  my FtpUpdates::Config $config = shift( @_ );

  my $all_files_ar = get_all_files( $config->{ftp_local_dir} );

  my @files_compress = grep( m/\.Z$/, @$all_files_ar );
  my @files_gzip = grep( m/\.gz$/, @$all_files_ar );
  my @files_to_just_move = grep( m/$config->{grab_orig_file_name_pattern}$/, @$all_files_ar );

  my @decompress_jobs;
  foreach my $compressed_file ( @files_compress ) {

    my $command = "gunzip $config->{ftp_local_dir}/$compressed_file";
    print( STDERR "$command\n" ) if ( $config->{VERBOSE} );
    push( @decompress_jobs, bsub( $config->{LSF_QUEUE}, $command, "$config->{logs_dir}/uncompress.LSF.log" ) );
  }

  foreach my $gzipped_file ( @files_gzip ) {

    my $command = "gunzip $config->{ftp_local_dir}/$gzipped_file";
    print( STDERR "$command\n" ) if ( $config->{VERBOSE} );
    push( @decompress_jobs, bsub( $config->{LSF_QUEUE}, $command, "$config->{logs_dir}/gunzip.LSF.log" ) );
  }

  if ( bwait( @decompress_jobs ) ) {

    die( "Compression failed" );
  }

  foreach my $file_name ( @files_compress, @files_gzip, @files_to_just_move ) {

    print STDERR "#$file_name#\n";
    $file_name =~ s/\.(?:Z|gz)//; # Remove the suffix

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

sub merge_header_master {

  my FtpUpdates::Config $config = shift( @_ );

  my $files = get_all_files( $config->{uncompressed_dir} );

  my %masters;
  my %variables;
  foreach my $fname ( @$files ) {

    if ( $fname =~ m/^([A-Z]{5})_master/ ) {

      $masters{$1} = $fname;
    
    } elsif ( $fname =~ m/^([A-Z]{5})_variable/ ) {

      $variables{$1} = $fname;
    }
  }

  my @commands;
  foreach my $set ( keys(%masters) ) {

    if ( not exists($variables{$set}) ) {
      die( "ERROR: '$masters{$set}' has no corresponding variable file.\n" );
    }

    my $command = "$config->{FIXMGA} $config->{uncompressed_dir}/$masters{$set} ".
    "$config->{uncompressed_dir}/$variables{$set} > $config->{fixed_dir}/.$set.dat; ".
    "rm $config->{uncompressed_dir}/$masters{$set}; rm $config->{uncompressed_dir}/$variables{$set};".
    "mv $config->{fixed_dir}/.$set.dat $config->{fixed_dir}/$set.dat";

    push( @commands, LsfCommand->new({command => $command,
                                      queue   => $config->{LSF_QUEUE},
                                      log     => "$config->{logs_dir}/$set.LSF.log" }) );
  }

  eval {
    execute_in_parallel( \@commands );
  };
  if ( $@ ) {

#     send_mail( { to      => 'mjang@ebi.ac.uk', ####$config->{notification_addresses},
#                   subject => "ERROR: MGA loading",
#                   body    => "There was a fatal error while trying to load MGA.\n".
#                              "$@\n"           } );

      die $@;
  }
}

sub load_mga {
  # Load all files in $config->{fixed_dir} using plain putff.
  # The error files are moved to the $config->{load_error_dir}
  # The original files are moved to the $config->{archive_data_dir}
  # The accno prefix of the MGA set is added to the databse if not already there
  # RETURN: an arrayref containing all the filenames treated succesfully and an
  #         arrayref of all filenames for wich putff exited.
  #

  my FtpUpdates::Config $config = shift( @_ );
  my ( $dblogin ) = @_;

  move_putff_error_files( $config->{fixed_dir} );
  my $files_ar = get_all_files( $config->{fixed_dir} );
  @$files_ar = grep( !m/\.summary\.xml$/, @$files_ar );

  add_accno_prefixes( $config, $dblogin, $files_ar );

  my $jobs = load_files( $config, $dblogin, $files_ar );

  my $failed_ar = bwait_ids( keys(%$jobs) );

  my @failed_files;
  foreach my $job_id ( @$failed_ar ) {

    my $fname = $jobs->{$job_id};
    push( @failed_files, $fname );
    move_error_same_pub( $config, $fname );
    delete( $jobs->{$job_id} );
  }

  return ( [values(%$jobs)], \@failed_files );
}

sub add_accno_prefixes {

  my FtpUpdates::Config $config = shift( @_ );  
  my ( $dblogin, $files_ar ) = @_;
  $dblogin =~ s/^\/?\@?//;
  my $dbh = DBI->connect ("dbi:Oracle:$dblogin",'', '',
    {PrintError => 0, AutoCommit => 0, RaiseError => 1});

  foreach my $this_file ( @$files_ar ) {
   
    my ($prefix) = $this_file =~ m/$config->{get_set_id_pattern}/;

    if ( $prefix ) {
 
      my ($exists) = $dbh->selectrow_array( "SELECT prefix FROM cv_database_prefix WHERE prefix = '$prefix'" );

      if ( not $exists ) {

        $dbh->do( "INSERT INTO cv_database_prefix (prefix, dbcode, entry_type) 
          VALUES ('$prefix', '$config->{db_code}', 'MGA')" );
      }
    
    } else {

      die( "ERROR: bad file name '$this_file'" );
    }
  }
  
  $dbh->disconnect();
}

sub group_lsf_reports {
  my FtpUpdates::Config $config = shift( @_ );

  group_reports( $config, 'LSF' );
  group_reports( $config, 'putff' );
  group_reports( $config, 'loader' ); # only WGS have this
  group_reports( $config, 'clonepub' );
}

sub group_reports {
  my FtpUpdates::Config $config = shift;
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
      my $cmd = "tar cf $tar_fname $fname";# create archive
      my_system( $cmd );
      my_unlink( $fname );
    }

    foreach my $fname ( @files ){
  
      my $cmd = "tar rf $tar_fname $fname";# add to archive
      my_system( $cmd );
      my_unlink( $fname );
    }
  }
}


sub get_args {
  # Checks and returns the command line arguments
  #

  my ( $dblogin, $collaborator, $verb ) = @ARGV;

  my $USAGE = "$0 <user/passw\@instance> <collaborator>\n".
              "\n".
              "  Processes and load all new files for the colaborator and entry type specified.\n".
              "\n".
              "  <collaborator> is one of: '". NCBI ."', '". DDBJ ."'\n".
              "\n";

  unless( defined($collaborator) ) {
    disable diagnostics;
    die( $USAGE );
  }

  unless ( $collaborator eq NCBI ||
           $collaborator eq DDBJ   ) {

      disable diagnostics;
      die( "'$collaborator' is not a recognised collaborator name.\n\n$USAGE" );
  }

  if (defined($verb) && ($verb =~ /^-v/i)) {
      $verb = 1;
  }
  else {
      $verb = 0;
  }

  return ( $dblogin, $collaborator, $verb );
}

