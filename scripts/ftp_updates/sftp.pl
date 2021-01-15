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

use diagnostics;
use warnings;
use strict;
use Net::SFTP::Foreign;
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

    my $sftp = get_sftp( $config );

    my $last_loaded = get_last_loaded( $config );

    unload_new_files( $config, $sftp, $last_loaded );

    $sftp->autodisconnect() or die "can not disconnect sftp\n";
    print STDERR "sftp finished\n";

    if ( $config->{entry_type} ne 'TYPE_BQV' ) {
     
      my $comm = "$config->{LOADER} $dbconn $collaborator $type $verbose";
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


sub get_sftp {

  my FtpUpdates::Config $config = shift( @_ );
  my $sftp_addr = $config->{sftp_addr};
  my $sftp_user = $config->{sftp_uname};
  my $sftp_password = $config->{sftp_passw};

  $config->{VERBOSE} && print( STDERR "Connecting to: $sftp_addr\n" );

  my $sftp;
  
  # try 7 times before giving up
  my $i;
  for ( $i = 1; $i <= 7; ++$i ) {
  
    $sftp = Net::SFTP::Foreign->new($sftp_addr, user => $sftp_user, password => $sftp_password, timeout => 3000);  
  
    if ( defined ( $sftp ) ) {
      last;
    } else {
      sleep( 1 );
      next;
    }
  }

  if ( !defined ( $sftp ) ) {    
    print( "Cannot connect or login to '$sftp_addr' after $i attempts.\n$@" );
    exit($exit_status);
  } 
 

  $config->{VERBOSE} && print( STDERR "Connected and logged in $i attempts.\n" );

  return $sftp;
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
  my ( $sftp, $last_loaded ) = @_;

  my $remote_dir = $config->{sftp_remote_dir};
  my $local_dir = $config->{sftp_local_dir};
  my $name_pattern = $config->{file_name_pattern};

  $config->{VERBOSE} && print( STDERR "getting file names\n" );
  my $file_names_hr = get_file_names( $config, $sftp, $last_loaded );
	    #print "Looking inside $checkDir\n";
  my $new_last_loaded = unload_files( $config, $sftp, $file_names_hr );

  return $new_last_loaded;
}


sub get_file_names {

  my FtpUpdates::Config $config = shift( @_ );
  my ( $sftp, $last_loaded ) = @_;

  my $remote_dir = $config->{sftp_remote_dir};

  my $name_pattern = $config->{file_name_pattern};

  $sftp->setcwd( $remote_dir ) or  die( "Cannot cwd to $remote_dir" );

  my $dirlist = $sftp->ls() or die "unable to retrive directory: ".$sftp->error;
  my @filenames = map { $_ ->{"filename"}} @$dirlist;

  $, = "\n";
  # $config->{VERBOSE} && print 'Dir list:', @dirlist, "\n";

  my @all_files = grep( m/$name_pattern/, @filenames );

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
	my $attr = $sftp->stat($file_name) or die "unable to stat remote file to get the file timestamp\n";
	$timestamp = $attr->mtime;
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
  my ( $sftp, $file_names_hr ) = @_;

  my $local_dir = $config->{sftp_local_dir};

  my $max_timestamp = 0;

  open(WRITERETRIEVED, ">>".$config->{retrieved_files_fname}) || print "WARNING: Could not append to ".$config->{retrieved_files_fname}." which lists all files retrieved\n\n";

  my @fnames_by_timestamp = sort {
                              $file_names_hr->{$a} cmp $file_names_hr->{$b}
                            } keys %$file_names_hr;

  foreach my $file_name ( @fnames_by_timestamp ) {
      print( STDERR "Getting '$file_name'\n" );
      my $sftpResult = $sftp->get( $file_name, "$local_dir/.$file_name" ) or die "can not get $file_name\n";

      if ( -f "$local_dir/.$file_name") {
	  print STDERR " sftp fetch succeeded with $file_name\n";### troubleshooting
	  my $timestamp = $file_names_hr->{$file_name};
	  $max_timestamp = max( $max_timestamp, $timestamp );
	  (-e "$local_dir/.$file_name") || print STDERR "Just sftped $local_dir/.$file_name and now it is gone!\n";
	  my_rename( "$local_dir/.$file_name", "$local_dir/$file_name" );
	  my_system( "chmod 0666 $local_dir/$file_name" );

	  print WRITERETRIEVED "$file_name\t".SeqDBUtils2::timeDayDate("yyyy-mm-dd-time")."\t$timestamp\n";

	  print( STDERR "Got it, timestamp = ". localtime( $timestamp ) ."\n" );
	  write_last_loaded( $config, $timestamp );
	  
      } else {
	  print STDERR "ERROR: When fetching '$file_name' I had status $sftpResult\n";
	  print STDERR "sftp fetch failed with message".$sftp->error."\n";### troubleshooting
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

=head1
use Net::SFTP::Foreign; # add to congfig
use strict;
use warnings;
use Cwd qw(abs_path);
#/ebi/production/seqdb/embl/tools/bin/perl /nfs/gns/homes/xin/tmp/test.pl

my $sftp_addr = "colb-ftp.ddbj.nig.ac.jp"; #add to config 115-117
my $uname = 'emblftp'; #add to config 115-117
my $passw = 'Hte1eJ^g6'; #add to config 115-117

my $sftp = Net::SFTP::Foreign->new($sftp_addr, 
user => 'emblftp', 
password => 'Hte1eJ^g6', 
timeout => 3000);

$sftp->error and die "Something bad happened: " . $sftp->error;


my $attr = $sftp->stat("./daily-nc/DDBJr92u0041.dat.Z") or die "unable to stat remote file";
printf "modification time: %d\n", $attr->mtime; #ftp.pl L180
#$sftp->binary();
#my $remote_dir    = $sftp_addr .'/daily-nc';
my $remote_dir    = '/daily-nc';
$sftp->setcwd( $remote_dir ) or die( "Cannot cwd to '$remote_dir'" );
my $dirlist = $sftp->ls($remote_dir) or die "unable to retrive directory: ".$sftp->error;
foreach my $dir_ele (@$dirlist){ 
      my $fileName = $dir_ele->{"filename"};
      print "$fileName\n";   
}
$sftp->autodisconnect() or die "can not quit sftp\n";
=cut