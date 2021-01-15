#!/ebi/production/seqdb/embl/tools/bin/perl
#
# ftp.pl <user/passw@instance> <collaborator> <entry type> <verbose>
#    Downloads by ftp all new files for the entry type specified.
#    <entry type> is one of: '-normal', '-con', '-bqv', '-wgs', '-tpa'
#
# After downloading it call the loader utils (release_loader.pl or 
# bqv/release_load_bqv.pl) which loads entries in the database.
#
# 07-DEC-2009 G. Hoad   Created

use diagnostics;
use warnings;
use strict;
use Net::FTP::AutoReconnect;
use SeqDBUtils2;
use FtpRelease::ReleaseConfig;
use Utils qw(my_open printfile my_rename);
use Mailer;
use LWP::UserAgent;
use Data::Dumper;

# constants and paths
my $exit_status = 0;
my @data_types = qw{normal con bqv wgs tpa};
my $NCBI_RELEASE_FTP = 'ftp://ftp.ncbi.nih.gov/genbank/GB_Release_Number';
my $RELEASE_DIR = '/ebi/production/seqdb/embl/data/collab_exchange/ncbi.release.test';
my $LAST_RELEASE_FNAME = "$RELEASE_DIR/last_release_number";
my $TEMP_LAST_RELEASE_FNAME = "$RELEASE_DIR/.last_release_number";
my $COMPLETED_FLAG_FILE = "$RELEASE_DIR/.complete";

main();

sub main {

    my ( $dbconn, $type, $verbose, $test ) = get_args();
    print STDERR `date`;

    eval {
	
	my $latest_release_num = get_latest_release_number();

	if (! $latest_release_num) {
	    print STDERR "ERROR: Latest genbank release number could not be found from $NCBI_RELEASE_FTP\n";
	    return(0);
	}
	
	my $last_release_num = get_last_release_loaded();

	my $brand_new_release_run = 0;
	if ($latest_release_num > $last_release_num) {
	    $brand_new_release_run = 1;
	}

	# if there is a new release, download it and put in prdb1
	if ($brand_new_release_run || (
				        ($latest_release_num == $last_release_num) && 
				        (! -e($COMPLETED_FLAG_FILE))
				      )
           ) {

            # create .last_release file containing new release number
	    create_temp_release_number_file( $latest_release_num );

	    # remove flag which marks the run as having finished
	    remove_completed_run_flag();


	    if ($type eq "") {
            # process every type

		foreach my $data_type (@data_types) {
		    get_files_and_run_loader($brand_new_release_run, $data_type, $dbconn, $verbose, $test);
		}
	    }
	    else {
		# process the type specified in the script arguments
		get_files_and_run_loader($brand_new_release_run, $type, $dbconn, $verbose, $test);
	    }

	    # now release loading has complete, replace old release number with the new one
	    my_rename($TEMP_LAST_RELEASE_FNAME, $LAST_RELEASE_FNAME);

	    # create a .complete file to show the run has finished
	    create_completed_run_flag($latest_release_num);
	}
    };
    
    if ( $@ ) {
	# don't die if lock found.
	print STDERR $@;
    }
}

sub get_files_and_run_loader {

    my ( $brand_new_release_run, $type, $dbconn, $verbose, $test ) = @_;

    my $config = FtpRelease::ReleaseConfig->get_config( $type, $verbose, $test );
    $config->dump_all();
    my $ftp = get_ftp( $config );

    if (($brand_new_release_run) && (-e $config->{retrieved_files_fname})) {
	print STDERR "Brand new release run\n";
	unlink($config->{retrieved_files_fname});
    }
    
    $config->{VERBOSE} && print( STDERR "getting file names\n" );
    my $file_names_hr = get_file_names( $config, $ftp );

    unload_files( $config, $ftp, $file_names_hr );


    if ( $type eq 'bqv' ) {

	my $local_dir = $config->{ftp_local_dir};
	my @downloaded_bqv_files = glob("$local_dir/gb*.qscore.gz");

	foreach my $bqv_file (@downloaded_bqv_files) {
	    my $comm = "$config->{BQV_LOADER} $dbconn $bqv_file $test";
	    print STDERR "launching BQV release loader on $bqv_file:\n'$comm'\n";
	    system( $comm );
        }
    }
    else {	
	my $comm = "$config->{LOADER} $dbconn $type $verbose $test";
	print STDERR "launching release loader:\n'$comm'\n";
	system( $comm );
    }
}

sub get_file_names {

    my FtpRelease::ReleaseConfig $config = shift( @_ );
    my ( $ftp ) = @_;
    
    my $remote_dir = $config->{ftp_remote_dir};
    my $name_pattern = $config->{file_name_pattern};
    
    $ftp->cwd( $remote_dir ) or
	die( "Cannot cwd to '$remote_dir'" );
    
    my @dirlist = $ftp->ls();
    
    $, = "\n"; # set a separator to the output field separator
    # $config->{VERBOSE} && print 'Dir list:', @dirlist, "\n";
    
    my @all_files = grep( m/$name_pattern/, @dirlist );
    
    my %new_files;
    
    foreach my $file_name ( @all_files ) {

	$new_files{$file_name} = 1;
	$config->{VERBOSE} && print( STDERR "Marking $file_name as a file to retrieve\n" );
    }
    
    return \%new_files;
}

sub unload_files {

    my FtpRelease::ReleaseConfig $config = shift( @_ );
    my ( $ftp, $file_names_hr ) = @_;

    my $local_dir = $config->{ftp_local_dir};
    my $remote_dir = $config->{ftp_remote_dir};

    open(WRITERETRIEVED, ">>".$config->{retrieved_files_fname}) || print "WARNING: Could not append to ".$config->{retrieved_files_fname}." which lists all files retrieved\n\n";


    foreach my $file_name ( keys %$file_names_hr ) {

	if (! -e("$local_dir/$file_name")) {
	  
	    #print( STDERR "Downloading '$file_name'\n" );

	    my $ftpResult = $ftp->get( $file_name, "$local_dir/.$file_name" );

	    print STDERR "ftpResult = $ftpResult\n";
	    print STDERR "local_dir/.file_name = $local_dir/.$file_name\n";

	    if ( $ftpResult eq "$local_dir/.$file_name") {
		print STDERR " ftp fetch succeeded with message".$ftp->message."\n";### troubleshooting
	
		my_rename( "$local_dir/.$file_name", "$local_dir/$file_name" );

		my @files = glob("$local_dir/$file_name");
		chmod(0666, @files);
		
		print WRITERETRIEVED "$file_name\n";
	    } 
	    else {
		print STDERR "ERROR: When fetching '$file_name' I had status \"$ftpResult\"\n";
		print STDERR " ftp fetch failed with message".$ftp->message."\n";### troubleshooting
		# die ?
	    }
	}
	else {
	    print STDERR "$file_name has already been downloaded\n";
	}
    }
	
    close(WRITERETRIEVED);
}

sub get_args {

    my $dbconn;
    my $type = "";
    my $verbose = 0;
    my $test = 0;

    foreach my $arg (@ARGV) {

	if ($arg =~ /(prdb1|devt)/i) {
	    $dbconn = $arg;
	}
	elsif ($arg =~ /\-(normal|con|bqv|wgs|tpa)/) {
	    $type = $1;
	}
	elsif ($arg =~ /-v(erbose)?/) {
	    $verbose = 1;
	}
	elsif ($arg =~ /-t(est)?/) {
	    $test = 1;
	}
    }

    my $USAGE = "$0 <user/passw\@instance> <entry type> <verbose> <-t(est)?>\n".
	"\n".
	"  Downloads by ftp all new files for the entry type specified.\n".
	"\n".
	"  <entry type> is one of: '-normal', '-con', '-bqv', '-wgs', '-tpa'\n".
	"  If entry type is left blank, all types will be picked up and loaded in series.\n".
	"  <-t(est)> is optional.  It makes sure the database being used is devt.";

    unless( defined( $dbconn ) ) {
	disable diagnostics;
	print $USAGE;
	exit($exit_status);
    }
    
    if (defined $test) {
	$dbconn = '/@devt';
    }
     
    return ( $dbconn, $type, $verbose, $test );
}

sub get_ftp {

    my FtpRelease::ReleaseConfig $config = shift( @_ );

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

sub create_temp_release_number_file {
    
    my $latest_release_num = shift;

    printfile( $TEMP_LAST_RELEASE_FNAME, $latest_release_num );
}

sub get_last_release_loaded {

  my ($fh, $last_release);

  if (open($fh, "<$LAST_RELEASE_FNAME")) {
      $last_release = <$fh>;
      close( $fh );
      chomp( $last_release );
  }
  else {
      $last_release = 0;
  }

  print( STDERR "Last release: $last_release\n" );
  return $last_release;
}

sub get_latest_release_number {

    my $ua = new LWP::UserAgent;
    $ua->timeout(1000);

    my $req = new HTTP::Request GET => $NCBI_RELEASE_FTP;
    my $result = $ua->request($req);
    if (!( $result->is_success )) {
        return("");
    }
    
    my $rescontent = $result->content;            

    if ( $rescontent =~ /(\d+)/ ) {
	return($1);
    }
    else {
	return(0);
    }
}

sub remove_completed_run_flag {

    if (-e $COMPLETED_FLAG_FILE) {
	print STDERR "Removing $COMPLETED_FLAG_FILE\n";
	unlink($COMPLETED_FLAG_FILE);
    }
}

sub create_completed_run_flag {

    my $latest_release_num = @_;

    printfile( $COMPLETED_FLAG_FILE, $latest_release_num );
}

exit($exit_status);
