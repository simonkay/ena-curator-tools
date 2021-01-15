#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  ecNumberFetcher.pl
#
#  MODULE DESCRIPTION:
#
#  Reads enzyme.dat file of enzyme info, names and mappings to a set of text files.
#  including ec_list used by update_ec_numbers.pl
#
#===============================================================================

use strict;
use DBI;
use File::Copy; 

# global settings
my $dataDir = "/ebi/production/seqdb/embl/tools/curators/scripts/collab/ec_lists/";
my $ENZYMEFILE = "/ebi/ftp/private/uniprot/enzyme/enzyme_intenz.dat";
my $FILE_ALL  = "ec.all.list";
my $FILE_LIVE = "ec.live.list";
my $FILE_DEAD = "ec.dead.list";
my $FILE_TRAN = "ec.tran.list";
my $FILE_FIX  = "ec_list"; # the one that update_ec_numbers.pl uses; both dead and remapped in one
my $FILE_OLD_SUFFIX = "_OLD";
my $FILE_PUBLIC_ALL = "/ebi/ftp/pub/databases/embl/misc/ec_number_validation_mappings.txt";
my $verbose = 1;
my $exit_status = 0;

sub ecString($;$) {
    my $ecNumber = shift;
    my $blank = shift;
    if (!(defined($blank))) {
	$blank = '-';
    }
    if ($ecNumber eq 'ROOT') { # ROOT is the special root node
	return "-.-.-.-";
    }
    if ($ecNumber !~ /^[\d\.]+$/) { # Not an ec number at all
	return $ecNumber;
    }

    my $depth = (3 - $ecNumber =~ tr/\././); # eg 1.1.1.1 = depth 0, 1.1.1 = depth 1
    return $ecNumber . ".$blank" x $depth;
}

sub makeNode(\%$$;$) {
    my $rh_ecTree = shift;
    my $ecNumber  = shift;
    my $live      = shift;
    my $transferString = shift;

    if (exists(${$rh_ecTree}{$ecNumber})) {
	printf STDERR "%s already exists\n",$ecNumber;
	return; # NB - this returns parent EC unless new node already existed
    }

    my @transferList   = ();
    if ($transferString) {
	@transferList = split(', ',$transferString);
    }

    my $parent = $ecNumber;
    $parent =~ s/([\d\.]+)\.[\d\-]+/$1/;
    if ($parent eq $ecNumber) {
#	$verbose && printf STDERR "%s can't be ascended further, using 0 unless I already am 0!\n", $ecNumber;
	$parent = "ROOT";
    }
    if ($ecNumber eq "ROOT") {
	undef($parent);
    }
    
    my $depth = (3 - $ecNumber =~ tr/\././); # eg 1.1.1.1 = depth 0, 1.1.1 = depth 1
    if ($ecNumber eq 'ROOT') { # ROOT is the special root node
	$depth++;
    }
    
    ${$rh_ecTree}{$ecNumber} = {'parent' => $parent,
				'depth'  => $depth,
				'live'   => $live,
				'ra_transferList' => \@transferList};

#    $verbose && printf STDERR "parent of %s = %s\n", $ecNumber, (defined($parent)?$parent:"none");
    return $parent; # NB - this returns parent EC unless new node already existed
}

sub addBranchesForLeafNodes(\%) {
    my $rh_ecTree = shift;
    my @leafNodes = (keys %{$rh_ecTree});
    
    foreach my $leaf (@leafNodes){
	# while it is worth doing
	# make parent
        my $newNode   = ${$rh_ecTree}{$leaf}->{'parent'};
        while (defined($newNode) && !(exists(${$rh_ecTree}{$newNode}))){
#	    printf STDERR "making parent %s\n",$newNode;
	    $newNode = makeNode(%{$rh_ecTree}, $newNode, 0); # once a node made, ready to make its parent
        }
	if (${$rh_ecTree}{$leaf}->{'live'}) {
	    my $parent = ${$rh_ecTree}{$leaf}->{'parent'};
	    while ($parent) {
		${$rh_ecTree}{$parent}->{'live'} = 1;
		$parent = ${$rh_ecTree}{$parent}->{'parent'};
	    }
	} elsif (@{${$rh_ecTree}{$leaf}->{'ra_transferList'}}) {
	    my @leafTransferList = @{${$rh_ecTree}{$leaf}->{'ra_transferList'}};

	    my $parent = ${$rh_ecTree}{$leaf}->{'parent'};
	    while ($parent) {
		my @parentaltransferList = @{${$rh_ecTree}{$parent}->{'ra_transferList'}};
		
		# refresh unique list for parent when adding new ones
		my %seen = ();
		@{${$rh_ecTree}{$parent}->{'ra_transferList'}} = 
		    grep { ! $seen{$_}++ } @parentaltransferList,@leafTransferList ;
		$parent = ${$rh_ecTree}{$parent}->{'parent'};
	    }
	}
    }
}

sub validateRemapTargets(\%) {
    my $rh_ecTree = shift;
    my %remapTargets2source; 
    foreach my $node (keys %{$rh_ecTree}) {
	foreach my $target (@{${$rh_ecTree}{$node}->{'ra_transferList'}}) {
	    if (!(defined($remapTargets2source{$target}))) {
		$remapTargets2source{$target} = "";
	    }
	    $remapTargets2source{$target} .= $node." ";
	}
    }
    $verbose && printf STDERR "%d remapping targets\n", scalar(keys %remapTargets2source); 
    foreach my $target (keys %remapTargets2source) {
	if (!(exists(${$rh_ecTree}{$target}))) {
	    printf STDERR "!! %s cited as a transfer target by %sbut it is unhear of\n", $target, $remapTargets2source{$target} ;
	    $exit_status = 2;
	} elsif (!(${$rh_ecTree}{$target}->{'live'})) {
	    printf STDERR "!! %s cited as a transfer target by %sbut it itself is dead\n", $target, $remapTargets2source{$target} ;
	    $exit_status = 2;
	}
    }
}

sub findNearestCommonAncestor(\%$$) {
    my $rh_ecTree = shift;
    my ($ec2, $ec1) = @_;
    my ($ec1_bak, $ec2_bak) = ($ec2, $ec1);
    # we can simplify searching by always starting at the same level
    while (${$rh_ecTree}{$ec1}->{'depth'} < ${$rh_ecTree}{$ec2}->{'depth'}) {
	$ec1 = ${$rh_ecTree}{$ec1}->{'parent'};
    }
    while (${$rh_ecTree}{$ec2}->{'depth'} < ${$rh_ecTree}{$ec1}->{'depth'}) {
	$ec2 = ${$rh_ecTree}{$ec2}->{'parent'};
    }
    
    while ($ec1 && $ec2) {
	if ($ec1 eq $ec2) {
	    return $ec1;
	}
	$ec1 = ${$rh_ecTree}{$ec1}->{'parent'};
	$ec2 = ${$rh_ecTree}{$ec2}->{'parent'};
    }
    die ("no nearest common ancestor for $ec1_bak and $ec2_bak (I got to $ec1 and $ec2)\n");
}

sub transferList2NCA(\%@) {
    my $rh_ecTree = shift;
    my @transferList = @_;
#    $verbose && printf "Remap list %s\n", join(", ", @transferList);
    my $ec1 = pop(@transferList);
    while ((my $ec2 = pop(@transferList)) && ($ec1 ne "ROOT")) {
##	$verbose && printf "   %s Vs. %s", $ec1, $ec2;
	$ec1 = findNearestCommonAncestor(%{$rh_ecTree}, $ec1, $ec2);
##	$verbose && printf " = %s\n", $ec1;
    }
#    $verbose && printf " mapped to %s\n", ecString($ec1);
    return $ec1;
}
    
sub populateTransferTarget(\%) {
    my $rh_ecTree = shift;
    foreach my $node (keys %{$rh_ecTree}) {
	if (@{${$rh_ecTree}{$node}->{'ra_transferList'}}) {
#	    if (scalar(@{${$rh_ecTree}{$node}->{'ra_transferList'}}) > 1) {
	    ${$rh_ecTree}{$node}->{'ra_transferTarget'} = 
		transferList2NCA(%{$rh_ecTree}, @{${$rh_ecTree}{$node}->{'ra_transferList'}});
#	    } 
	}
    }
}

sub getSortedListOfEC(\%) {
    my $rh_ecTree = shift;
    return sort {
	if ($a eq "ROOT") {
	    return -1;
	}
	if ($b eq "ROOT") {
	    return 1;
	}
	my @ec1 = split(/\./,$a);
	my @ec2 = split(/\./,$b);
	for(my $i = 0; $i < 4; $i++) {
	    if(!(defined($ec1[$i]))) {
		$ec1[$i] = 0;
	    }
	    if(!(defined($ec2[$i]))) {
		$ec2[$i] = 0;
	    }
	    if($ec1[$i] == $ec2[$i]) {
		next;
	    }
	    return ($ec1[$i] <=> $ec2[$i]);
	}
	die ("$a equals $b!\n");
    } (keys (%{$rh_ecTree}));
}

sub makeFiles(\%) {
    my $rh_ecTree = shift;
    if (-e "$dataDir/$FILE_ALL") {
	rename "$dataDir/$FILE_ALL", "$dataDir/$FILE_ALL$FILE_OLD_SUFFIX";
    }
    open(my $fh_all,  ">$dataDir/$FILE_ALL")  || die("Can't open $FILE_ALL for writing: $!");
    if (-e "$dataDir/$FILE_LIVE") {
	rename "$dataDir/$FILE_LIVE", "$dataDir/$FILE_LIVE$FILE_OLD_SUFFIX";
    }
    open(my $fh_live, ">$dataDir/$FILE_LIVE") || die("Can't open $FILE_LIVE for writing: $!");
    if (-e "$dataDir/$FILE_DEAD") {
	rename "$dataDir/$FILE_DEAD", "$dataDir/$FILE_DEAD$FILE_OLD_SUFFIX";
    }
    open(my $fh_dead, ">$dataDir/$FILE_DEAD") || die("Can't open $FILE_DEAD for writing: $!");
    if (-e "$dataDir/$FILE_TRAN") {
	rename "$dataDir/$FILE_TRAN", "$dataDir/$FILE_TRAN$FILE_OLD_SUFFIX";
    }
    open(my $fh_tran, ">$dataDir/$FILE_TRAN") || die("Can't open $FILE_TRAN for writing: $!");
    if (-e "$dataDir/$FILE_FIX") {
	rename "$dataDir/$FILE_FIX", "$dataDir/$FILE_FIX$FILE_OLD_SUFFIX";
    }
    open(my $fh_fix, ">$dataDir/$FILE_FIX") || die("Can't open $FILE_FIX for writing: $!");
    
    my @ecList = getSortedListOfEC(%{$rh_ecTree});
#    print join ("\n", @ecList);
    foreach my $ecNumber (@ecList) {
	my $details = ${$rh_ecTree}{$ecNumber};
	my $target;
	my $extraInfo = "";
		
	if ($details->{'live'}) {
	    $target = $ecNumber;
	    printf $fh_live ("%s\n", 
			     ecString($ecNumber));
	} elsif (defined($details->{'ra_transferTarget'})) {
	    $target = $details->{'ra_transferTarget'};
	    printf $fh_tran ("%s\t%s\n", 
			    ecString($ecNumber), 
			    ecString($target));
	    printf $fh_fix  ("%s %s\n", 
			    ecString($ecNumber), 
			    ecString($target));
	    $extraInfo = "Transferred to ".join(', ',@{$details->{'ra_transferList'}});
	} else {
	    $target = "DELETED";
	    printf $fh_dead ("%s\n", 
			     ecString($ecNumber));
	    printf $fh_fix ("%s deleted\n", 
			    ecString($ecNumber));
	}
	printf $fh_all ("%s\t%s\t%s\n", 
			ecString($ecNumber), 
			ecString($target),
			$extraInfo);
    }
    
    close($fh_all)  || die("Can't close $FILE_ALL: $!");
    copy("$dataDir/$FILE_ALL",  "$FILE_PUBLIC_ALL");
    close($fh_live) || die("Can't close $FILE_LIVE: $!");
    close($fh_dead) || die("Can't close $FILE_DEAD: $!");
    close($fh_tran) || die("Can't close $FILE_TRAN: $!");
    close($fh_fix) || die("Can't close $FILE_TRAN: $!");
 }

sub insertFixes(\%) {
    my $rh_ecTree = shift;
    my $new_fixes = 0;
    my $old_fixes = 0;
    my $fqualid ;

    # connect to enapro
    my $dbh = DBI->connect( 'dbi:Oracle:enapro', '/', '', { RaiseError => 1, PrintError => 0, AutoCommit => 0 } );
    if (!(defined($dbh))) {
	print STDERR "Can't connect to database: $DBI::errstr\n ";
	return ($new_fixes, $old_fixes);
    }

    # get fqualid
    my $sql_fqualid = $dbh->prepare("SELECT fqualid FROM cv_fqual where fqual = 'EC_number'");
    $sql_fqualid->execute();
    ($fqualid) = $sql_fqualid->fetchrow_array() || 
	print STDERR "Could not find fqualid for EC_number\n";
    $sql_fqualid->finish();
    if (!(defined ($fqualid))) {
	print STDERR "Can't get fqualid from database database: $DBI::errstr\n";
	return ($new_fixes, $old_fixes);
    }

    # find how many fix rows are in the existing table
    my $sql_current = $dbh->prepare("SELECT count(*) from CV_FQUAL_VALUE_FIX where FQUALID = ?");
    $sql_current->execute($fqualid) || 
	print STDERR "Could not find existing count of EC_number rows in CV_FQUAL_VALUE_FIX: $DBI::errstr\n";
    ($old_fixes) = $sql_current->fetchrow_array();
    $sql_current->finish();

    # wipe current EC number rows - smarter to update them, but this will do for the moment
    my $sql_wipe_current = $dbh->prepare("delete from CV_FQUAL_VALUE_FIX where FQUALID = ?");
    $sql_wipe_current->execute($fqualid) || 
	die("Could not find exisiting count of EC_number rows in CV_FQUAL_VALUE_FIX\n"); # I would prefer not to die like this
    $sql_wipe_current->finish();

    # insert fix rows from the ec hash
    my $sql_insert = $dbh->prepare("INSERT into CV_FQUAL_VALUE_FIX (fqualid,regex,value) VALUES ($fqualid, ?, ?)");
    
    foreach my $ecNumber (keys %{$rh_ecTree}) {
	my $details = ${$rh_ecTree}{$ecNumber};
	my $target;

	if ($details->{'live'}) {
	    next;
	} elsif (defined($details->{'ra_transferTarget'})) {
	    $target = ecString($details->{'ra_transferTarget'});
	} else {
	    $target = "DELETED";
	}
        if ($target ne "-.-.-.-") {
            $new_fixes++;
            $sql_insert->execute(quotemeta(ecString($ecNumber)),$target);
        }     
    }
    $sql_insert->finish();

    $dbh->commit;
    $dbh->disconnect;
    return $new_fixes, $old_fixes;
}

sub main() {
# 1) read enzyme file and make a node for each entry
    open (my $in, "<$ENZYMEFILE") || die("Can't open $ENZYMEFILE: $!");
    my %ecTree;

    my $ecNumber;
    my $live = 0;
    my $transferString;

    while (my $line = <$in>) {
	chomp($line);
        if ($line =~ /^ID   ([0-9\.]*)\s*$/){
            $live = 1;
            $ecNumber = $1;
        }
	elsif ($line =~ /^DE   Transferred entry: /) {
	    $transferString = "";
	    while ($line !~ /\.\s*$/) {
		$transferString .= $line;
		$line = <$in> || last;
		chomp($line);
		if ($line eq '//') {
		    print STDERR "!! $ecNumber transfer string seemed incomplete (no dot at end):\n$transferString\n";
		    $exit_status = 2;
		    last;
		}
	    } 
	    $transferString .= $line;
	    $transferString =~ s/DE   Transferred entry: //;
	    $transferString =~ s/DE   / /g;
	    $transferString =~ s/ and /, /; # now possible list just separated by ', '
	    $transferString =~ s/\.\s*$//;  # remove final .
	    undef($live);
	}
	elsif ($line =~ /^DE   Deleted entry/){
	    undef($live);
	}
	elsif (($line =~ /^\/\//) && (defined($ecNumber))){
	    makeNode(%ecTree, $ecNumber, $live, $transferString);

	    undef($ecNumber);
	    $live = 0;
	    undef($transferString);
	}
    }
    close($in);
    printf "%d leaf nodes created\n", scalar(keys %ecTree);
# 2) create branch nodes for leaves
    addBranchesForLeafNodes(%ecTree);
    printf "%d nodes in tree\n", scalar(keys %ecTree);
# 3) check all remappings goto valid nodes
    validateRemapTargets(%ecTree);
# 4) turn ambiguous remapping lists to degenerate nodes, for both leaves and non-leaf nodes
    populateTransferTarget(%ecTree);
# 5) write to files
    makeFiles(%ecTree);
    print "Files regenerated in $dataDir\n";
# 6) write to cv_fqual_fix
    my ($new_fixes, $old_fixes) = insertFixes(%ecTree);
    print "cv_fqual_fix updated with $new_fixes rows (was $old_fixes rows)\n";
}

main();
exit($exit_status);


