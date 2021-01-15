#!/sw/arch/bin/perl -w
# nb /ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/genomes/add_project.pl,v 1.7 2008/02/18 15:37:47 szilva Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#                      
#  Graphical user interface to add new genome projects to CV_PROJECT_LIST and
#  update existing records. No deletions or project_code changes are allowed.
#
#  MODIFICATION HISTORY:
#
#  18-OCT-2000  Peter Sterk        created
#  23-APR-2001  Nicole Redaschi    removed check for machine names.
#  10-DEC-2001  Nicole Redaschi    removed check for user 'datalib'.
#
#===============================================================================

use DBI;
use Tk;
use Tk::DialogBox;
use Tk::LabEntry;

my $prefix = "";
my $desc = "";
my $abbrev = "";

my %attr = (
	    PrintError => 0,
	    RaiseError => 0
	    );
my $projects;
my @menus;

$top = MainWindow->new();
$top->title ('New Genome Projects Entry Form');

menu_bar();

$top->Label(-text=>"Query and alter Oracle table CV_PROJECT_LIST")->pack();

lab_entries();

projects_listbox();

action_buttons();

text_message();

MainLoop();

sub menu_bar {
    my $f = $top->Frame(-relief => 'ridge', -borderwidth =>2);
    $f->pack(-side=> 'top', -anchor=> 'n', -expand => 1, -fill => 'x');
    
    foreach (qw/File Help/) {
	push (@menus, $f->Menubutton(-text => $_, -tearoff =>0));
    }
    $menus[$#menus]->pack(-side => 'right');
    $menus[0]->pack(-side => 'left');
    $menus[0]->command(-label=>'Quit',-command=>\&terminate);
    my @message_vars = ("OK","About this form","add_project.pl\nPeter Sterk\nEBI 2000");
    $menus[$#menus]->command(-label=>'About Entry Form', -command=>[\&show_messageBox, @message_vars]);
}

sub terminate {
    exit;
}

sub show_messageBox {
    my ($type, $title, $message) = @_;
    my $button = $top->messageBox(-type => $type,
				  -title => $title,
				  -message => $message);
}

sub clear_fields {
    $prefix = "";
    $desc = "";
    $abbrev = "";
    $projects->selectionClear(0, 'end');
    $text_message->delete('1.0', 'end');
    $text_message->insert('end', "READY\n", 'darkgreen');
}


sub update_row {
    print STDERR "curselection = ".$projects->curselection."\n";
    my $pr= $projects->curselection;
    my $selected_pr = $reverse_project{$pr};

    if ($prefix eq "" || $prefix !~ /^[A-Z]{2}$/i) {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No or invalid two-letter prefix - row not updated.\n", 'red');
	return;
    }
    if ($abbrev eq "") {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No abbreviation given - row not updated.\n", 'red');
	return;
    }
    if ($desc eq "") {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No description given - row not updated.\n", 'red');
	return;
    }
    if (! defined $selected_pr) {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No project selected from list.\n", 'red');
	return;
    }

    $text_message->delete('1.0', 'end');

    my $dbh = DBI->connect('dbi:Oracle:PRDB1','/','', \%attr)        
	or die "Can't connect to database: $DBI::errstr";

    my $sth = $dbh->prepare(q{
	                      UPDATE cv_project_list
			      SET PROJECT_DESC = ?,  
				  PROJECT_ABBREV = ?,
				  PROJECT_ORGANISM_PREFIX = ?
			      WHERE PROJECT_CODE = ?
			      });

    $sth->bind_param(1, $desc, CHAR);
    $sth->bind_param(2, $abbrev);
    $sth->bind_param(3, $prefix);
    $sth->bind_param(4, $selected_pr);

    $sth->execute || dbi_error($DBI::errstr);
    $sth->finish;
    $dbh->disconnect;
    $text_message->delete('1.0', 'end');
}

sub insert_row {
    my $new_code;

    if ($prefix eq "" || $prefix !~ /^[A-Z]{2}$/i) {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No or invalid two-letter prefix - row not inserted.\n", 'red');
	return;
    }
    if ($abbrev eq "") {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No abbreviation given - row not inserted.\n", 'red');
	return;
    }
    if ($desc eq "") {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No description given - row not inserted.\n", 'red');
	return;
    }
    $text_message->delete('1.0', 'end');


    my $dbh = DBI->connect('dbi:Oracle:PRDB1','/','', \%attr)        
	or die "Can't connect to database: $DBI::errstr";

    my $sth0 = $dbh->prepare(q{
			      SELECT max(project_code)
			      FROM cv_project_list
			      });

    $sth0->execute || dbi_error($DBI::errstr);
    while (($new_code) = $sth0->fetchrow_array) {
	last;
    }

    $sth0->finish;

    $new_code += 1; # new project code

    $text_message->insert('end', "New project code is \"$new_code\".\n", 'darkgreen');


    $prefix =~ tr/a-z/A-Z/;

    my $sth = $dbh->prepare(q{
	                      INSERT into cv_project_list values
			      ( ? , ? , ? , ? )
			      });

    $sth->bind_param(1, $abbrev);
    $sth->bind_param(2, $new_code);
    $sth->bind_param(3, $desc);
    $sth->bind_param(4, $prefix);

    $sth->execute || dbi_error($DBI::errstr);
    $sth->finish;
    $dbh->disconnect;
    $text_message->insert('end', "Row inserted for \"$abbrev\".\n", 'darkgreen');

    $projects->delete(0, 'end');
    populate_projects_listbox();
}

sub dbi_error {
    my $dbi_error = $_[0];
    $text_message->delete('1.0', 'end');
    $text_message->insert('end', "$dbi_error\n", 'red');    
}

sub query_project {
    print STDERR "curselection = ".$projects->curselection."\n";
    my $pr= $projects->curselection;
    my $selected_pr = $reverse_project{$pr};

    if (! defined $selected_pr) {
	$text_message->delete('1.0', 'end');
	$text_message->insert('end', "No project selected from list.\n", 'red');
	return;
    }
    my $dbh = DBI->connect('dbi:Oracle:PRDB1','/','', \%attr )        
	or die "Can't connect to database: $DBI::errstr";

    my $sth = $dbh->prepare(q{
                              SELECT PROJECT_ABBREV, PROJECT_DESC, PROJECT_ORGANISM_PREFIX 
	                      FROM cv_project_list
			      WHERE project_code = ? });

    $sth->bind_param(1, $selected_pr);
    $sth->execute || dbi_error($DBI::errstr);;
 
    while (($abbrev, $desc, $prefix) = $sth->fetchrow_array) {
	last;
    }
    $text_message->delete('1.0', 'end');
    $text_message->insert('end', "READY\n", 'darkgreen');

    $sth->finish;
    $dbh->disconnect;

}

sub projects_listbox {
    $frame_0=$top ->Frame->pack(-side=>'top', -fill=>'both');
    $frame_1=$frame_0 ->Frame->pack('-side' => 'left', -anchor=>'nw');

    $frame_1->Label(-text=>"Projects:")->pack(-side=>'left', -anchor=>'nw');
    $projects=$frame_1->ScrlListbox (-width => 30,
				     -height => 12,
				     -font => '9x15',
				     -background => 'white') -> pack(-anchor=>'w', -pady=>5);

    populate_projects_listbox();
}

sub populate_projects_listbox {
    %project = ();
    %reverse_project = ();

    $dbh = DBI->connect('dbi:Oracle:PRDB1','/','', \%attr )        
	or die "Can't connect to database: $DBI::errstr";

    my $sth = $dbh->prepare(q{
                              SELECT project_code, project_abbrev
	                      FROM cv_project_list
			      ORDER BY project_code});

    $sth->execute || dbi_error($DBI::errstr);

    my $no=0;
    while ((my $code, my $abbrev) = $sth->fetchrow_array) {
	$project{$code}=$no;
	$no ++;
	$pr = sprintf "%2d %-25s", $code, $abbrev;
	$projects -> insert ('end', $pr);
    }
    %reverse_project = reverse %project;

    $sth->finish;
    $dbh->disconnect;
    $projects->bind('<Double-1>', \&query_project);
    $projects->selectionClear(0, 'end');
}

sub action_buttons {
    $frame_2=$frame_0 ->Frame->pack('-side' => 'right', -anchor=>'se');

    $button_clear = $frame_2->Button(
				      -text     => 'Clear',
				      -activeforeground => 'blue',
				      -command  => \&clear_fields);
    $button_clear->pack('-side' => 'bottom', -anchor=>'se', -padx=>5, -pady=>0, -fill => 'x');

    $button_insert = $frame_2->Button(
				      -text     => 'Insert',
				      -activeforeground => 'blue',
				      -command  => \&insert_row);
    $button_insert->pack('-side' => 'bottom', -anchor=>'se', -padx=>5, -pady=>0, -fill => 'x');

    $button_update = $frame_2->Button(
				      -text     => 'Update',
				      -activeforeground => 'blue',
				      -command  => \&update_row);
    $button_update->pack('-side' => 'bottom', -anchor=>'se', -padx=>5, -pady=>0, -fill => 'x');

    
    $button_query = $frame_2->Button(
				     -text     => 'Query Project',
				     -activeforeground => 'blue',
				     -command  => \&query_project);
    $button_query->pack('-side' => 'bottom', -anchor=>'se', -padx=>5, -pady=>0, -fill => 'x');
}

sub lab_entries {
    $frame_1=$top ->Frame->pack();

    $entry_accno=$frame_1->LabEntry(-label => 'Prefix:          ',
				    -labelPack => [-side => "left", -anchor => "w"],
				    -width => 3, -font => '9x15',
				    -textvariable => \$prefix)->pack(-side => "top", -anchor => "nw");
    
    $entry_accno=$frame_1->pack(-expand => "yes",
				-padx => 5, -pady => 5,
				-side => "top");
    
    $entry_abbrev=$frame_1->LabEntry(-label => 'Abbreviation:',
				     -labelPack => [-side => "left", -anchor => "w"],
				     -width => 25, -font => '9x15',
				     -textvariable => \$abbrev)->pack(-side => "top", -anchor => "nw");
    
    $entry_abbrev=$frame_1->pack(-expand => "yes",
				 -padx => 5, -pady => 5,
				 -side => "top");

    $entry_descr=$frame_1->LabEntry(-label => 'Description:  ',
				    -labelPack => [-side => "left", -anchor => "w"],
				    -width => 40, -font => '9x15',
				    -textvariable => \$desc)->pack(-side => "top", -anchor => "nw");
    
    $entry_descr=$frame_1->pack(-expand => "yes",
				-padx => 5, -pady => 5,
				-side => "top");
}

sub text_message {
    $frame_3=$top ->Frame->pack(-pady => 5);

    $text_message=$frame_3->Text(-height=>2, -width=>65, -background=>'white')->pack();
    $text_message->tagConfigure('red', -foreground=>'red');
    $text_message->tagConfigure('darkgreen', -foreground=>'darkgreen');
    $text_message->insert('end', "READY\n", 'darkgreen');
}
