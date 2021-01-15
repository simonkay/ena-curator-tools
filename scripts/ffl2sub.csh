for file in *.ffl ; do mv $file `echo $file | sed 's/\(.*\.\)ffl/\1sub/'`; done
