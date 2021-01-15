#!/ebi/uniprot/production/tools/perl/perl-5.12.1/bin/perl

use strict; 
use warnings;
use DBI;
use Net::FTP;
use lib '/ebi/uniprot/production/tools/perl/perl-5.12.1/lib';
use Utils;
use Scalar::Util qw(looks_like_number);
my $exit_status = 0;
my $oracle_sid='ETAPRO'; 
my $user='wallet';
my $password='none';
our %institute_query_hash;
our %collection_query_hash;
my $USAGE = "USAGE: $0 No arguments passed

PURPOSE:
  Runs search against the cowner and ccode tables downloaded from NCBI

OPTIONS:
   none

RETURNS:
   0 if no errors were detected, otherwise 1.";

if ( @ARGV < 0 || @ARGV > 0 ) 
{
  die $USAGE;
}

system("clear");
print "Initialising insearch variables\n";
my ( $DB ) = 'ETAPRO';
my $dbh = DBI->connect( "dbi:Oracle:$DB")
|| die ( "ERROR: can't to connect to Oracle\n" );
print "INFO: Database Connection to $DB\n";
  
my $sth = $dbh->prepare('select global_name from global_name')
or die "Couldn't prepare statement: " . $dbh->errstr;

my $usth = $dbh->prepare('select user from dual')
or die "Couldn't prepare statement: " . $dbh->errstr;

$usth->execute()
or die "Couldn't execute statement: " . $sth->errstr;
my $user_name = ($usth->fetchrow_array())[0];

$sth->execute()
or die "Couldn't execute statement: " . $sth->errstr;
my $global_name = ($sth->fetchrow_array())[0];

$sth->finish()
or die "Couldn't close statement: " . $sth->errstr;
print "INFO: The query functions will be run as the $user_name user\n\n";

main( $dbh );
$sth->finish();
undef $dbh;
print "disconnecting and closing insearch variables\n";
print "done.\n";
exit($exit_status);

sub display_menu
{

print "ENA Curation Institute Search\n\n";
print "Qualifier Types: SV=specimen_voucher, BM=bio_material, CC=culture_collection\n\n";
print "Institute report	(1) \'Institute code\' query\n";
print "			(2) All Institute text query\n";
print "			(3) Full Institute record by \'query id\' query\n";
print "Collection report	(4) \'Collection code\' query\n";
print "			(5) All Collection text query\n";
print "			(6) Full Collection record by \'query id\' query\n\n";
}

sub display_prompt
{
print "\nReport No. Or q to quit, r to re-display menu: ";	# Ask again
}

sub main
{
my ($dbh) = @_;

display_menu();
display_prompt();
$a = <STDIN>;
chop $a;
while ($a ne "q")
	{
		if ($a eq "1")
			{
				search_by_institue_code($dbh);
			}
			elsif ($a eq "2")
				{
					ccowner_all_text($dbh);
				}
				elsif ($a eq "3")
					{
						full_record_by_inst_id($dbh);
					}
					elsif ($a eq "4")
						{
							coll_code_query($dbh);
						}
						elsif ($a eq "5")
							{
								ccode_all_text($dbh);
							}
							elsif ($a eq "6")
								{
									full_record_by_coll_id($dbh);
								}
								elsif ($a eq "r")
									{
										system("clear");
										display_menu();
										display_prompt();
									}
		else
			{
				print "Unknown option, please resubmit\n";
				display_prompt();
			}
$a = <STDIN>;		# Get input again
chomp $a;			# Chomp off newline again
}

# Menu option 1
sub search_by_institue_code {
	my ($dbh) = @_;
	my $ref;
	my $interpolated_string;			
	print "Run Inst code query (use % for wild card) : ";
	$interpolated_string = <STDIN>;
	chomp $interpolated_string;
	print "Searching for $interpolated_string\n";
	my $sth = $dbh->prepare("select \
		rownum,
		nvl(INSTITUTE_CODE, 'NA'), \
		nvl(INSTITUTE_ABBREV, 'NA'), \
		nvl(INSTITUTE_SYNONYM, 'NA'), \
		nvl(INSTITUTE_NAME, 'NA'), \
		nvl(COUNTRY, 'NA'), \
		nvl(ADDRESS, 'NA'), \
		nvl(PHONE, 'NA'), \
		nvl(FAX, 'NA'), \
		nvl(INSTITUTE_URL, 'NA'), \
		nvl(SPECIMEN_URL, 'NA'), \
		nvl(COLLECTION_TYPE, 'NA'), \
		nvl(decode(FQUAL, 'specimen_voucher', 'SV', \
								'bio_material', 'BM', \
								'culture_collection', 'CC', \
								'specimen_voucher,bio_material', 'SV/BM', \
								'specimen_voucher,culture_collection', 'SV/CC', \
								'specimen_voucher,culture_collection,bio_material', 'SV/CC/BM', \
								'culture_collection,bio_material', 'CC/BM', FQUAL), 'NA') \          
	from eta.cc_institute \
	where upper(institute_abbrev) like upper(?) \ 
	order by rownum
	");
	if ($interpolated_string)
	{
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;	
		system("clear");
		display_menu();
		print "Option: 1, Searched Inst code query for: $interpolated_string\n\n";
		print "Column List\nquery_id,inst_code,inst_abbrev,institute_synonym,institute_name,country,address,phone,fax,institute_url,collection_type,fqual \
---------------------------------------------------------------------------------------------------\n";
		$ref=$sth->dump_results();
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;
		$ref = $sth->fetchall_arrayref;
		clear_institute_query_hash();
		my $row; 
		my $key; 
		my $value;
		foreach $row ( @{$ref} ) {		
		$institute_query_hash{"@$row[0]"} = "@$row[1]";
		# print "query id @$row[0] will search on @$row[1]\n"; Removed by request of Richard Gibson 24-10-2012
		}
		display_prompt();
	}
	else
	{
		print "\nNo text string entered\n";
		display_prompt();
	}
}

# Menu option 2
sub ccowner_all_text {
	my ($dbh) = @_;
	my $ref;
	my $interpolated_string;			
	print "Run Institute all text Query (use % for wild card) : ";
	$interpolated_string = <STDIN>;
	chomp $interpolated_string;
	my $sth = $dbh->prepare("select 
		rownum,
		nvl(INSTITUTE_CODE, 'NA'), \
		nvl(INSTITUTE_ABBREV, 'NA'), \
		nvl(INSTITUTE_SYNONYM, 'NA'), \
		nvl(INSTITUTE_NAME, 'NA'), \
		nvl(COUNTRY, 'NA'), \
		nvl(ADDRESS, 'NA'), \
		nvl(PHONE, 'NA'), \
		nvl(FAX, 'NA'), \
		nvl(INSTITUTE_URL, 'NA'), \
		nvl(SPECIMEN_URL, 'NA'), \
		nvl(COLLECTION_TYPE, 'NA'), \
		nvl(decode(FQUAL, 'specimen_voucher', 'SV', \
								'bio_material', 'BM', \
								'culture_collection', 'CC', \
								'specimen_voucher,bio_material', 'SV/BM', \
								'specimen_voucher,culture_collection', 'SV/CC', \
								'specimen_voucher,culture_collection,bio_material', 'SV/CC/BM', \
								'culture_collection,bio_material', 'CC/BM', FQUAL), 'NA') \          
	from eta.cc_institute \
	where upper(INSTITUTE_CODE) like upper('%'||:1||'%') \
	or upper(INSTITUTE_ABBREV) like upper('%'||:1||'%') \
	or upper(INSTITUTE_SYNONYM) like upper('%'||:1||'%') \
	or upper(INSTITUTE_NAME) like upper('%'||:1||'%') \
	or upper(COUNTRY) like upper('%'||:1||'%') \
	or upper(ADDRESS) like upper('%'||:1||'%') \
	or upper(PHONE) like upper('%'||:1||'%') \
	or upper(FAX) like upper('%'||:1||'%') \
	or upper(INSTITUTE_URL) like upper('%'||:1||'%') \
	or upper(SPECIMEN_URL) like upper('%'||:1||'%') \
	or upper(COLLECTION_TYPE) like upper('%'||:1||'%') \
	or upper(FQUAL) like upper('%'||:1||'%')
	");
	if ($interpolated_string)
	{
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;	
		system("clear");
		display_menu();
		if ($sth)
		{
			print "Option: 2, Searched all text query for: $interpolated_string\n\n";
			print "Column List\ninst_id,inst_code,unique_name,country,inst_name,address,collection_type,comments,qualifier_type,unique_name \
---------------------------------------------------------------------------------------------------\n"; 
			$ref=$sth->dump_results();
			$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;
			$ref = $sth->fetchall_arrayref;
			clear_institute_query_hash();
			my $row; 
			my $key; 
			my $value;
			foreach $row ( @{$ref} ) {		
			$institute_query_hash{"@$row[0]"} = "@$row[1]";
			# print "query id @$row[0] will search on @$row[1]\n"; Removed by request of Richard Gibson 24-10-2012
		}
		}
		else
		{
			print STDERR "INFO: Error running query for $interpolated_string, restart insearch.pl or if problems resumes, consult ena development support\n";	
		}
		display_prompt();
	}
	else
	{
		print "\nNo text string entered\n";
		display_prompt();
	}
}

# Menu option 3
sub full_record_by_inst_id {
	my ($dbh) = @_;
	my $ref;
	my $row;
	my $key; 
	my $value;
	my $interpolated_string;
	system("clear");
	display_menu();
	foreach $key (sort { $a <=> $b} keys %institute_query_hash) {
    print "query id $key will search on $institute_query_hash{$key}\n";
		}
	print "\nRun Full CC_INSTITUTE record by query_id (as created by options 1,2) : ";
	$interpolated_string = <STDIN>;
	chomp $interpolated_string;
	$interpolated_string=$institute_query_hash{"$interpolated_string"};
	my $sth = $dbh->prepare("select \
		nvl(INSTITUTE_CODE, 'NA'), \
		nvl(INSTITUTE_ABBREV, 'NA'), \
		nvl(INSTITUTE_SYNONYM, 'NA'), \
		nvl(INSTITUTE_NAME, 'NA'), \
		nvl(COUNTRY, 'NA'), \
		nvl(ADDRESS, 'NA'), \
		nvl(PHONE, 'NA'), \
		nvl(FAX, 'NA'), \
		nvl(INSTITUTE_URL, 'NA'), \
		nvl(SPECIMEN_URL, 'NA'), \
		nvl(COLLECTION_TYPE, 'NA'), \
		nvl(decode(FQUAL, 'specimen_voucher', 'SV', \
								'bio_material', 'BM', \
								'culture_collection', 'CC', \
								'specimen_voucher,bio_material', 'SV/BM', \
								'specimen_voucher,culture_collection', 'SV/CC', \
								'specimen_voucher,culture_collection,bio_material', 'SV/CC/BM', \
								'culture_collection,bio_material', 'CC/BM', FQUAL), 'NA') \ 
	from eta.cc_institute \
	where institute_code = ? \
	order by institute_code
	");
	
	if ( defined $interpolated_string && $interpolated_string=~ /^[A-Za-z]/ )
	{
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;	
		system("clear");
		display_menu();
		$ref = $sth->fetchall_arrayref;
		print "Option: 3, Search Full record by query code query for: $interpolated_string\n\n";
		print "Column List\ninstitute_code,institute_abbrev,institute_synonym,institute_name,country,address,phone,fax,institute_url,specimen_url,collection_type,fqual \
------------------------------------------------------------------------------------------------------------------------------\n"; 
		my $row;
		foreach $row ( @{$ref} ) {
		print "@$row\n\n"; }
		print "\n";
		display_prompt();
	}
	else
	{
		print "\n\nQuery id is a numeric value created by running an option 1 or 2 query, instead, an invalid number, string or a null was entered.\n";
		display_prompt();
	}
}  

# Menu option 4
sub coll_code_query {
my ($dbh) = @_;
	my $ref;
	my $interpolated_string;			
	print "Run COLLECTION_CODE query (use % for wild card) : ";
	$interpolated_string = <STDIN>;
	chomp $interpolated_string;
	my $sth = $dbh->prepare("select \
		rownum,
		nvl(cci.institute_code, 'NA'), \
        nvl(cci.institute_name, 'NA'), \
        nvl(ccc.COLLECTION_NAME, 'NA'), \
        nvl(ccc.COLLECTION_CODE, 'NA'), \
        nvl(ccc.COLLECTION_TYPE, 'NA'), \
        nvl(ccc.COLLECTION_URL, 'NA'), \
		nvl(decode(ccc.FQUAL, 'specimen_voucher', 'SV', \
                                'bio_material', 'BM', \
                                'culture_collection', 'CC', \ 
                                'specimen_voucher,bio_material', 'SV/BM', \ 
                                'specimen_voucher,culture_collection', 'SV/CC', \ 
                                'specimen_voucher,culture_collection,bio_material', 'SV/CC/BM', \ 
                                'culture_collection,bio_material', 'CC/BM', ccc.FQUAL),'NA') \
	from eta.cc_collection ccc \
	join eta.cc_institute cci \
	on ccc.institute_code = cci.institute_code
	where upper(ccc.collection_code) like upper( ? ) \
	order by rownum
	");
	if ($interpolated_string)
	{
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;	
		system("clear");
		display_menu();
		print "Option: 4, Searched all text query for: $interpolated_string\n\n";
		print "Column List\ninstitute_code,institute_name,collection_name,collection_code,collection_type,collection_url,fqual \
----------------------------------------------------------------------------------------------------------------------\n"; 
		$ref=$sth->dump_results();
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;
		$ref = $sth->fetchall_arrayref;
		clear_collection_query_hash();
		my $row; 
		my $key; 
		my $value;
		foreach $row ( @{$ref} ) {		
		$collection_query_hash{"@$row[0]"} = "@$row[1], @$row[3]";
		# print "query id @$row[0] will search on @$row[1], @$row[3]\n"; Removed by request of Richard Gibson 24-10-2012
		}
		display_prompt();
	}
	else
	{
		print "\nNo text string entered\n";
		display_prompt();
	}
}  
	
	# Menu option 5
	sub ccode_all_text {
	my ($dbh) = @_;
	my $ref;
	my $interpolated_string;			
	print "Run CC_COLLECTION all text query (use % for wild card) : ";
	$interpolated_string = <STDIN>;
	chomp $interpolated_string;
	if ($interpolated_string) { print "Searching for $interpolated_string\n";}
	my $sth = $dbh->prepare("select
		rownum,
		nvl(cci.INSTITUTE_CODE, 'NA'), \
        nvl(cci.INSTITUTE_NAME, 'NA'), \
        nvl(ccc.COLLECTION_NAME, 'NA'), \
        nvl(ccc.COLLECTION_CODE, 'NA'), \
        nvl(ccc.COLLECTION_TYPE, 'NA'), \
        nvl(ccc.COLLECTION_URL, 'NA'), \
		nvl(decode(ccc.FQUAL, 'specimen_voucher', 'SV', \
                                'bio_material', 'BM', \
                                'culture_collection', 'CC', \ 
                                'specimen_voucher,bio_material', 'SV/BM', \ 
                                'specimen_voucher,culture_collection', 'SV/CC', \ 
                                'specimen_voucher,culture_collection,bio_material', 'SV/CC/BM', \ 
                                'culture_collection,bio_material', 'CC/BM', ccc.FQUAL),'NA') \
	from eta.cc_collection ccc \
	join eta.cc_institute cci \
	on ccc.institute_code = cci.institute_code
	where upper(ccc.institute_code) like upper('%'||:1||'%') \
	or upper(ccc.collection_name) like upper('%'||:1||'%') \
	or upper(ccc.collection_code) like upper('%'||:1||'%') \
	or upper(ccc.collection_type) like upper('%'||:1||'%') \
	or upper(ccc.collection_url) like upper('%'||:1||'%') \
	order by rownum
	");
	if ($interpolated_string)
	{
		$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;	
		system("clear");
		display_menu();
		if ($sth)
		{
			print "Option: 5, Searched all text query for: $interpolated_string\n\n";
			print "Column List\ninstitute_code,institute_name,collection_name,collection_code,collection_type,collection_url,fqual \
------------------------------------------------------------------------------------------------------------------------------\n"; 
			$ref=$sth->dump_results();
			$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;
			$ref = $sth->fetchall_arrayref;
			clear_collection_query_hash();
			my $row; 
			my $key; 
			my $value;
			foreach $row ( @{$ref} ) {		
			$collection_query_hash{"@$row[0]"} = "@$row[1], @$row[3]";
			# print "query id @$row[0] will search on @$row[1], @$row[3]\n"; # Removed by request of Richard Gibson 24-10-2012
			}
		}
			else
		{
			print STDERR "INFO: Error running query for $interpolated_string, restart insearch.pl or if problems resumes, consult ena development support\n";
		}
		display_prompt();
	}
	else
	{
		print "\nNo text string entered\n";
		display_prompt();
	}
} 
	
	# Menu option 6
	sub full_record_by_coll_id {
	my ($dbh) = @_;
	my $ref;
	my $row;
	my $key; 
	my $value;
	my $interpolated_string;
	system("clear");
	display_menu();
	foreach $key (sort { $a <=> $b} keys %collection_query_hash) {
    print "query id $key will search on $collection_query_hash{$key}\n";
		}
	print "\nRun Full CC_COLLECTION record by query_id (as created by option 4,5) : ";
	$interpolated_string = <STDIN>;
	chomp $interpolated_string;
	$interpolated_string=$collection_query_hash{"$interpolated_string"};
	print "Searching for $interpolated_string\n";
	my $sth = $dbh->prepare("select 
		nvl(cci.INSTITUTE_CODE, 'NA'), \
        nvl(cci.INSTITUTE_NAME, 'NA'), \
        nvl(ccc.COLLECTION_NAME, 'NA'), \
        nvl(ccc.COLLECTION_CODE, 'NA'), \
        nvl(ccc.COLLECTION_TYPE, 'NA'), \
        nvl(ccc.COLLECTION_URL, 'NA'), \
		nvl(decode(ccc.FQUAL, 'specimen_voucher', 'SV', \
                                'bio_material', 'BM', \
                                'culture_collection', 'CC', \ 
                                'specimen_voucher,bio_material', 'SV/BM', \ 
                                'specimen_voucher,culture_collection', 'SV/CC', \ 
                                'specimen_voucher,culture_collection,bio_material', 'SV/CC/BM', \ 
                                'culture_collection,bio_material', 'CC/BM', ccc.FQUAL),'NA') \
	from eta.cc_collection ccc \
	join eta.cc_institute cci \
	on ccc.institute_code = cci.institute_code
	where upper(cci.institute_code) = upper( ? )
	order by cci.institute_code
	");
	($interpolated_string) = $interpolated_string =~ /^.{0}(.*?),/s;
	$sth->execute($interpolated_string) or die "Couldn't execute statement: " . $sth->errstr;	
	system("clear");
	$ref = $sth->fetchall_arrayref;
	display_menu();
	if (scalar @{$ref} > 0)
	{
		print "Option: 6, Searched for institute code: $interpolated_string\n\n";
		print "Column List\ninstitute_code,institute_name,collection_name,collection_code,collection_type,collection_url,fqual \
---------------------------------------------------------------------------------------------------------------\n";
		my $row;
		foreach $row ( @{$ref} ) {
		print "@$row\n\n"; }
		display_prompt();
	}
	else
	{	
	if ($interpolated_string)
	{
		print "No rows returned for coll id query for $interpolated_string\n";
		display_prompt();
	}
	else
	{
		print "\n\nQuery id is a numeric value created by running an option 4 or 5 query, instead, an invalid number, string or a null was entered.\n";
		display_prompt();
				}
			}
		}
	sub clear_institute_query_hash {
	for (keys %institute_query_hash) # Clear dow query hash (institute_query_hash) before refilling it.
		{
			delete $institute_query_hash{$_};
		}
	}
	sub clear_collection_query_hash {
	for (keys %collection_query_hash) # Clear dow query hash (collection_query_hash) before refilling it.
		{
			delete $collection_query_hash{$_};
		}
	}
}