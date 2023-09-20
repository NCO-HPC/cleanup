#!/bin/sh
set -x

# Added 2020-06
# Taken from cleanup_thindir.sh and modified to use rm instead of rsync
#  Input is a "keep" list ... any file that does not match a pattern in the keep list is deleted.
#  Note that the keep list is passed to egrep, so the format is extended regex rather than the
#  wildcard style rsync include/exclude format used for thin list files passed to cleanup_thindir.sh.

# Updated Arash Bigdeli 2022-10-19 , thin_dir_base is now an input

# usage: cleanup_thindir_rmfiles.sh $keep_list_file $thin_dir_base

keep_list_file=${1:?}
thin_dir_base=${2:?}

if [ ! -s "${keep_list_file}" ]; then
    err_exit "Keep list $keep_list_file does not exist"
fi
if [ $(egrep -c "^-|^\+" ${keep_list_file}) -gt 0 ]; then
    err_exit "Keep list $keep_list_file seems to be in rsync format.  It should be regex."
fi

# Remove comment lines and blank lines from the keep list
sed -e '/^\s*\#/d' -e '/^\s*$/d' $keep_list_file > ./keeplist

# Replace production variable tags in the keep list with their contents
sed -i "s/_ENVIR_/$envir/g" ./keeplist
for var in PDYp1 PDY PDYm1 PDYm2 PDYm3 PDYm4 PDYm5 PDYm6 PDYm7 PDYm8 PDYm9 PDYm10 PDYm11 PDYm12 PDYm13; do
    # Escape the backslash characters in the variable string and replace the
    # variable tags (_PDY_) with the corresponding variable's contents ($PDY)
    if [ -z "${!var}" ]; then
        >&2 echo "WARNING: \$${var} not defined!"
    fi
    eval sed -i "s/_${var}_/\${${var}//\\//\\\\/}/g" ./keeplist
    if [ `echo $keep_list_file |egrep "rap|hrrr"` ]; then
      if [ ${!var} -ge $PDYm2 ]; then
        Year=`echo ${!var} |cut -c1-4`
        Mon=`echo ${!var} |cut -c5-6`
        Day=`echo ${!var} |cut -c7-8`
        timestr=${Year}-${Mon}-${Day}
#       newline=`grep YYYY-MM-DD keeplist| sed -e "s/_YYYY-MM-DD_/\$timestr/g"`
#       sed -e "/YYYY-MM-DD/a $newline" keeplist> keeplist.1
#       mv keeplist.1 keeplist
        grep YYYY-MM-DD keeplist > timestr_recs
        for rec in $(cat timestr_recs); do
          echo $rec
           newline=${rec/_YYYY-MM-DD_/$timestr}
           echo $newline >> keeplist
        done
        if [ ${!var} -eq $PDYm2 ]; then
          sed -e "/YYYY-MM-DD/d" keeplist >keeplist.1
          mv keeplist.1 keeplist
        fi
      fi
    fi
done

# Split the list on lines that begin with a forward slash ("/") or "com/"
csplit -zf thindirparms ./keeplist '/^\(com\)\?\//' {*} --quiet

# For each directory in the keep list, delete all but the indicated files
for dirparms in ./thindirparms??; do
    echo -n "   Directory Specifier and Days to Keep: "
    head -1 $dirparms

#AB    read thin_dir_base keepdays < $dirparms  
    read dummy_thin_dir_base keepdays < $dirparms

#AB    thin_dir_base=$(compath.py ${thin_dir_base})

    # Remove the current PDY from the path if it is present at the end of $thin_dir_base
    thin_dir_base=${thin_dir_base%.$PDY}

    # Gather a list of which data directories need thinning
    keep_dates="${PDY:?}"
    if [ $keepdays -gt 0 ]; then
        keep_dates+=" $(finddate.sh $PDY s-$keepdays)"
    fi
    ls -1d $thin_dir_base* | grep -Ev ${keep_dates// /|} >thin_dir_list
    if [ ! -s thin_dir_list ]; then
        echo "     ... no directories to thin."
        continue
    fi

    sed -e '1d' -e '/^[-+]/d' $dirparms > keep_patterns
    if [ -s keep_patterns ]; then
        echo "----------------- keep_patterns CONTENTS -----------------"
        cat keep_patterns
        echo "--------------------------------------------------------"
    else
        echo "   Skipping $thin_dir_base because no valid rules were found in the list file"
        continue
    fi

    for thin_dir in $(cat ./thin_dir_list); do
        # Sanity check that the directory is not for a future date
        DirDate=$(echo $thin_dir | sed 's/^.*\([0-9]\{8\}\)[0-9]*$/\1/')
        if [[ "$DirDate" =~ ^2[0-9][0-9][0-9][0-9][0-9][0-9][0-9]$ ]] && [ $DirDate -gt $PDY ]; then continue; fi

        # Start the thinning process
        echo
        echo "   Thinning $thin_dir"
        sed -e "s#^^\?#${thin_dir}/#" -e 's#\/\+#/#g' ./keep_patterns > keep_patterns_with_path
        if [ ! -s keep_patterns_with_path ]; then
           echo "No records in keep_patterns_with_path.  Skipping for now... but must fix."
           continue
        fi
        # modify keep pattern to avoid scrubbing active dot files created by concurrent mirror job
        sed -i -r 's#/([^/]*)$#/\\\.?\1#' keep_patterns_with_path
        set -x
        # files for now... modify for empty dirs(?)
        find $thin_dir -type f -print | sort > find_files.list
        egrep -v -f keep_patterns_with_path find_files.list > delete.list
        { set +x; } 2>/dev/null
        for file in $(cat delete.list); do
           echo "Deleting $file"
           if [ "${SENDCOM^^}" = "YES" ]; then
              rm ${file}
           fi
        done
        mv --backup=numbered keep_patterns_with_path keep_patterns_with_path.mvd
        mv --backup=numbered find_files.list find_files.list.mvd
        mv --backup=numbered delete.list delete.list.mvd

    done

#    rm ./thin_dir_list ./keep_patterns
done

#rm ./thindirparms?? ./keeplist
