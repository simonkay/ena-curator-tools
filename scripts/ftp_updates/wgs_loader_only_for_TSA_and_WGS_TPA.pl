#!/ebi/production/seqdb/embl/tools/bin/perl
#
# wgs_loader.pl <user/passw@instance> <collaborator> <set prefix> [<verbose>]
#
# Load a WGS set from a collaborator after it has been ftped.
# It is part of the collab update pipeline a.k.a. anti-load
#
# ?  ?   2004 F. Nardone    Created
# 11 Apr 2005 F. Nardone    Added Vincent's mail to the 'added prefix' notification
# 14 Oct 2005 F. Nardone    Removed Vincent's mail
# 25 Feb 2006    --"--      Quote quotes for prefix description.
# 15 Feb 2007    --"--      Use statusid.
#                           Renamed kill_previous set to suppress_previous_set
# 

use warnings;
use strict;
use diagnostics;

use FtpUpdates::Config_only_for_TSA_and_WGS_TPA;
use FtpUpdates::Loader;
use Utils qw(my_opendir my_open my_system my_rename my_unlink);
use Lsf;
use Mailer;
use Putff;

use File::Basename;
use DBI;
use Data::Dumper;

#my $DESCRIPTION_LIMIT = 256 - length('WGS - ');
#"$config->{WGS_LOADER} $dblogin $config->{collaborator} $type_code $set $verb $test 
main();

sub main {

  my ( $dblogin, $collaborator, $type_code, $key, $set_prefix, $verbose, $test) = get_args();

  my $DESCRIPTION_LIMIT = 256 - length($type_code) - 3;

  my FtpUpdates::Config_only_for_TSA_and_WGS_TPA $config = FtpUpdates::Config_only_for_TSA_and_WGS_TPA->get_config( $collaborator,
                                                                  $type_code,
								  $key,
                                                                  $verbose,
								  $test);

  $config->dump_all();

  my $fnames_ar = get_file_names( $config, $set_prefix );

  if ( $fnames_ar ) {

    my $type_reform = $config->{entry_type_name};
    my $full_set_id = get_set_id_version( $config, $fnames_ar,$type_reform );
    my ($description, $error) = get_description( $config, $fnames_ar,$DESCRIPTION_LIMIT );
    my $added = add_new_prefix( $config, $dblogin, $set_prefix, $description );
    my $body = scalar( localtime( time() ) ) ."\n\n" .
	$config->{entry_type_name}." prefix $set_prefix, ". $config->{entry_type_name}." - $description' ($config->{collaborator}) added to the database.\n";
    if (defined($error)) {
	$body .= $error;
    }
    if ( $added ) {
	my $subject;
	if($key eq 'TPA_WGS'){
	  $subject = $config->{entry_type_name}."($key) prefix '$set_prefix' ($config->{collaborator}) added to the database.";
	}
	else{
	  $subject = $config->{entry_type_name}." prefix '$set_prefix' ($config->{collaborator}) added to the database.";
	}
	send_mail( { to      => $config->{notification_addresses},
		     subject => $subject,
		     body    => $body
		 } );
    }

    eval {
      # we don't care whether this fails or not.
      add_new_prefix( $config, '/@DEVT', $set_prefix, $description );
    };
    
    my $load_jobs  = load_files( $config, $dblogin, $fnames_ar );

    my $failed_jobs_id = bwait_ids( keys( %$load_jobs ) );
    my @failed_files = move_failed_files( $config, $failed_jobs_id, $load_jobs );
    my $loading_status = get_wgs_loading_numbers( $config, $fnames_ar );

    unless( @$failed_jobs_id || $loading_status->{failed} > 0 ) {
      # If no failures, flag the set for distribution
     $dblogin =~ s/^\/?\@?//;
      my $dbh = DBI->connect("dbi:Oracle:$dblogin",'', '',
                             { AutoCommit => 0,
                               PrintError => 1,
                               RaiseError => 1 } );

      add_prefix_to_distribution_table( $dbh, $full_set_id, $type_reform );
      suppress_previous_set( $dbh, $full_set_id );

      $dbh->commit();
      $dbh->disconnect();
    }

    notify_wgs_loading( $config, $full_set_id, $loading_status, \@failed_files, $description );

    cleanup_loaded_files( $config, $fnames_ar );

  } else {

    print( "No files to load.\n" );
  }
}

sub get_description {
  # Returns the organism name for a wgs set

  my $config = shift( @_ );
  my ( $fnames_ar, $DESCRIPTION_LIMIT) = @_;

  my @org_names = ();
  foreach my $fname ( @{$fnames_ar} ) {
    push(@org_names,get_organism_names( "$config->{fixed_dir}/$fname" ));
  }

  # uniquify list of organisms (eg if WGS is chunked into >1 file
  {
      my %seen =() ;
      @org_names =  grep { ! $seen{$_}++ } @org_names ;
  }

  my $description = 'desc to add';
  my $error;

  if ( scalar(@org_names) > 1 ) {
      $error = sprintf ("%s file(s) contain %d organism names:\n%s\n",
			join(", ",@{$fnames_ar}),
			scalar(@org_names),
			join("\n", @org_names));
  } elsif ($DESCRIPTION_LIMIT < length($org_names[0])) {
      $error = sprintf ("%s file(s) contain a %d length organism name (limit is %d):\n",
			join(", ",@{$fnames_ar}),
			length($org_names[0]),
			$DESCRIPTION_LIMIT);
      $error .= "$org_names[0]\n"
	      . ' ' x $DESCRIPTION_LIMIT . "|-> excess\n";
  } else {
    $description = $org_names[0];
  }
  return $description, $error;
}

sub get_organism_names {
  # Return all organism names to which the entries in $fname refer.

  my $fname = shift;

  my %names;
  my $in_fh = my_open( $fname );
  my $lastLineIsSource = 0;
  my $osObtained = 0; # 0 = not yet, 1 = got start but need more, 2 = done
  my $os = "";

  while ( my $line = <$in_fh> ) {
      if (substr($line,0,2) eq "//") {
	  $os =~ s/  +/ /g; # multiple spaces possibliity arising from concatenation
	  $names{$os} = 1;
	  $osObtained = 0;
      } elsif ( $osObtained == 0) {
	  if ($line =~ /^ {21}\/organism=\"(.+)\"$/) {
	      $os = $1;
	      $osObtained = 2;
	  } elsif ( $line =~ /^ {21}\/organism=\"(.+)/) {
	      $os = $1;
	      $osObtained = 1;
	  }
      } elsif ( $osObtained == 1) {
	  if ($line =~ /^ {21}(.+)\"$/) {
 # NB There is no constraint stopping double quotes within organism names, but they should not be present
	      $os .= " " . $1;
	      $osObtained = 2;
	  } elsif ($line =~ /^ {21}(.+)/) {
	      $os .= " " . $1;
	  }
      }
  }
  close( $in_fh );
  return (keys( %names ));
}

sub get_file_names {
  # Return all data file names waiting to be loaded fro this set

  my $config = shift( @_ );
  my ( $set_prefix ) = @_;

  my $all_fnames  = get_all_files( $config->{fixed_dir} );

  my $match_regexp;
  if($config->{entry_type_name} eq 'TSA'){
    $match_regexp=$config->{tsa_fname_begin}.$set_prefix;
  }
  elsif($config->{entry_type_name} eq 'WGS'){
    $match_regexp=$config->{wgs_fname_begin}.$set_prefix;
  }
  else {
    print "WARNING: ".$config->{entry_type_name}." is not a type for WGS loading.";
  }
  print "match_regexp=$match_regexp\n";
  my $fnames  = [grep( m/$match_regexp/, @$all_fnames )];

  return $fnames->[0] ? $fnames : undef;
}

sub move_failed_files {
  # Moves aside all files related to jobs which did not exit nicely
  # Return an array containing the names of all files moved

  my $config = shift( @_ );
  my ( $failed_jobs_id, $load_jobs ) = @_;

  my @failed_files;
  foreach my $job_id ( @$failed_jobs_id ) {

    if ( defined ( my $fname = $load_jobs->{$job_id} ) ) {

      my_rename( "$config->{fixed_dir}/$fname", "$config->{fatal_error_dir}/$fname" );
      delete( $load_jobs->{$job_id} );
      push( @failed_files, $fname );
    }
  }

  return @failed_files;
}

sub notify_wgs_loading {

  my $config = shift( @_ );
  my ($full_set_id, $status, $failed_files, $description) = @_;

  my $address;
  if ( ! ($address = $config->{notification_addresses}) ) {
    # Do nothing if there is nobody to notify
    return;
  }

  my $msg = $config->{entry_type_name}." $full_set_id, description $description:\n".
            "\n".
   sprintf( "stored    = %8d\n", $status->{stored} ).
   sprintf( "failed    = %8d\n", $status->{failed} ).
   sprintf( "unchanged = %8d\n", $status->{unchanged} ).
            "--------------------\n".
   sprintf( "parsed    = %8d\n", $status->{stored} + $status->{failed} + $status->{unchanged} ).
            "\n".
            "======================\n".
            "\n";

  if ( scalar( @$failed_files ) > 0 ) {

    print STDERR scalar( @$failed_files ) ."#\n";
    print STDERR "+". join( '-', @$failed_files) ."+\n";
    $msg .= "These files generated a fatal error while loading:\n".
            join( ', ', @$failed_files ) ."\n";
  }

  # we load wgs with -no_error_files
  #if ( $status->{failed} > 0 ) {

  #  $msg .= "$status->{failed} error files are in $config->{load_error_dir}.\n";
  #}

  my $subject;

  if ( (scalar( @$failed_files ) > 0) || 
       ($status->{failed} > 0)            ) {

    $msg .= "The set will not be distributed because it was not lodaed completely.\n";
    $subject = "ERROR loading: ";

  } else {

    $msg .= "The set will be distributed.\n";
    $subject = "Loaded: ";
  }

  if($config->{entry_key_name} eq 'TPA_WGS'){
    $subject .= $config->{entry_type_name}." ($config->{entry_key_name}) $full_set_id, $description";
  }
  else{
    $subject .= $config->{entry_type_name}." $full_set_id, $description";
  }
  send_mail( { to      => $address,
               subject => $subject,
               body    => $msg   } );
}

sub get_set_id_version {

  my $config = shift( @_ );
  my ($fnames_ar, $type_reform) = @_;

  my $fh_in = my_open( "$config->{fixed_dir}/$fnames_ar->[0]" );

  my $full_id;
  while ( <$fh_in> ) {

    if ( m/^ACCESSION   ([A-Z]{4}\d{2})/ ) {
      $full_id = $1;
      last;
    }
  }

  close( $fh_in );

  if ( !defined($full_id) ) {
    die( "Can't find a valid $type_reform accession number in '$config->{fixed_dir}/$fnames_ar->[0]'\n" );
  }

  return $full_id;
}

sub get_wgs_loading_numbers {
  # Return a hash with the number of stored, failed and unchanged entries.

  my $config = shift( @_ );
  my ($fnames_ar) = @_;

  my ($loaded, $failed, $unchanged) = get_entry_numbers( $config, $fnames_ar );
  print STDERR ("Loaded: $loaded, Failed: $failed, Unchanged: $unchanged\n");
  return { stored    => $loaded,
           failed    => $failed,
           unchanged => $unchanged };
}

sub add_new_prefix {
  # Add to 'cv_Database_prefix' the WGS prefix $set_files_hr
  # if it is not not already in the database.
  #

  my $config = shift( @_ );
  my ($dblogin, $prefix, $description) = @_;
 $dblogin =~ s/^\/?\@?//;
  my $dbh = DBI->connect("dbi:Oracle:$dblogin",'', '',
                         {AutoCommit  => 0,
                           PrintError => 1,
                           RaiseError => 1} );

  my $is_there_sql = "SELECT *
                        FROM cv_database_prefix
                       WHERE prefix = '$prefix'";

  my $res = $dbh->selectall_arrayref( $is_there_sql );

  my $added;
  
  if ( !defined( $res->[0] ) ) {# the prefix is not already in the cv_table

    $description =~ s/'/''/g; # to avoid SQL errors
    my $add_sql = "INSERT INTO cv_database_prefix
                          (dbcode,               prefix,    entry_type)
                   VALUES ('$config->{db_code}', '$prefix', '$config->{entry_type_name} - $description')";

    $dbh->do( $add_sql );
    $dbh->commit();

    $added = 1;
    
  } else {

    $added = 0;
  }

  $dbh->disconnect();

  return $added;
}

sub add_prefix_to_distribution_table {

  my ($dbh, $set_prefix,$type_reform) = @_;

  my $table_name = "";

  if($type_reform eq 'TSA'){
    $table_name = "distribution_tsa";
  }
  else{
    $table_name = "distribution_wgs";
  }

  my $sql = "INSERT INTO $table_name
                    (wgs_set,       distributed)
             VALUES ('$set_prefix', 'N')";

  $dbh->do( $sql );

}

sub suppress_previous_set {

   my ($dbh, $current_prefix) = @_;

   my ($letters, $numbers);

   if ($current_prefix =~ m/^([A-Z]{4})(\d\d)$/) {

      ($letters, $numbers) = ($1, $2);

      if ($numbers <= 1) {
         # this is the first set, there is nothing to suppress
         return;
      }

      --$numbers;

      my $old_prefix = sprintf("%s%02d", $letters, $numbers);

      my $set_remark = "begin auditpackage.remark := 'no distribution - WGS set suppressed'; end;";

      $dbh->do($set_remark);

      my $sql = "UPDATE dbentry
                    SET statusid = 5
                  WHERE primaryacc# like '$old_prefix%'";

      my $rownum = $dbh->do($sql);
   }
}

sub get_args {#"$config->{WGS_LOADER} $dblogin $config->{collaborator} $type_code $set > $config->{logs_dir}/$set.loader.log 2>&1";

  my ( $dblogin, $collaborator, $type_code, $key, $set_prefix, $verbose, $test ) = @ARGV;
  print "here2 key=$key\n";
  unless( defined( $set_prefix ) ) {
    print( STDERR "Usage:\n$0 <user/passw\@instance> <collaborator> <set prefix> [<verbose>]\n" );
    exit;
  }

  $verbose = $verbose ? 1 : 0;

  return( $dblogin, $collaborator, $type_code, $key, $set_prefix, $verbose,$test );
}
