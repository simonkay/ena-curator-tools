#!/ebi/production/seqdb/embl/tools/bin/perl -w

#################################################################
# diskspace.pl - monitors free disk space on /ebi/services/data #
# sends warning when free space is less than 5% and sends       #
# additional messages for every percent less space              #
# Author  : Peter Sterk                                         #
# 19990827: Version 1                                           #
# 19990831: Version 1.1 Additional cumulative log file (df.log) #
#################################################################

chomp($now = `date +%y%m%d%H%M`);
chomp($free = `df | grep ebi/production/seqdb/embl/data/collab_exchange`);
$free =~ s/^.*\s(\d+)\%.*/$1/;

#open LOG, "/ebi/production/seqdb/embl/tools/curators/scripts/log/diskspace.log" or die "Can't open log file\n";
open LOG, "/ebi/production/seqdb/embl/tools/log/diskspace.log" or die "Can't open log file\n";
while (<LOG>) {
    chomp($percentage = $_);
    $percentage =~ s/ percent.*//;
}
close LOG;

# keep separate log to monitor disk usage over time
#open DFLOG, ">>/ebi/production/seqdb/embl/tools/curators/scripts/log/df.log" or die "Can't open df.log\n";
open DFLOG, ">>/ebi/production/seqdb/embl/tools/log/df.log" or die "Can't open df.log\n";
print DFLOG "$now---$free percent\n";
close DFLOG;

if ($free !~ /\d+/) {
    $free = 60;  # in case log file gets screwed up after system failure
} elsif ($free > 94) {
    if ($free > $percentage) {
	#open LOG, ">>/ebi/production/seqdb/embl/tools/curators/scripts/log/diskspace.log" or die "Can't open log file\n";
	open LOG, ">>/ebi/production/seqdb/embl/tools/log/diskspace.log" or die "Can't open log file\n";
	print LOG "$free percent---$now\n";
	close LOG;
	open MAIL, "|mailx -s 'Automatic message: /ebi/production/seqdb/embl/data/collab_exchange $free\% full' dbgroup\@ebi.ac.uk" or die "Can't fork:$!";
	print MAIL "/ebi/production/seqdb/embl/data/collab_exchange $free\% full, please free up some space.\n";
	close MAIL;
    }
}
if ($free < $percentage && $free < 95) {
    # write new log file
    #open LOG, ">/ebi/production/seqdb/embl/tools/curators/scripts/log/diskspace.log" or die "Can't open log file\n";
    open LOG, ">/ebi/production/seqdb/embl/tools/log/diskspace.log" or die "Can't open log file\n";
    print LOG "$free percent---$now\n";
    close LOG;
}
