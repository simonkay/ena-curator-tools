#! /ebi/services/tools/bin/perl -w

# 	$Id: release.pl,v 1.2 2008/02/11 14:50:24 gemmah Exp $	
# release.pl creates table containing "file number" "file name" "description"
# and "number of records" fields
# Author     : Peter Sterk
# Version 1.0: 15-SEP-1999
#############################################################################
 
# ask user for release number and output file name
get_release();

# get list of .txt, .ndx and .dat files for that release
get_files();

# count number of lines for each of the files
get_line_counts();

# write out html table for the html version of the release notes
write_table();

sub get_release {
    $|=1; # no buffering
    print "Please type EMBL release number (e.g. 60): "; 
    chomp($release_no = <STDIN>);
    $reldir = "/ebi/services/idata/embl/release/$release_no";
    print "\nGive path, or just press [Enter] to save files\n";
    print "table$release_no.html and table$release_no.txt in current directory: ";
    # Change to current directory
    chomp($curr_dir = `pwd`);
    chdir "$curr_dir" or die "Can't change to current directory: $!";
    chomp($outfile = <STDIN>);

    # if path contains ~, store file in home directory
    chomp($user = `whoami`);
    if ($outfile =~ /^~[A-Za-z0-9_-]*\/?/) {
        $outfile =~ s/^~[A-Za-z0-9_-]*/\/homes\/$user/;

    }
    # remove terminal slash from path if present
    if ($outfile =~ /.+/) {
	$outfile =~ s/\/$//;
	$outfile .= "/table$release_no";
    } else {
	$outfile .= "table$release_no";
    }

    open OUT, ">$outfile.html" or die "Can't create html output file - check path: $!";
    open OUTTXT, ">$outfile.txt" or die "Can't create text output file - check path: $!";

    print "\n";
    $|=0;
}

sub get_files {
    # subroutine creates arrays of all .txt, .ndx and .dat files

    # get 'n' sort all .txt files
    opendir RELEASEDIR, "$reldir" or die "Can't open release directory. Wrong release number? Please start again: $!";
        @files = grep /\.txt$/, sort readdir RELEASEDIR; 
    closedir RELEASEDIR;

    # get 'n' sort all .ndx files
    opendir RELEASEDIR, "$reldir" or die "Can't open release directory. Start again: $!";
    @ndxfiles = grep /\.ndx$/, sort readdir RELEASEDIR;
    closedir RELEASEDIR;

    # merge @files and @ndxfiles
    push(@files, @ndxfiles);

    # Get 'n' sort all .dat files. Sort them properly (not 1, 11-19, 2, 20-29)
    # Make sure divisions in @divisions are in alphabetical order!
    @datfiles=();


    opendir RELEASEDIR, "$reldir" or die "Can't open release directory. Wrong release number? Please start again: $!";
        @div_temp = grep /\.dat$/, sort readdir RELEASEDIR; 
    closedir RELEASEDIR;
    foreach my $d (@div_temp) {
	# create a list of divisions
	$d =~ s/\.dat//;
	if ($d =~ /^[A-Za-z_]+$/) {
	    push (@divisions,$d);
	} elsif ($d =~ /^([A-Za-z_]+)1$/) {
	    push (@divisions,$1);
	}
    }

    foreach $div (@divisions) {
	if (-e "$reldir/${div}1.dat") {
	    $counter = 1;
	    push(@datfiles, "${div}${counter}.dat");
            ++$counter;
            while (-e "$reldir/${div}${counter}.dat") {
		push(@datfiles, "${div}${counter}.dat");
		++$counter;
	    }
        } else {
	    push (@datfiles, "${div}.dat");
        }
    }
}


sub get_line_counts {
    # create hash filename-number of lines
    %linecounts = ();
    # count lines for each file in @files
    foreach $file (@files) {
	open IN, "$reldir/$file" or die "Can't open $file: $!";
	while (<IN>) {
	    if (eof) {
		$linecounts{$file}= $.;
		print "Number of lines in $file = $linecounts{$file}\n";
	    }       
	}
	close (IN);

    }
    # count lines for each file in @datfiles
    foreach $file (@datfiles) {
	open IN, "$reldir/$file" or die "Can't open $file: $!";

	while (<IN>) {
	    if (eof) {
		$linecounts{$file}= $.;
		print "Number of lines in $file = $linecounts{$file}\n";
	    }       
	}
	close (IN);

    }
}

sub write_table {
    # define descriptions for each file here; use first three letters for .dat files
    %descriptions = ('deleteac'          => 'Deleted accession numbers',
		     'ftable'            => 'Feature Table Documentation',
                     'relnotes'          => 'Release Notes (this document)',
                     'subform'           => 'Data Submission Form',
                     'subinfo'           => 'Data Submission Documentation',
                     'update'            => 'Data Update Form',
		     'usrman'            => 'User Manual',
                     'accno'             => 'Accession Number Index',
                     'citation'          => 'Citation Index',
                     'division'          => 'Division Index',
                     'keyword'           => 'Keyword Index',
                     'shortdir'          => 'Short Directory Index',
                     'species'           => 'Species Index',
                     'est'               => 'EST Sequences',
                     'fun'               => 'Fungi Sequences',
                     'gss'               => 'Genome Survey Sequences',
                     'htg'               => 'High Throughput Genome Sequences',
                     'htgo'              => 'High Throughput Genome Sequences phase 0',
                     'hum'               => 'Human Sequences',
                     'inv'               => 'Invertebrate Sequences',
                     'mam'               => 'Other Mammal Sequences',
                     'org'               => 'Organelle Sequences',
                     'pat'               => 'Patent Sequences',
                     'phg'               => 'Bacteriophage Sequences',
                     'pln'               => 'Plant Sequences',
                     'pro'               => 'Prokaryote Sequences',
                     'rod'               => 'Rodent Sequences',
                     'sts'               => 'STS Sequences',
                     'syn'               => 'Synthetic Sequences',
                     'unc'               => 'Unclassified Sequences',
                     'vrl'               => 'Viral Sequences',
                     'vrt'               => 'Other Vertebrate Sequences' );

    $file_no = 1; # file counter stored in first column of the table

#    uncomment if you want to view the table on its own in web browser:
#    print OUT "<html><body>\n";

    print OUT "<P>The release contains the files shown below, in the order listed. File sizes are given as numbers of records.\n";

    print OUT "<TABLE BORDER ><TR><TD><H2>File Number</H2></TD><TD><H2>File Name</H2></TD><TD><H2>Description</H2></TD><TD><H2>Number of Records</H2></TD></TR>\n";


    print OUTTXT "The release contains the files shown below, in the order listed. File sizes\n";
    print OUTTXT "are given as numbers of records.\n\n";
    print OUTTXT "File Number File Name     Description                      Number of Records\n\n";

    foreach $file (@files) {
	# find the descriptive information. For .txt and .ndx files, 
        # use filename minus extension as hash key
	$file_no_ext = $file;
        $file_no_ext =~ s/\.\w\w\w$//;
        $filename = uc($file);
	$descr = $descriptions{$file_no_ext};
	print OUT "<TR><TD>$file_no</TD><TD>$filename</TD><TD>$descr</TD><TD align=right>$linecounts{$file}</TD></TR>\n";
	printf OUTTXT ("%4d        %-14s%-40s%10d\n",$file_no,$filename,$descr,$linecounts{$file});

        ++$file_no;
    }
    foreach $file (@datfiles) {
	# find the descriptive information for .dat files. Use first three
        # letters of filename as hash key
	$file_no_ext = $file;
        $file_no_ext =~ s/(^\w\w\wo?).*/$1/;
        $filename = uc($file);
	$descr = $descriptions{$file_no_ext};
	print OUT "<TR><TD>$file_no</TD><TD>$filename</TD><TD>$descr</TD><TD align=right>$linecounts{$file}</TD></TR>\n";
	printf OUTTXT ("%4d        %-14s%-40s%10d\n",$file_no,$filename,$descr,$linecounts{$file});
        ++$file_no;
    }
    print OUT "</TABLE>\n";

#    uncomment if you want to view the table on its own in web browser
#    print OUT "</body></html>\n";

    print "HTML able written to $outfile.html\nText file written to $outfile.txt\n"; 

    close OUT;
    close OUTTXT;
} 


__END__

