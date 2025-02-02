## Nokia Ovi Store Panic Grab
Origin: [https://archive.org/details/2015_ovi_store_panic] and [https://archive.org/details/2015_ovi_store_panic]

The above deathgrab, decoded with [WARCAT](https://github.com/chfoo/warcat) (the Python version, since it is three times faster than the later rust version), all .dm files stripped of ASCII headers and footers, and sorted into categories.

Note that no files have been renamed. This is on purpose, since it represents exactly what you got from the Ovi Store.

Script used for stripping .dm "encoded" files:
```
#!/bin/bash
FN=$1
HS=`head -n 4 "$1" | wc -c`
HS=`expr $HS + 1`
FS=18
cat "$FN" | tail -c +$HS | head -c -$FS > "$FN".fixed
```
And then obviously remove ".dm.fixed" from the output files.
