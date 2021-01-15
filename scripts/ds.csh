#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/ds.csh,v 1.14 2010/02/23 10:15:04 faruque Exp $
#
#  (C) EBI 2000
#
#  USAGE: source ds.csh <ds> [test]
#
#  MODULE DESCRIPTION:
#
#  cd's to directory <ds> ( retrieves from archive if necessary ) 
#  NOTE: must be sourced to change the directory!
#
#  MODIFICATION HISTORY:
#
#  31-AUG-2000  Carola Kanz        Created.
#  22-SEP-2001  Nicole Redaschi    added option test.
#  24-SEP-2001  Nicole Redaschi    modified chmod command.
#  27-SEP-2006  F. Nardone         Use new archiving strategy
#  11-JUL-2007  Quan Lin           added checking for .tar.gz file
#===============================================================================

set dsno = $1
set test = $2

if ( $dsno == "" ) then

    echo "USAGE: source ds.csh <ds> [test]"
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

    if ( -e $archive/$archived_dir/$dsno.tar.gz ) then

      echo "  extracting from archive file $archived_dir$dsno.tar.gz"

      # if someone interrupts dearchiving, clean-up - catch interrupt of script and also of gunzip and tar
      onintr cleanup
            
      cd $dir
      cp $archive/$archived_dir/$dsno.tar.gz .

      echo "    gunzipping $dir/$dsno.tar.gz"
      gunzip $dsno.tar.gz
      set failure = $status
      if ($failure != 0) then
	    echo ERROR: gunzip failed with status $failure
	    goto cleanup
      endif

      echo "    untarring $dir/$dsno.tar"
      tar xfs $dsno.tar
      set failure = $status
      if ($failure != 0) then
	    echo ERROR: tar failed with status $failure
	    goto cleanup
      endif

      echo "    removing tar $dir/$dsno.tar"
      rm $dsno.tar
      chmod -R ug+rwX $dsno 
      chmod -R  o= $dsno

      onintr 

      cd $dsno

    else
         
     echo "ERROR: DS directory $dsno does not exist"
     exit
        
    endif

endif

    
echo "You are in DS directory $dir/$dsno"

exit

cleanup:
echo "ERROR: Dearchiving interrupted, cleaning-up half-written files and directories"
echo " please be more patient than before@"
if ( -e $dir/$dsno.tar.gz) then
    echo " Removing half-unarchived file $dir/$dsno.tar.gz"
    rm $dir/$dsno.tar.gz
endif
if ( -e $dir/$dsno.tar) then
    echo " Removing half-unarchived file $dir/$dsno.tar"
    rm $dir/$dsno.tar
endif
if ( -e $dir/$dsno) then
    echo " Removing part-unarchived directory $dir/$dsno"
    rm -rf $dir/$dsno
endif

