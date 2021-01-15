for file in *.dat ; do cp $file `echo $file | sed 's/\(.*\.\)dat/\1fflupd/'`; done
