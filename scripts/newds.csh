#! /bin/csh
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/newds.csh,v 1.6 2001/09/22 18:27:21 redaschi Exp $
# 
#  USAGE: newds.csh <ds> [test]
#
#  MODULE DESCRIPTION:
#
#  Creates a new DS directory, unless the given <ds> already exists in the
#  archive or unpacked.
#
#  MODIFICATION HISTORY:
#
#  31-AUG-2000  Carola Kanz        Created.
#  05-SEP-2001  Nicole Redaschi    Protection of directory must be 770.
#  22-SEP-2001  Nicole Redaschi    added option test.
#
#===============================================================================

set dsno = $1
set test = $2

if ( $dsno == "" ) then

    echo "USAGE: newds.csh <ds> [test]"
    exit

endif

# set the environment
setenv SCRIPT dirsub
source /homes/datalib/.env_scripts

# set the production environment
set archive = $ARCHIVE
set dir     = $DS

# reset to test environment if necessary
if ( $test == test ) then

    set archive = $ARCHIVE_TEST
    set dir     = $DS_TEST

endif

# check whether directory already exists
if ( -d $dir/$dsno ) then
        
    echo "ERROR: DS directory $dsno already exists"
    exit

endif
 
# check in archive       
set dd  = $dsno".tar.gz"
set cnt = `ar t $archive | grep -cx $dd`
if ( $cnt > 0 ) then
	    
    echo "ERROR: DS directory $dsno already exists"
    exit

endif
	    
mkdir $dir/$dsno
chmod 770 $dir/$dsno
echo "Created DS directory $dir/$dsno"

endif
