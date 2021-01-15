#!/bin/tcsh -f

#--------------------------------------------------------------------------------
# converts sequin files with .sqn to EMBL format
# 
# Peter Sterk - 1997
# 22-JUN-2001  Carola Kanz   stoe and mstoe merged and renamed to sequin_to_embl.csh
#                            USAGE: sequin_to_embl.csh [<filename>]
#                              converts <filename>, if given,
#                              otherwise: converts all .sqn files in
#                              the current directory
#                              ( <outfilename> =^ EMBL<infilename> )
# 2-JUL-2003   Quan Lin      changed asn2ff to asn2gb.
#--------------------------------------------------------------------------------                  

if ($#argv > 1) then
    echo "USAGE: $0 [<filename>]"
else if ($#argv == 1) then
    if (-e $argv[1]) then
	asn2gb -i $argv[1] -o EMBL$argv[1] -f e 
    else
        echo "file $argv[1] does not exist";
    endif
else
    # use on all .files in directory
    foreach f (*.sqn) 
        echo "$f"
        asn2gb -i $f -o EMBL$f -f e
    end
endif



