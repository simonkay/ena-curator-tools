#!/ebi/production/seqdb/embl/tools/bin/perl -w

#-----------------------------------------------------------------------------------
#  schema_diff.sql 
#  script shows schema differences between runtime and last time this script was run
#  via the tables user_objects, user_tab_columns and user_constraints and copies of
#  these tables taken at the last run.
#  30-NOV-1999  Carola Kanz   created
#  07-JUL-2000  Carola Kanz   warn about deleted and invalid trigger
#  12-JAN-2005  Carola Kanz   display all invalid objects
#-----------------------------------------------------------------------------------

# create copy tables: schema_diff_create_tables_DEVT.sql / ..PRDB1.sql



use Oraperl;
use strict;

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $Usage = "USAGE: $0 <username/password\@instance>";
my ($session, $system_id) = login (@ARGV);


#--------------------------------------------------------------------------------
# display invalid objects
#--------------------------------------------------------------------------------

my $sql_inv = "select object_name, object_type from user_objects where status='INVALID'";
my $cur_inv = &ora_open ( $session, $sql_inv )  || die "\n(invalid): $ora_errstr\n";

print "\ninvalid objects\n---------------\n";

while ( my ($name, $type) = &ora_fetch ( $cur_inv )) {
  printf "%-30s  %-20s\n", $name, $type;
}
print "\n\n";

&ora_close ( $cur_inv ) || warn $ora_errstr;


#-------------------------------------------------------------------------------
# table user_objects contains: 
# DATABASE LINK, INDEX, PACKAGE, PACKAGE BODY, PROCEDURE, SEQUENCE, SYNONYM
# TABLE, TRIGGER, VIEW
#-------------------------------------------------------------------------------

## objects not regarded (only modified by this program or temporary tables
## truncated (DDL!) on a regular basis)

my @skip = ( 
"OLD_USER_CONSTRAINTS", 
"OLD_USER_OBJECTS", 
"OLD_USER_TAB_COLUMNS",
"SCHEMADIFF",  
"DISTRIBUTION_BIOSEQ",
"DISTRIBUTION_CON",
"DISTRIBUTION_DBENTRYID",
"DISTRIBUTION_DELETED",
"DISTRIBUTION_FEATID",
"DISTRIBUTION_LOCATION",
"DISTRIBUTION_MISC",
"DISTRIBUTION_PHYSEQID",
"DISTRIBUTION_PRIMARYACC",
"DISTRIBUTION_PUBID",
"DISTRIBUTION_PUBID_EXCLUDED",
"DISTRIBUTION_SEQID",
"DISTRIBUTION_SEQID_CHANGED",
"DISTRIBUTION_SEQID_UNCHANGED",
"I_DISTRIBUTION_PUBID",
"I_NEW_SYNONYM_1", 
"I_NEW_SYNONYM_2",
"I_NEW_SYNONYM_3", 
"I_NEW_TAX_NODE", 
"NEW_SYNONYM", 
"NEW_TAX_NODE", 
"PK_NEW_TAX_NODE",
"ID2_IDX",
"ID_IDX",
"I_DISTRIBUTION_PUBID_EXCLUDED1" ); 

my $obj;
my $where_clause = "";

foreach $obj ( @skip ) {
  $where_clause .= "and object_name != '$obj' ";
}
$where_clause =~ s/and//;     # delete first and ...


my $sql_user_objects = "
select nvl (OBJECT_NAME, '-'), nvl (OBJECT_ID, '0'), nvl (OBJECT_TYPE, '-'), 
       nvl (to_char (CREATED, 'DD-MON-YYYY'), '0'), 
       nvl (to_char (LAST_DDL_TIME, 'DD-MON-YYYY HH24:MI:SS'), '0'), nvl (STATUS, '-'),  
       'insert' xx from user_objects   
where $where_clause  
minus 
select nvl (OBJECT_NAME, '-'), nvl (OBJECT_ID, '0'), nvl (OBJECT_TYPE, '-'), 
       nvl (to_char (CREATED, 'DD-MON-YYYY'), '0'), 
       nvl (to_char (LAST_DDL_TIME, 'DD-MON-YYYY HH24:MI:SS'), '0'), nvl (STATUS, '-'),
       'insert' xx from old_user_objects 
where $where_clause
union
select nvl (OBJECT_NAME, '-'), nvl (OBJECT_ID, '0'), nvl (OBJECT_TYPE, '-'), 
       nvl (to_char (CREATED, 'DD-MON-YYYY'), '0'), 
       nvl (to_char (LAST_DDL_TIME, 'DD-MON-YYYY HH24:MI:SS'), '0'), nvl (STATUS, '-'),
       'delete' xx from old_user_objects 
where $where_clause
minus 
select nvl (OBJECT_NAME, '-'), nvl (OBJECT_ID, '0'), nvl (OBJECT_TYPE, '-'), 
       nvl (to_char (CREATED, 'DD-MON-YYYY'), '0'), 
       nvl (to_char (LAST_DDL_TIME, 'DD-MON-YYYY HH24:MI:SS'), '0'), nvl (STATUS, '-'),
       'delete' xx from user_objects
where $where_clause
order by 1, 7 desc";

my $cur = &ora_open ( $session, $sql_user_objects )  || die "\n(user_objects): $ora_errstr\n";

print "       object_name          object_type   created     last_ddl          status\n";

my @changed_tables;
my %trigger = ();
my @invalid_trigger = ();
my $nof = 0;
my ( $name, $id, $type, $created, $last_ddl, $status, $xx);

while ( ($name, $id, $type, $created, $last_ddl, $status, $xx) = &ora_fetch ($cur)) {
  printf "%-6s %-20s %-13s %-11s %-17s %-7s\n", $xx, substr ($name, 0, 20), $type, $created, 
          substr ($last_ddl, 0, 17), $status;

  # collect table names to check later for changed defaults ( long )-:
  if ( $type eq 'TABLE' && $xx eq 'insert' ) {
    $changed_tables[$nof] = $name;
    $nof++;
  }

  # collect deleted trigger to warn explicitely
  if ( $type eq 'TRIGGER' ) {
    # $xx is either 'delete' or 'insert'
    if ( defined $trigger{$name} && $trigger{$name} ne $xx ) {
      delete $trigger{$name};
    }
    else {
      $trigger{$name}=$xx;
    }
  }

  # collect invalid trigger to warn explicitely
  if ( $type eq 'TRIGGER' && $xx eq 'insert' && $status eq 'INVALID' ) {
    push ( @invalid_trigger, $name )
  }
}

&ora_close ( $cur ) || warn $ora_errstr;


#-------------------------------------------------------------------------------
# table user_tab_columns
# DEFAULTS, COLUMN DATA TYPES
#-------------------------------------------------------------------------------
my $i;
# only "one way" of outer join necessary as columns can't be dropped :-))))
print "\n\n*** user_tab_columns\n"; 

print "       table_name           column               dtype     dlen  n default\n";

for ( $i = 0; $i < $nof; $i++ ) {
  my $sql = "SELECT x.column_name, x.data_default, 
                    nvl (x.data_type, '-'), x.data_length, nvl (x.nullable, '-'),
                    y.data_default,
                    nvl (y.data_type, '-'), nvl (y.data_length, 0),  nvl (y.nullable, '-')
               FROM user_tab_columns x, old_user_tab_columns y
              WHERE x.table_name = '$changed_tables[$i]' 
                AND y.table_name(+) = '$changed_tables[$i]'
                AND x.column_name = y.column_name(+)";

  $cur = &ora_open ( $session, $sql )  || die "\n(user_tab_columns): $ora_errstr\n";

  my ($column_name, $new_default, $new_dtype, $new_dlength, $new_null,
      $old_default, $old_dtype, $old_dlength, $old_null);

  while ( ($column_name, $new_default, $new_dtype, $new_dlength, $new_null,
	   $old_default, $old_dtype, $old_dlength, $old_null) = &ora_fetch ($cur) ) {

    $new_default = ''   if ( !defined $new_default );
    $old_default = ''   if ( !defined $old_default );

    if ( $new_default ne $old_default || $new_dtype ne $old_dtype || 
	 $new_dlength ne $old_dlength || $new_null ne $old_null ) {
      printf "insert %-20s %-20s %-9s %-5s %s %s\n", substr ($changed_tables[$i], 0, 20), 
                substr ($column_name, 0, 20), 
                $new_dtype, $new_dlength, $new_null, $new_default;
      ## print 'delete' row only if column already existed before
      if ($old_dtype ne '-' || $old_dlength != 0 || $old_null ne '-') {
	printf "delete %-20s %-20s %-9s %-5s %s %s\n", substr ($changed_tables[$i], 0, 20),
                substr ($column_name, 0, 20), 
	        $old_dtype, $old_dlength, $old_null, $old_default;
      }
    }
  }
  &ora_close ( $cur ) || warn $ora_errstr;
}

#-------------------------------------------------------------------------------
# table user_constraints
#-------------------------------------------------------------------------------

print "\n\n*** user_constraints\n"; 
# as constraints can be deleted or inserted, "both directions" of outer join 
# have to be considered; union is not possible because of long :-(
# update not possible...

print "       table_name           constraint           t del_rule  status  search_cond.\n";

for ( $i = 0; $i < $nof; $i++ ) {

## insert
  my $sql = "SELECT x.constraint_name, y.constraint_name, 
                    nvl (x.constraint_type, '-'), x.search_condition, 
                    nvl (x.delete_rule, '-'), nvl (x.status, '-') 
               FROM user_constraints x, old_user_constraints y
              WHERE x.table_name = '$changed_tables[$i]' 
                AND y.table_name(+) = '$changed_tables[$i]'
                AND x.constraint_name = y.constraint_name(+)";

  $cur = &ora_open ( $session, $sql )  || die "\n(user_constraints, inserts): $ora_errstr\n";

  my ($constraint_name, $constraint_name2, $ctype, $search_condition, $delete_rule, $status);

  while ( ($constraint_name, $constraint_name2, $ctype, $search_condition, $delete_rule, $status) 
	  = &ora_fetch ($cur) ) {

    ## insert, if constrained not in old_user_constraints
    if (!defined $constraint_name2 ) {
      $search_condition = ''   if ( !defined $search_condition );

      printf "insert %-20s %-20s %-1s %-9s %-7s %s\n", substr ($changed_tables[$i], 0, 20), 
            substr ($constraint_name, 0, 20), 
            $ctype, $delete_rule, $status, $search_condition;
    }
  }

  &ora_close ( $cur ) || warn $ora_errstr;

## delete
  $sql =    "SELECT y.constraint_name, x.constraint_name, 
                    nvl (y.constraint_type, '-'), y.search_condition, 
                    nvl (y.delete_rule, '-'), nvl (y.status, '-') 
               FROM user_constraints x, old_user_constraints y
              WHERE x.table_name(+) = '$changed_tables[$i]' 
                AND y.table_name = '$changed_tables[$i]'
                AND x.constraint_name(+) = y.constraint_name";

  $cur = &ora_open ( $session, $sql )  || die "\n(user_constraints, deletes): $ora_errstr\n";

  while ( ($constraint_name, $constraint_name2, $ctype, $search_condition, $delete_rule, $status)
	  = &ora_fetch ($cur) ) {

    ## delete, if constrained not in user_constraints
    if (!defined $constraint_name2 ) {
      $search_condition = ''   if ( !defined $search_condition );

      printf "delete %-20s %-20s %-1s %-9s %-7s %s\n", substr ($changed_tables[$i], 0, 20),
             substr ($constraint_name, 0, 20), 
             $ctype, $delete_rule, $status, $search_condition;
    }
  }

  &ora_close ( $cur ) || warn $ora_errstr;
}

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------
&ora_logoff ( $session );

### warn about deleted trigger
print "\n\n";
my @trig = keys %trigger;
foreach ( @trig ) {
  if ( $trigger{$_} eq 'delete' ) {
    print "**** deleted trigger $_ !!!\n";
  }
}

### warn about invalid triggers
print "\n";
foreach ( @invalid_trigger ) {
  print "---- trigger $_ is invalid !!!\n";
}


# --------------------------------------------------------------------------------
sub login {

  if (@_ != 1) { 
    die "\n $Usage\n\n";
  }

  my $llogin = $_[0];

  # connect to orcale.

  # substitute '@' by '/' to make split easier
  $llogin =~ s/\@/\//g;

  # split login data for ora_login fct
  my ($username, $password, $sys_id) = split (/\//, $llogin);

  $sys_id = $ENV { "ORACLE_SID" }  if (!(defined $sys_id) || !($sys_id));

  my $ses = &ora_login ( lc($sys_id), $username, $password ) || die "\n(login): $ora_errstr\n";
  print STDERR "\nconnecting to database $sys_id...\n\n";

  &ora_do ( $ses, "ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY'" );
  return $ses, $sys_id;
}
