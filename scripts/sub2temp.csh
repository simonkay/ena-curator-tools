for file in *.sub ; do cp $file `echo $file | sed 's/\(.*\.\)sub/\1temp/'`; done
