#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/set_wgs_set_status.pl,v 1.0 2016/05/03 10:34:07 xin 
#
#  MODULE DESCRIPTION:
#
#  Updates wgs et status. Audit remark is mandatory.
#
#  MODIFICATION HISTORY:
#
#  03-MAY-2016 Xin LIU    Created based on set_entry_status
#======================================================================================================

use strict;
use DBI;
use dbi_utils;
use seqdb_utils;
use SeqDBUtils;

my $REMARKLIMIT = 50;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Modify wgs set status. Current available status:\n".
            "          draft, private, cancelled, public, suppressed, killed.\n".
	    	"          A reason of less than $REMARKLIMIT characters must be\n".
	    	"          given for the modification.\n\n".
            " USAGE:   $0\n".
	    	"          <user/password\@instance> [set] [-test] [-remark]\n\n".
	    	"          set(required)              wgs prefix with build number (i.e. LLLLVV).\n".
	    	"          -test(optional)            checks for test vs. production settings. This is required while using enadev.\n".
	    	"          -remark=\"XXX\"(optional)    reason for modification.\n\n".
            "    When prompted for the entry status enter the statusid.\n".
            "    For example 1-draft, enter 1 and press <RETURN>.\n".
            "    Some status have hold date, when prompted, enter the date.\n".
            "    For no change to either entry status or hold date press <RETURN>.\n".
            "    If you want to cancel the change when asked for reasons, enter Q and press <RETURN>\n";


( @ARGV >= 2 && @ARGV <= 4 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide ( 1 );

my %embl_status = (1 => 'draft',2 => 'private', 3 => 'cancelled', 4 => 'public', 5 => 'suppressed', 6 => 'killed');

main ();

sub main{

    my ($login, $set, $remark, $test) = handle_command_line ();
   
    #connect to database

    my $dbh = dbi_ora_connect ( $login );
    dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

    my @accnos = get_acc($dbh, $set);
    if (!(@accnos) || (@accnos == 0)) {
		die("No entries found\n");
    }

    my ($cur_status, $cur_hdate, $ext_ver) = check_acc (\@accnos, $set, $dbh); 
    display_cur_status ($set, \@accnos, $cur_status, $cur_hdate,  $ext_ver);

    my ($new_status, $new_hdate) = get_new_status($accnos[$#accnos], $cur_status, $cur_hdate, $ext_ver, $dbh);

    if ($new_status eq $cur_status || $new_status eq ''){
		$new_status = "-";
    }

    if ($new_hdate eq '-' || $new_hdate eq $cur_hdate){	    	   
		print "\nhold date has not been changed\n";   
		$new_hdate = "-";
    }
  
    if ($cur_hdate eq '-' && $new_hdate eq 'N'){
		print "\nno hold date \n";
		$new_hdate = "-";
    }
	
    if ($new_status ne "-" || $new_hdate ne "-"){
		while ($remark eq ''){
	    	$remark = get_remark();
		}
		if (uc($remark) eq 'Q') {
	    	print "Changes abandoned\n";
	    	dbi_logoff ( $dbh );
	    	exit;
		}	
    }
	
    set_audit ($remark, $dbh);
    
    update_entry ($set, $new_status, $new_hdate, $dbh);   
    
    # handle temporary suppression and kill - make sure there is a signal to redistribute when set is released
    if($cur_status==4 && ($new_status == 5 ||$new_status == 6) && $new_hdate =~ /\d+/){ # if old status is 4 and the new status in (5,6)
    	insert_distribution_wgs (\@accnos,$dbh);
    }
    
    dbi_commit ( $dbh );
    dbi_logoff ( $dbh );
}

sub insert_distribution_wgs{
	my ($acc_array,$dbh ) = @_;
	my $first_entry = $acc_array->[0];
	my $set_prefix = substr($first_entry,0,6);	
	my $sql = "INSERT INTO distribution_wgs (wgs_set, distributed) VALUES ('$set_prefix', 'N')";

 	$dbh->do( $sql );
 	return;
}

sub handle_command_line {
    my $login = $ARGV[0];
    my $set = "";
    my $test  = 0;
    my $remark = "";
    for ( my $i = 1; $i < @ARGV; ++$i )
    {	
		if ( $ARGV[$i] =~ /^(\-set=?)?([A-Z]{1,4}\d{2})$/ )	{
	    	$set = uc ( $2 );
		} 
		elsif ( $ARGV[$i] =~ /^\-remark=[\"\']?([^\"\']+)[\"\']?$/ ) {
	    	$remark = $1;
	    	if ( length($remark) > $REMARKLIMIT ) {
				print STDERR "Remark should be $REMARKLIMIT characters or less\n"
		    	. "$remark is ".length($remark)." long\n"
		    	. ' ' x  $REMARKLIMIT . "|-> excess\n";
				$remark = "";
	    	}	
		}
		elsif ( $ARGV[$i] eq "-test" ) {   
	    	$test = 1;
		}
		else {
	    	die ( "I do not understand  $ARGV[$i]\n$usage" );
		}
    }
    if ($set eq "" ){
		die ($usage);
    }
    die if ( check_environment ( $test, $login ) == 0 );
    return ($login, $set, $remark, $test);
}

sub display_cur_status {

    my ($set, $accessions, $cur_status, $cur_hdate, $ext_version) = @_;
    my $message = ''; 
    if (scalar @$accessions != 0 ){
		$message = "$set: current status";
    }   
    if ($cur_status eq '4'){ #public
        print "$message: " . $ext_version . "\n";
    }
    elsif ($cur_status eq '3' || $cur_status eq '5' ){
		print "$message: $embl_status{$cur_status}\n";
    }
    else{
        my $hold_date = ($cur_hdate eq '-') ? "no hold date" : "current hold date: $cur_hdate";
        print "$message: $embl_status{$cur_status}, $hold_date\n";	
    }  
}

#-------------------------------------------------------------------------------
# query for input.
#-------------------------------------------------------------------------------
sub get_remark {

    my $remark = "--------10--------20--------30--------40--------50*";

    while ( length ( $remark ) > $REMARKLIMIT )
    {
		print "\nreason for modification (max. $REMARKLIMIT characters, Q to quit without changing status):\n";
		print "--------10--------20--------30--------40--------50\n";  
		chomp ( $remark = <STDIN> );
    }

    return $remark;
}

sub get_new_status {
    my ($acc, $cur_status, $cur_hdate,$ext_ver, $dbh) = @_;    
    my $new_status = '';
    my $new_hdate   = '';  
    while ($new_status eq '' && $new_hdate eq ''){
		$new_status = "-";
		$new_hdate = "-";

		if ($cur_status eq "1"){
	    	($new_status, $new_hdate) = process_draft($cur_status, $cur_hdate, $dbh);
		}
    	elsif ($cur_status eq "2"){
	    	($new_status, $new_hdate) = process_private($cur_status, $cur_hdate, $dbh);
		}
		elsif ($cur_status eq "3"){
	    	($new_status, $new_hdate) = process_cancelled($cur_status, $cur_hdate, $dbh);
		}
		elsif ($cur_status eq "4"){
	    	($new_status, $new_hdate) = process_public($cur_status, $cur_hdate, $ext_ver,$dbh);
		}
		elsif ($cur_status eq "5"){
	    	($new_status, $new_hdate) = process_suppressed($cur_status, $cur_hdate, $dbh);
		}
		elsif ($cur_status eq "6"){
	    	($new_status, $new_hdate) = process_killed($cur_status, $cur_hdate, $dbh);
		}
#	printf "%s->%s\n", $embl_status{$cur_status}, (($new_status ne"")?$embl_status{$new_status}:"no change"");
		if ($cur_status eq $new_status){
	    	$new_status = '';
		}

	# exit if user pressed return everywhere.
		if ( $new_status eq '' && $new_hdate eq '' ) {
	    	print "Nothing to change\n";
	    	dbi_logoff ( $dbh );
	    	exit;
		}	
    }

    return ($new_status, $new_hdate);
}

sub get_new_statusid {    
    my $statusid = '';
    chomp ( $statusid = <STDIN> ); 
    $statusid =~ s/\s//g;
    if ((defined($statusid)) && 
		($statusid ne '') && 
		($statusid !~ /^\d+$/)) {
		$statusid = statusWordToCode($statusid);
    }
    return $statusid;
}

sub get_new_hdate {
    my ($dbh, $new_status, $cur_hdate) = @_;
    my $new_hdate = "";

    if ($new_status eq '1' || $new_status eq '6'){
		print "Hold date (DD-MON-YYYY)(return for No change or 'n' for none):";
    }
    elsif ($new_status eq '2') {
		print "Hold date (DD-MON-YYYY):";
    }
    else {
		print "Hold date (DD-MON-YYYY)(return for No change):";
    }
	chomp ( $new_hdate = <STDIN> ); $new_hdate = uc ( $new_hdate );$new_hdate =~ s/\s//g;
    if ($new_status eq '2' and $cur_hdate eq '-'){
		while ( $new_hdate eq ''){
	    	print "A hold date must be provided to change the status to private:\n";
            print "Hold date (DD-MON-YYYY)(C to cancel):";
	    	chomp ( $new_hdate = <STDIN> ); $new_hdate = uc ( $new_hdate );$new_hdate =~ s/\s//g;
	    	if ($new_hdate eq 'C'){
                print "Nothing has changed\n";
				dbi_logoff($dbh);
                exit;
	    	}		
		}
		while ( $new_hdate !~ /^\d{2}-[A-Z]{3}-\d{4}$/ && $new_hdate ne 'XXX'){
	    	print "wrong format (DD-MON-YYYY): "; 	    
	    	chomp ( $new_hdate = <STDIN> ); $new_hdate = uc ( $new_hdate );$new_hdate =~ s/\s//g;
		}	
    }
    elsif ($new_status eq '1' || $new_status eq '6'){
		while ( $new_hdate !~ /^\d{2}-[A-Z]{3}-\d{4}$/ && $new_hdate ne '' && $new_hdate ne 'XXX' 
                      && $new_hdate ne 'N'){
	   		print "wrong format (DD-MON-YYYY): "; 	    
	   		chomp ( $new_hdate = <STDIN> ); $new_hdate = uc ( $new_hdate );$new_hdate =~ s/\s//g; 
		}
    }
    else {
		while ( $new_hdate !~ /^\d{2}-[A-Z]{3}-\d{4}$/ && $new_hdate ne '' && $new_hdate ne 'XXX') {
	    	print "wrong format (DD-MON-YYYY): "; 
	    	chomp ( $new_hdate = <STDIN> ); $new_hdate = uc ( $new_hdate );$new_hdate =~ s/\s//g;	     
		}
    }	    
    if ($new_hdate eq 'XXX'){
		$new_hdate = '31-DEC-9999';
    }
    elsif ($new_hdate eq ''){
		$new_hdate = '-';
    }
    if ($new_hdate ne 'N' && $new_hdate ne '-'){
		check_hdate($new_hdate, $dbh);
    }
    return $new_hdate;
}

sub process_draft {

    my ($cur_status, $cur_hdate, $dbh) = @_;
    my $new_status = '-';
    my $new_hdate = '';
    my $draft = "(1-draft [for hold date change], 2-private, 3-cancelled, 4-public):";
    
    print "Please enter statusid $draft";

    while ($new_status !~ /^[1-4]$/) {
		$new_status = get_new_statusid();
		if ($new_status !~ /^[1-4]$/) {
	    	print "Wrong set statusid entered, type a number or a status:";
		}
    }
    
    if ($new_status eq '4' and $cur_hdate eq '31-DEC-9999'){
		$new_status = confirm_xxx_removal($cur_status, $new_status);
    }    
    elsif ($new_status eq '4' and $cur_hdate ne '-'){
		print "\n***Are you sure you want to remove hold date by changing the status to public (Y/N)(default=N)?:";
		my $answer = '';
        chomp ( $answer = <STDIN> ); 
        if (uc ($answer) eq 'N' || $answer eq ''){
            $new_status = '';
	    	print "please enter statusid (1-draft [for hold date change], 2-private, 3-cancelled):";
	    	$new_status = get_new_statusid();

	    	while ($new_status ne '1' && $new_status ne '2' && $new_status ne '3' && $new_status ne ''){       
				print "Wrong wgs set status id entered:";
				$new_status = get_new_statusid();
	    	}
        }
    }
    
    if ($new_status eq '1' || $new_status eq "2"){	
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }	      
    return ($new_status, $new_hdate);
}

sub confirm_xxx_removal {
    my ($cur_status, $new_status) = @_;
    my $message;
    print "***Hold date 31-DEC-9999 is a special one used for indefinitely private entries (eg TPA).\n";
    print "***Please confirm that you wish to remove this hold date and make the wgs set public (y/N)?";

    my $answer = '';
  
    chomp ( $answer = <STDIN> ); 
    if (uc ($answer) eq 'N' || $answer eq ''){   
		if ($cur_status eq '1'){
	    	print "please enter statusid (1-draft [for hold date change], 2-private, 3-cancelled):";
	    	$new_status = get_new_statusid();
	    	while ($new_status ne '1' && $new_status ne '2' && $new_status ne '3' && $new_status ne ''){       
				print "Wrong wgs set status id entered:";
				$new_status = get_new_statusid();
	   	 	}
		}
		elsif ($cur_status eq '2'){
	    	print "please enter statusid (1-draft, 2-private [for hold date change], 3-cancelled):";
	    	$new_status = get_new_statusid();
	    	while ($new_status ne '1' && $new_status ne '2' && $new_status ne '3' && $new_status ne ''){       
				print "Wrong wgs set status id entered:";
				$new_status = get_new_statusid();
	    	}
		}
		elsif ($cur_status eq '6'){
	    	print "please enter statusid (5-suppressed, 6-killed [hold date change]):";
            $new_status = get_new_statusid();
	    	while ($new_status ne '5' && $new_status ne '6' && $new_status ne ''){       
				print "Wrong wgs set status id entered:";
				$new_status = get_new_statusid();
	    	}
        }
    }
 
    return $new_status;
}

sub process_private{
    my ($cur_status, $cur_hdate, $dbh) = @_;
    my $new_status = '-';
    my $new_hdate = '';

    print "please enter statusid (1-draft, 2-private [for hold date change], 3-cancelled, 4-public):";

    $new_status = get_new_statusid();

    while ($new_status ne '1' && $new_status ne '2' && $new_status ne '3' 
            && $new_status ne '4' && $new_status ne ''){
       
		print "Wrong wgs set status id entered:";
		$new_status = get_new_statusid();
    }
    if ($new_status eq '4' and $cur_hdate eq '31-DEC-9999'){
		$new_status = confirm_xxx_removal($cur_status, $new_status);
    }   
    if ($new_status eq '1' || $new_status eq "2"){	
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }	      
      	 
    return ($new_status, $new_hdate);
}

sub process_cancelled {
    my ($cur_status, $cur_hdate, $dbh) = @_;
    my $new_status = '-';
    my $new_hdate = '';
 
    print "please enter statusid (1-draft, 2-private, 4-public):";
    
    $new_status = get_new_statusid();

    while ($new_status ne '1' && $new_status ne '2' && $new_status ne '4' && $new_status ne ''){       
		print "Wrong wgs set status id entered:";
		$new_status = get_new_statusid();
    }	      

    if ($new_status eq '1' || $new_status eq '2'){
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }
    	            	 
    return ($new_status, $new_hdate);
}

sub process_public {

    my ($cur_status, $cur_hdate, $ext_ver, $dbh) = @_;
    my $new_status = '-';
    my $new_hdate = '';
    
    if ($ext_ver eq 'pre-public'){#not distributed
		print "please enter statusid (1-draft, 2-private, 3-cancelled):";
		$new_status = get_new_statusid();
		while ($new_status ne '1' && $new_status ne '2' && $new_status ne '3' && $new_status ne ''){       
	    	print "Wrong wgs set status id entered:";
	    	$new_status = get_new_statusid();
		}
    }  
    else {
		print "please enter statusid (5-suppressed, 6-killed):";
    	$new_status = get_new_statusid();
		while ($new_status ne '5' && $new_status ne '6' && $new_status ne ''){       
	    	print "Wrong wgs set status id entered:";
	    	$new_status = get_new_statusid();
		}	      
    }

    if ($new_status eq '1' || $new_status eq '2'){   
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }
    elsif ($new_status eq '6'){
		print "\n***Do you want to permanently kill this wgs set (i.e. no hold date allowed)? (Y/N)(default=Y)?:";
		my $answer = '';
        chomp ( $answer = <STDIN> ); 
        if (uc ($answer) eq 'N' ){
	#        $new_status = '';
	        $new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
	    }
    }
    elsif ($new_status eq '5'){
        print "\n***Do you want to permanently suppress this wgs set (i.e. no hold date allowed)? (Y/N)(default=Y)?:";
        my $answer = '';
        chomp ( $answer = <STDIN> );
        if (uc ($answer) eq 'N' ){
     #       $new_status = '';
            $new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
       }
    }
	            	 
    return ($new_status, $new_hdate);
}

sub process_killed {
    my ($cur_status, $cur_hdate, $dbh) = @_;
    my $new_status = '-';
    my $new_hdate = '';   
    print "please enter statusid (4-public, 5-suppressed, 6-killed [hold date change]):";    	
    $new_status = get_new_statusid();
    while ($new_status ne '4' && $new_status ne '5'  && $new_status ne '6' && $new_status ne ''){       
		print "Wrong set status id entered:";
	 	$new_status = get_new_statusid();
    }    
    if ($new_status eq '4' and $cur_hdate eq '31-DEC-9999'){
		$new_status = confirm_xxx_removal($cur_status, $new_status);
    }   
    if ($new_status eq '6'){
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }	
    if ($new_status eq '5' && $cur_hdate ne '-' ){
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }
	elsif($new_status eq '5' && $cur_hdate eq '-'){
    	print "There is no current hold date for extending.\n"
    }
    return ($new_status, $new_hdate);
}

sub process_suppressed {
    my ($cur_status, $cur_hdate, $dbh) = @_;
    my $new_status = '-';
    my $new_hdate = '';    
    print "please enter statusid (4-public,  5-suppressed[for hold date change], 6-killed):";    
    $new_status = get_new_statusid();
    while ($new_status ne '4' && $new_status ne '5' && $new_status ne '6' && $new_status ne ''){       
		print "Wrong entry status id entered:";
		$new_status = get_new_statusid();
    }	
    if ($new_status eq '6'){
		print "\n***Do you want to permanently kill this wgs set (i.e. no hold date allowed)? (Y/N)(default=Y)?:";
		my $answer = '';
        chomp ( $answer = <STDIN> ); 
        if (uc ($answer) eq 'N' ){	  
	    	$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
		}
    }	  
    
    if ($new_status eq '5' && $cur_hdate ne '-' ){
		$new_hdate = get_new_hdate($dbh, $new_status, $cur_hdate);
    }
    elsif($new_status eq '5' && $cur_hdate eq '-'){
    	print "There is no current hold date for extending.\n"
    }
              	 
    return ($new_status, $new_hdate);
}


#-------------------------------------------------------------------------------
# check holdate.
#-------------------------------------------------------------------------------
sub check_hdate {

    my ($date, $dbh) = @_;
   
    if ( $date ne '' )
    {
	my $sql = "SELECT sign ( to_char ( to_date ( '$date', 'DD-MON-YYYY' ), 'YYYYMMDD' )
                          - to_char ( sysdate, 'YYYYMMDD' ) ) 
                     FROM dual";

	my $sign = dbi_getvalue ( $dbh, $sql );
	( $sign != 1 ) && bail ( "invalid hold date $date, date should be later than today.", $dbh );
    }
}

#-------------------------------------------------------------------------------
# fill @accnos array.
#-------------------------------------------------------------------------------
sub get_acc {
    my ($dbh, $set) = @_;
    my @accnos = ();

	my $sql = "SELECT primaryacc# FROM dbentry WHERE primaryacc# like ? and entry_type in (3,8)";
    my $sth = $dbh->prepare($sql);
	$sth->execute($set . "%");
   	while (my $acc = $sth->fetchrow_array()){
	    push (@accnos,$acc);
	}
    return @accnos;
}

# display a message if entry is conentry
sub check_acc {
    my ($accno, $set, $dbh) = @_;    
    my @accnos = @$accno; 
	my $entry_type ;

    # all accnos in WGS set should have the same statusid to start with and
    # changed to the same statusid

    my $statusid = '';
    my $hdate = '';
    my $ext_ver = '';
    my %status = ();
    my %h_date = ();
    my %ext_ver = ();
    my $status_count = 0;
    my $h_date_count = 0;
    my $ext_ver_count = 0;

   
	foreach my $acc (@accnos){
	    my $sql = "select statusid, 
                        NVL ( to_char ( hold_date, 'DD-MON-YYYY' ), '-'), 
                        decode (ext_ver, 0, 'pre-public', null, 'pre-public', 'public')
                   from dbentry
                  where primaryacc# = ?" ;
  
	    my $sth = $dbh->prepare($sql);
	    $sth->execute($acc);

	    ($statusid, $hdate, $ext_ver)  = $sth->fetchrow_array(); 
    
	    $status{$statusid} = 1;
        $h_date{$hdate} = 1;
        $ext_ver{$ext_ver} = 1;
     }
	 if(@accnos > 1){	
	    $status_count = keys %status;
	    $h_date_count = keys %h_date;
	    $ext_ver_count = keys %ext_ver;

        check_status ($status_count, $h_date_count, $ext_ver_count, $dbh, $set, \%status, \%h_date, \%ext_ver, \@accnos);
	}        
	($statusid) = %status;
	($hdate) = %h_date;
    ($ext_ver) = %ext_ver;   

    return ($statusid, $hdate, $ext_ver);
}

sub check_status {
    my ($status_count, $h_date_count, $ext_ver_count, $dbh, $set, $status, $hdate, $ext_ver, $accessions) = @_;
    my %status = %$status;
    my %h_date = %$hdate;
    my %ext_ver = %$ext_ver;
    my @accnos = @$accessions;
    my $num_acc = scalar (@accnos);

    if ( $status_count > 1){   
		print "ERROR: accession numbers in $set should have the same status:\n\n";
		if ($num_acc <= 15){
	   		printf "%-12s%-10s\n", "Primaryacc#", "Status";
           	print "----------- ----------\n"; 
	   		foreach my $acc (@accnos){
	       		my $sql = "select cv.status
                            from dbentry db, cv_status cv
                           where db.primaryacc# = ?
                             and db.statusid = cv.statusid";

	       		my $sth = $dbh->prepare($sql);
	       		$sth->execute($acc);
	       		my ($status) = $sth->fetchrow_array();	     
	       		printf "%-12s%-10s\n", $acc, $status;
	   		}
        }else {
	       	print "Statuses found\n";
	       	foreach my $key (keys %status){
		   		print "$embl_status{$key}\n";
	       	}	   		
       	}
       dbi_logoff($dbh);
       exit;
    } 
    elsif ($status_count == 1){
		my ($statusid) = %status;
		if ($statusid eq '1' || $statusid eq '6'){
	    	if ($h_date_count > 1){
				check_h_date (\%h_date, $dbh, $set, $statusid, $accessions, $num_acc);
	    	}		    
        }
		elsif ($statusid eq '4'){
	    	if ($ext_ver_count > 1){
				check_ext_ver(\%ext_ver, $dbh, $set, $accessions, $num_acc);
	    	}
		}
    }
}

sub check_h_date {
    my ($dates, $dbh, $set, $status, $accessions, $num_acc) = @_;
    my %h_date = %$dates;
    my @accnos = @$accessions;
    my $hdate;	   
    my $no_date = '';
    my $xxx_date = ''; 

    while (($hdate) = each %h_date){
		if ($hdate eq '-' and $status eq '1'){
	    	$no_date = "ERROR: in the $set Some entries have hold date, some don't.\n\n";
		}			
        elsif ($hdate eq '31-DEC-9999'){	    
	    	$xxx_date = "ERROR: in the $set some entries have hold date 31-DEC-9999.\n\n";	   
		}	
    }    
    if ($no_date || $xxx_date){	
		print $no_date;
		print $xxx_date;
		if ($num_acc <= 15){
	    	print "Hold_date found:\n\n";
            printf "%-12s%-12s\n", "Primaryacc#", "Hold_date";
            print "----------- -------------\n";
	    	foreach my $acc (@accnos){
				my $sql = "select NVL ( to_char ( hold_date, 'DD-MON-YYYY' ), '-')
                           from dbentry
                          where primaryacc# = ?";
                my $sth = $dbh->prepare($sql);
                $sth->execute($acc);
                my ($date) = $sth->fetchrow_array();	
				printf "%-12s%-12s\n", $acc, $date;
	    	}
	    }	
		else {
	    	print "Hold_date found:\n";
			foreach my $key (keys %h_date){
		    	print "$key\n";
			}	    
		}		
    	dbi_logoff($dbh);
    	exit;
	}
}

sub check_ext_ver {
    my ($versions, $dbh, $set, $accessions, $num_acc) = @_;
    my %ext_ver = %$versions;
    my @accnos = @$accessions;
    my $ext_ver;
    print "ERROR: both pre-public and public entries exist in the $set.\n\n";

    if ($num_acc <= 15){
		printf "%-12s%-10s\n", "Primaryacc#", "Status";
        print "----------- ----------\n"; 
		foreach my $acc_no (@accnos){
	    	my $sql = "select decode (ext_ver, 0, 'pre-public', null, 'pre-public', 'public')
                         from dbentry
                        where primaryacc# = ?";
            my $sth = $dbh->prepare($sql);
	    	$sth->execute($acc_no);
	    	my ($ext_version) = $sth->fetchrow_array();
            printf "%-12s%-10s\n", $acc_no, $ext_version;
        }  
    }  
    dbi_logoff ($dbh);
    exit;
}

#-------------------------------------------------------------------------------
# set audit remark.
#-------------------------------------------------------------------------------
sub set_audit {

    my ($remark, $dbh) = @_;

    $remark =~ s/\'/\'\'/g; # works also without the \ but my emacs font-lock does not :( 

    dbi_do ( $dbh, "begin auditpackage.remark := '$remark'; end;" );

}

#-------------------------------------------------------------------------------
# update all accnos.
#-------------------------------------------------------------------------------
sub update_entry {
    my ($set, $new_status, $new_hdate, $dbh) = @_; 
	$set =~ s/\s//g;
	$set = uc ( $set );    
    my $sql = ''; 
    my $part1 = "UPDATE dbentry ";
    my $part2 = '';
    my $part3 = '';   
    if ($new_hdate eq 'N'){
		$new_hdate = '';
    }
 
	$part3 = " WHERE primaryacc#  like '$set%' and entry_type in (3,8)";

    if ($new_status ne "-" && $new_hdate eq "-"){
	
		$part2 = "SET statusid = '$new_status' ";
		print"$set: set entry status = $embl_status{$new_status}\n";
    }
    elsif ($new_status ne "-" && $new_hdate ne "-"){     
		$part2 = "SET statusid = '$new_status', hold_date = to_date('$new_hdate', 'DD-MON-YYYY' )";
		my $date_message = '';
		if ($new_status eq '1' || $new_status eq '5' || $new_status eq '6'){
	    	$date_message = ($new_hdate eq '')? ", no hold date" : ", set hold date = $new_hdate";
		}
		elsif ($new_status eq '2'){
	    	$date_message = ", set hold date = $new_hdate";
		}    
		print "$set: set entry status = $embl_status{$new_status}$date_message\n";  
    }
    elsif ($new_status eq "-" && $new_hdate ne "-"){
		$part2 = "set hold_date = to_date('$new_hdate', 'DD-MON-YYYY' )";
		my $date_message = ($new_hdate eq '')? "no hold date" : "set hold date = $new_hdate";       
		print "$set: $date_message\n";
    }  
    if ($part2 ne ''){
		$sql = $part1 . $part2 . $part3;
		dbi_do ( $dbh, $sql );
    }
}

sub statusWordToCode {
    my $statusWord        = shift;
    my $escapedStatusWord = quotemeta($statusWord);
    my $statusCode        = -1;
    my $matches           = 0;
    foreach my $code (keys %embl_status) {
	if ($embl_status{$code} =~ /$escapedStatusWord/i) {
            $matches++;
            printf "%s matches Code %s, %s\n", $statusWord, $code, $embl_status{$code};
            $statusCode = $code;
        }
    }
    if ($matches == 1) {
        return $statusCode;
    } else {
        return 0;
    }
} ## end sub statusWordToCode

