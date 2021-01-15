#!/usr/local/bin/tcsh

cd /ebi/production/seqdb/embl/tools/curators/scripts/emblworld

/ebi/production/seqdb/embl/tools/curators/scripts/emblworld/emblworld_maker.pl \
  /@enapro \
  /ebi/production/seqdb/embl/tools/curators/scripts/emblworld/world_august5400x2700.jpg \
  /ebi/www/web/public/Services/EMBLWorld >& \
  /ebi/production/seqdb/embl/tools/curators/scripts/emblworld/emblworld.log

