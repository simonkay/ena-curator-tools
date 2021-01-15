#!/ebi/production/seqdb/embl/tools/bin/perl
#
# ftp.pl <user/passw@instance> <collaborator> <entry type> <verbose>
#    Downloads by ftp all new files for the entry type specified.
#    <entry type> is one of: '-normal', '-tpa', '-con', '-wgs', '-bqv', '-ann', '-mga'
#
# After downloading it call the loader utils (loader.pl) which loads
#  entries in the database.
# If the entry type is mga calls mga_loader.pl instead.
#
# 13-JUN-2004 F.Nardone   Created

#use lib "/nfs/production/seqdb/embl/developer/blaise/prog/tools/perllib";
use diagnostics;
use warnings;
use strict;
use Net::FTP::AutoReconnect;
use SeqDBUtils2;
use FtpUpdates::Config;
use Utils qw(my_open printfile my_rename my_system);
use Mailer;

my $exit_status = 0;

main();

sub main {

  my ( $dbconn, $collaborator, $type, $type_code, $verbose ) = get_args();
  print STDERR `date`;


  my FtpUpdates::Config $config = FtpUpdates::Config->get_config( $collaborator, $type_code, $verbose );
  $config->dump_all();

  eval {

    my $ftp = get_ftp( $config );

    my $last_loaded = get_last_loaded( $config );

    unload_new_files( $config, $ftp, $last_loaded );

    $ftp->quit();
    print STDERR "ftp finished\n";

    if ( $config->{entry_type} ne 'TYPE_BQV' ) {
     
      my $comm = "$config->{LOADER} $dbconn $collaborator $type $verbose";
      print STDERR "launching loader:\n'$comm'\n";
      # Run each loader job on LSF
#      system("bsub -q production-rh7 ", $comm );
      system( $comm );
    }
    else {
	print STDERR "TYPE_BQV found - Not running loader.pl\n";
    }
  };

  if ( $@ ) {
    # don't die if lock found.
    print STDERR $@;
  }

}


sub get_ftp {

  my FtpUpdates::Config $config = shift( @_ );

  my $ftp_addr = $config->{ftp_addr};

  $config->{VERBOSE} && print( STDERR "Connecting to: $ftp_addr\n" );

  my $ftp;
  
  # try 7 times before giving up
  my $i;
  for ( $i = 1; $i <= 7; ++$i ) {

    $ftp = Net::FTP::AutoReconnect->new( $ftp_addr, Timeout => 3000 ) ;

    if ( defined ( $ftp ) ) {
      last;
    } else {
      sleep( 1 );
      next;
    }
  }

  if ( not defined ( $ftp ) ) {
    
    print( "Cannot connect to '$ftp_addr' after $i attempts.\n$@" );
    exit($exit_status);
  }
  $config->{VERBOSE} && print( STDERR "  Connected in $i attempts.\n" );

  my $uname = $config->{ftp_uname};
  my $passw = $config->{ftp_passw};

  $config->{VERBOSE} && print( STDERR "  Logging in.\n" );
  $ftp->login( $uname, $passw ) or
    die( "Cannot login to '$ftp_addr'\n". $ftp->message );

  $ftp->binary();

  $config->{VERBOSE} && print( STDERR "Done\n" );

  return $ftp;
}


sub get_last_loaded {

  my FtpUpdates::Config $config = shift( @_ );

  my $fh = my_open( $config->{last_loaded_fname} );
  my $last_loaded = <$fh>;
  close( $fh );

  chomp( $last_loaded );
  $config->{VERBOSE} && print( STDERR "Last loaded: $last_loaded, '". localtime($last_loaded) ."'\n" );
  return $last_loaded;
}


sub unload_new_files {

  my FtpUpdates::Config $config = shift( @_ );
  my ( $ftp, $last_loaded ) = @_;

  my $remote_dir = $config->{ftp_remote_dir};
  my @remote_ftp_sub_dirs = @{$config->{remote_ftp_sub_dirs}};
  my $local_dir = $config->{ftp_local_dir};
  my $name_pattern = $config->{file_name_pattern};
  
  $config->{VERBOSE} && print( STDERR "Getting file names\n" );
  
  $ftp->cwd( $remote_dir ) or
              die( "Cannot cwd to '$remote_dir'" );
  
  if (@remote_ftp_sub_dirs == 0) {
        # No sub-directories
        $config->{VERBOSE} && print( STDERR "Looking inside remote directory '$remote_dir'\n" );

        my $file_names_hr = get_file_names( $config, $ftp, $last_loaded );
        my $new_last_loaded = unload_files( $config, $ftp, $file_names_hr );

        return $new_last_loaded;

  } else {
        # Several sub-dirs - loop through each dir in turn, getting the file names and unloading
        my $max_last_loaded = 0;
        my $first = 1;

        foreach my $dir_name ( @remote_ftp_sub_dirs ) {
            print "*"x100,"\n";
			print "Processing $dir_name in $remote_dir\n";
            if ($first == 1) {
                $ftp->cwd( $dir_name ) or
                      die( "Cannot cwd to '$dir_name'" );
                $first = 0;
            } else {
                # Must change up from previous sub-dir
                # But if this doesn't exist assume that we have searched all current sub dirs 
                $ftp->cwd( "../" . $dir_name ) or last;
            }
        
            $config->{VERBOSE} && print( STDERR "Looking inside remote directory '$remote_dir$dir_name'\n");

            my $file_names_hr = get_file_names( $config, $ftp, $last_loaded );
		    print "*" x100,"\n";
		    print "\nFile names to download\n";
			print $file_names_hr,"\n";
		    print "*" x100,"\n";
		
            my $new_last_loaded = unload_files( $config, $ftp, $file_names_hr );
            $max_last_loaded = max( $max_last_loaded, $new_last_loaded );
        }
		#return '';
        return $max_last_loaded;
  }
}


sub get_file_names {

  my FtpUpdates::Config $config = shift( @_ );
  my ( $ftp, $last_loaded ) = @_;

#  my $remote_dir = $config->{ftp_remote_dir};
  my $name_pattern = $config->{file_name_pattern};

#  $ftp->cwd( $remote_dir ) or
#    die( "Cannot cwd to '$remote_dir'" );

  my @dirlist = $ftp->ls();

  $, = "\n";
  # $config->{VERBOSE} && print 'Dir list:', @dirlist, "\n";

  my @all_files = grep( m/$name_pattern/, @dirlist );

  # $config->{VERBOSE} && print "\n\nMatching files:", @all_files, "\n";

  my (%new_files, $line, $retr_file, $retr_date, $retr_timestamp, %retr_files);

  # get info on files previously retrieved to check against new file
  if (-e $config->{retrieved_files_fname}) {
      open(READRETRIEVED, "<".$config->{retrieved_files_fname}) || print "WARNING: Could not read ".$config->{retrieved_files_fname}." in order to check if a new file in the ftp list has been retrieved previously\n\n";
      while ($line = <READRETRIEVED>) {
	  ($retr_file, $retr_date, $retr_timestamp) = split(/\t/, $line);
	  $retr_files{$retr_file} = $retr_date;
      }
      close(READRETRIEVED);
  }


  foreach my $file_name ( @all_files ) {

    my $timestamp; # Ftp module has been frequently failing to retreive timestamp of different ncbi wgs files
    for (my $i = 0; ($i < 10) && !defined($timestamp); $i++) {
	$timestamp = $ftp->mdtm( $file_name );
    }
    if ($config->{VERBOSE}) {
	print STDERR "filename = $file_name : " ;
	if (defined($timestamp)) {
	    print STDERR "timestamp = $timestamp " ;
	} else {
	    print STDERR "timestamp = UNDEFINED " ;
	}
	print STDERR "last_loaded = $last_loaded " ;
    }

    if ( $timestamp > $last_loaded ) {

      $config->{VERBOSE} && print( STDERR "will take it\n" );
      $new_files{$file_name} = $timestamp;

      # if the file has a new timestamp and is already listed as having been downloaded...
      if (($config->{entry_type} ne 'TYPE_WGS') && (defined($retr_files{$file_name}))) {
	 print STDERR "WARNING: $file_name appears to be new but it already exists in the list of retrieved files (".$config->{retrieved_files_fname}.").  It was originally dated ".$retr_files{$file_name}.".  This file is being downloaded automatically as part of the normal pipeline process.\n";
      }

    } else {

      $config->{VERBOSE} && print( STDERR "too old\n" );
	# if the file has an old timestamp but isn't listed as having been downloaded...
      if (! defined($retr_files{$file_name})) {
          # prompt bioinformatician to go and get it!
          print STDERR "WARNING: $file_name pre-dates the lastloaded timestamp but isn't in the list of retrieved files (".$config->{retrieved_files_fname}.").  This file is awaiting _manual_ download at this time (and manually add the filename to the bottom of the Retrieved_files_".'*'." file).\n";
      }
    }
  }

  return \%new_files;
}


sub unload_files {

  my FtpUpdates::Config $config = shift( @_ );
  my ( $ftp, $file_names_hr ) = @_;

  my $local_dir = $config->{ftp_local_dir};

  my $max_timestamp = 0;

  open(WRITERETRIEVED, ">>".$config->{retrieved_files_fname}) || print "WARNING: Could not append to ".$config->{retrieved_files_fname}." which lists all files retrieved\n\n";

  my @fnames_by_timestamp = sort {
                              $file_names_hr->{$a} cmp $file_names_hr->{$b}
                            } keys %$file_names_hr;

  foreach my $file_name ( @fnames_by_timestamp ) {
      print( STDERR "Getting '$file_name'\n" );
      my $ftpResult = $ftp->get( $file_name, "$local_dir/.$file_name" );
      if ( $ftpResult eq "$local_dir/.$file_name") {
	  print STDERR " ftp fetch succeeded with message".$ftp->message."\n";### troubleshooting
	  my $timestamp = $file_names_hr->{$file_name};
	  $max_timestamp = max( $max_timestamp, $timestamp );
	  (-e "$local_dir/.$file_name") ||
	      print STDERR "Just ftped $local_dir/.$file_name and now it is gone!\n";
	  my_rename( "$local_dir/.$file_name", "$local_dir/$file_name" );
	  my_system( "chmod 0666 $local_dir/$file_name" );

	  print WRITERETRIEVED "$file_name\t".SeqDBUtils2::timeDayDate("yyyy-mm-dd-time")."\t$timestamp\n";

	  print( STDERR "Got it, timestamp = ". localtime( $timestamp ) ."\n" );
	  write_last_loaded( $config, $timestamp );
	  
      } else {
	  print STDERR "ERROR: When fetching '$file_name' I had status $ftpResult\n";
	  print STDERR " ftp fetch failed with message".$ftp->message."\n";### troubleshooting
	  # die ?
      }
  }

  close(WRITERETRIEVED);

  return $max_timestamp;
}


sub max {
  my ( $a, $b ) = @_;

  return $a > $b ? $a : $b;
}


sub get_args {

  my ( $dbconn, $collaborator, $type, $verbose ) = @ARGV;
  my $USAGE = "$0 <user/passw\@instance> <collaborator> <entry type> <verbose>\n".
              "\n".
              "  Downloads by ftp all new files for the entry type specified.\n".
              "\n".
              "  <collaborator> is one of: '". NCBI ."', '". DDBJ ."'\n".
              "  <entry type> is one of: '-normal', '-tpa', '-con', '-wgs', '-bqv', '-ann'\n".
              "\n";

  unless( defined( $verbose ) ) {
    disable diagnostics;
    print $USAGE;
    exit($exit_status);
  }

  unless ( $collaborator eq NCBI ||
           $collaborator eq DDBJ and
           defined( $type )           ) {

      print $USAGE;
      exit($exit_status);
  }

#  my $type_code =  {-normal => TYPE_NORMAL,
#                    -tpa    => TYPE_TPA,
#                    -con    => TYPE_CON,
#                    -wgs    => TYPE_WGS,
#                    -bqv    => TYPE_BQV,
#                    -mga    => TYPE_MGA    }->{$type};

  my $type_code;
  if ( $type =~ /-normal/i ) {
      $type_code = 'TYPE_NORMAL';
  }
  elsif ( $type =~ /-tpa/i ) {
      $type_code = 'TYPE_TPA';
  }
  elsif ( $type =~ /-con/i ) {
      $type_code = 'TYPE_CON';
  }
  elsif ( $type =~ /-wgs/i ) {
      $type_code = 'TYPE_WGS';
  }
  elsif ( $type =~ /-bqv/i ) {
      $type_code = 'TYPE_BQV';
  }
  elsif (( $type =~ /-mga/i ) && ( $collaborator =~ /DDBJ/i )) {
      $type_code = 'TYPE_MGA';
  }

  return ( $dbconn, $collaborator, $type, $type_code, $verbose );
}

sub write_last_loaded {

  my ( $config, $new_last_loaded ) = @_;

  printfile( $config->{last_loaded_fname}, $new_last_loaded );
}

exit($exit_status);
