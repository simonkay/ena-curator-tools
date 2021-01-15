#!/bin/csh -f
ls -1 | grep '\.~[0-9]*~$' | xargs -i rm {}
ls -1
