#!/bin/csh -f

ls -1 | grep  -e '\.cal$' -e '\.del$' -e '\.log$' -e '\.temp$' -e '~$' -e '\.dat$' -e '\.ali$' -e '\.com$' -e '^seq_update\.ack$' -e '^dsin\.txt$' -e '^bulk\.dats$' -e '^dsin\.txt$' -e '^TAX_BAP\.TXT$' -e '\.*_temp$' | xargs -i rm {}
if ( -d "tpa_tmp" ) then
   rm -r "tpa_tmp"
endif
if ( -d "tpa_tmp.del" ) then
   rm -r "tpa_tmp.del"
endif
chmod -R g+rw . >& /dev/null
ls -1
