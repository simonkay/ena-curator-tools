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
#
# 15-Mar-2012 Xin : add key: tpa_wgs

use diagnostics;
use warnings;
use strict;
use Net::FTP::AutoReconnect;
use SeqDBUtils2;
use FtpUpdates::Config_only_for_TSA_and_WGS_TPA;
#use lib "/net/nas17b/vol_homes/homes/xin/tmp/ftp/Config_xintest";
use Utils qw(my_open printfile my_rename my_system);
use Mailer;

my $exit_status = 0;

main();

sub main {
#/ebi/production/seqdb/embl/tools/bin/perl /nfs/production/seqdb/embl/tools/curators/scripts/ftp_updates/ftp_only_for_TSA_and_WGS_TPA.pl /@enadev ncbi -wgs TPA_WGS 1 1>&! ~/tmp/ncbi.wgs.log &
#/ebi/production/seqdb/embl/tools/bin/perl /nfs/production/seqdb/embl/tools/curators/scripts/ftp_updates/ftp_only_for_TSA_and_WGS_TPA.pl /@enadev ncbi -tsa null 1 1>&! ~/tmp/ncbi.wgs.log &
#/ebi/production/seqdb/embl/tools/bin/perl /nfs/production/seqdb/embl/tools/curators/scripts/ftp_updates/ftp_only_for_TSA_and_WGS_TPA.pl /@enapro ncbi -tsa null 1 0

  my ( $dbconn, $collaborator,$type, $type_code, $key, $verbose, $test ) = get_args();
  print STDERR `date`;
  print("dbconn=$dbconn\ncollaborator=$collaborator\ntype=$type\ntype_code=$type_code\nkey=$key\nverbose=$verbose\ntest=$test\n");

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = FtpUpdates::Config_only_for_TSA_and_WGS_TPA->get_config( $collaborator, $type_code,$key, $verbose,$test );

  $config->dump_all();

  eval {

    my $ftp = get_ftp( $config );

    my $last_loaded = get_last_loaded( $config );

    unload_new_files( $config, $ftp, $last_loaded );

    $ftp->quit();
    print STDERR "ftp finished\n";

    if ( $config->{entry_type} ne 'TYPE_BQV' ) {
     
      my $comm = "$config->{LOADER} $dbconn $collaborator $type $key $verbose $test";
      print STDERR "launching loader:\n'$comm'\n";
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

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = shift( @_ );

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

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = shift( @_ );

  my $fh = my_open( $config->{last_loaded_fname} );
  my $last_loaded = <$fh>;
  close( $fh );

  chomp( $last_loaded );
  $config->{VERBOSE} && print( STDERR "Last loaded: $last_loaded, '". localtime($last_loaded) ."'\n" );
  return $last_loaded;
}


sub unload_new_files {

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = shift( @_ );
  my ( $ftp, $last_loaded ) = @_;

  my $remote_dir = $config->{ftp_remote_dir};
  my $local_dir = $config->{ftp_local_dir};
  my $name_pattern = $config->{file_name_pattern};

  $config->{VERBOSE} && print( STDERR "getting file names\n" );

  my $file_names_hr = get_file_names( $config, $ftp, $last_loaded );

######  print "Looking inside $checkDir\n";

  exit(0);

  my $new_last_loaded = unload_files( $config, $ftp, $file_names_hr );

  return $new_last_loaded;
}


sub get_file_names {

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = shift( @_ );
  my ( $ftp, $last_loaded ) = @_;

  my $remote_dir = $config->{ftp_remote_dir};
  my $name_pattern = $config->{file_name_pattern};
  my $remote_ftp_sub_dirs = $config->{remote_ftp_sub_dirs};

  my $length = @$remote_ftp_sub_dirs;
  print "Length = $length\n";

  # if exists loop through the sub dirs
  my @dirlist; 

  $ftp->cwd( $remote_dir ) or
       die( "Cannot cwd to '$remote_dir'" );
  $config->{VERBOSE} && print "In remote directory: ", $remote_dir, "\n";

  if ($length > 0)  {

     foreach (@$remote_ftp_sub_dirs) {

        $ftp->cwd( $_ ) or
           die( "Cannot cwd to '$_'");
	
        push(@dirlist, $ftp->ls());

        $ftp->cwd( ".." ) or
           die( "Cannot cwd up again");
    }
  } else {
     @dirlist = $ftp->ls();
  }

  foreach (@dirlist) { 
       print "dirlist=".$_."\n";
  }

  $, = "\n";
  
  $config->{VERBOSE} && print 'Dir list:', @dirlist, "\n";
  
  print "name_pattern=$name_pattern\n";
  
  my @all_files = grep( m/$name_pattern/, @dirlist );
  
  print "\n\nMatching files:", @all_files, "\n";
  
  $config->{VERBOSE} && print "\n\nMatching files:", @all_files, "\n";

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
    print STDERR "filename = $file_name \n " ;
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
      $new_files{$file_name} = $timestamp; #!!!!!

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

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = shift( @_ );
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

  my ( $dbconn, $collaborator, $type, $key, $verbose, $test ) = @ARGV;
  print"$dbconn, $collaborator, $type, $verbose\n";
  my $USAGE = "$0 <user/passw\@instance> <collaborator> <entry type> <verbose>\n".
              "\n".
              "  Downloads by ftp all new files for the entry type specified.\n".
              "\n".
              "  <collaborator> is one of: '". NCBI ."', '". DDBJ ."'\n".
              "  <entry type> is one of: '-normal', '-tpa', '-con', '-wgs', '-bqv', '-ann', 'tsa'\n".
	      "  <entry key> is 'tsa_wgs'".
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
  elsif ( $type =~ /-con/i ) {
      $type_code = 'TYPE_CON';
  }
  elsif ( $type =~ /-wgs/i ) {
      $type_code = 'TYPE_WGS';
  }
  elsif ( $type =~ /-tsa/i ) {
    print "here\n";
      $type_code = 'TYPE_TSA';
  } 
  elsif ( $type =~ /-tpa/i ) {
      $type_code = 'TYPE_TPA';
  }
  elsif ( $type =~ /-bqv/i ) {
      $type_code = 'TYPE_BQV';
  }
  elsif (( $type =~ /-mga/i ) && ( $collaborator =~ /DDBJ/i )) {
      $type_code = 'TYPE_MGA';
  }

  return ( $dbconn, $collaborator, $type, $type_code, $key, $verbose,$test );
}

sub write_last_loaded {

  my ( $config, $new_last_loaded ) = @_;

  printfile( $config->{last_loaded_fname}, $new_last_loaded );
}

exit($exit_status);
