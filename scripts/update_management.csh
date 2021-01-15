#! /bin/csh
#
#  $Header: 
#
#  USAGE: source update_management.csh <ac> 
#
#  MODULE DESCRIPTION:
#
#  runs a few scripts used for sequence update sequentially.
#  
#  runs 1) whodidit.pl \@enapro $acno; 2) get_ds.pl $acno;  
#  3) cd's to directory <ds> ( retrieves from archive if necessary ) 
#  (NOTE: must be sourced to change the directory!); 4) get_entry_info.pl /@enapro
#  5) ls -l
#
#  MODIFICATION HISTORY:
#
#  18-AUG-2003  Quan Lin        Created. 
#================================================================================

set acno = $1
set test = $2

if ( $acno == "" ) then

    echo "USAGE: $0 <ac> [test]"
    exit

endif

if ($test == "") then

    set database = '/@enapro'
else
    set database = '/@devt'

endif

whodidit.pl $database $acno

set dsno = `get_ds.pl $acno`

if ($status != 0)then
 echo 'get_ds.pl did not run.'
 exit
endif

if ($dsno == 0) then
    echo "***ds does not exist for $acno***"
    exit
endif

# set the environment
setenv SCRIPT dirsub
source /homes/datalib/.env_scripts

# set the production environment
set archive = $ARCHIVE
set dir     = $DS

# Temporary measure until environment is changed
set archive = /ebi/production/seqdb/embl/data/dirsub/ds_archive

# reset to test environment if necessary
if ( $test == test ) then

    set archive = $ARCHIVE_TEST
    set dir     = $DS_TEST

endif

if (-e $dir/$dsno.tar.gz ) then

    echo ""
    echo "Warning: $dir/$dsno.tar.gz exits, please remove it"
endif

if ( -e $dir/$dsno.tar ) then
    echo ""
    echo "$dir/$dsno.tar file exists"
    set arch_dir = `echo $dsno | sed "s|\(...\)|\1/|g" | sed 's|[^/]*/*$||'`
    
    if ( -e $archive/$arch_dir/$dsno.tar.gz ) then
	echo "Possible incompletely retrieved directory for ds $dsno"
	echo "Please delete tar file and directory with the following command:"
	echo "rm -r $dir/$dsno" 
        echo "rm $dir/$dsno.tar" 
	exit
    else 
	echo "Archiving of this ds appears to have been interrupted"
	echo "Please ask Nadeem, Gemma and/or Quan"
	echo "to investigate $dir/$dsno.tar"

    endif

endif
     
# if ds directory exists, just go there...
if ( -d $dir/$dsno ) then

    cd $dir/$dsno

# ... otherwise try to retrieve it from archive
else

    echo "retrieving from archive..."

    # split every 3 chars and throw away the last directory
    # 123456  => 123/
    # 1234567 => 123/456/
    set archived_dir = `echo $dsno | sed "s|\(...\)|\1/|g" | sed 's|[^/]*/*$||'`

echo $archive/$archived_dir/$dsno.tar.gz

    if ( -e $archive/$archived_dir/$dsno.tar.gz ) then
            
      cd $dir
      cp $archive/$archived_dir/$dsno.tar.gz .
      gunzip $dsno.tar.gz
      tar xfs $dsno.tar
      rm $dsno.tar
      chmod -R ug+rwX $dsno 
      chmod -R  o= $dsno

      cd $dsno

    else
         
     echo "ERROR: DS directory $dsno does not exist"
     exit
        
    endif

endif

    
echo "You are in DS directory $dir/$dsno"

get_entry_info.pl $database

ls -l


  








