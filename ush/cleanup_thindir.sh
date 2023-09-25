#!/bin/sh

# v2.1.1  Kit Menlove    2018-05-02
# Updated Arash Bigdeli 2022-10-19 , thin_dir_base is now an input

# usage: cleanup_thindir.sh $thin_list_file $thin_dir_base
thin_list_file=${1:?}
thin_dir_base=${2:?}

if [ ! -s "${thin_list_file}" ]; then
    err_exit "Thinning list $thin_list_file does not exist"
fi

# Remove comment lines and blank lines from the thinning list
sed -e '/^\s*\#/d' -e '/^\s*$/d' $thin_list_file > ./thinlist
# Replace production variable tags in the thin list with their contents
sed -i "s/_ENVIR_/$envir/g" ./thinlist
for var in PDYp1 PDY PDYm1 PDYm2 PDYm3 PDYm4 PDYm5 PDYm6 PDYm7 PDYm8 PDYm9 PDYm10 PDYm11 PDYm12 PDYm13; do
    # Escape the backslash characters in the variable string and replace the
    # variable tags (_PDY_) with the corresponding variable's contents ($PDY)
    if [ -z "${!var}" ]; then
        >&2 echo "WARNING: \$${var} not defined!"
    fi
    eval sed -i "s/_${var}_/\${${var}//\\//\\\\/}/g" ./thinlist
    if [ `echo $thin_list_file |grep rap` ]; then
      if [ ${!var} -ge $PDYm2 ]; then
        Year=`echo ${!var} |cut -c1-4`
        Mon=`echo ${!var} |cut -c5-6`
        Day=`echo ${!var} |cut -c7-8`
        timestr=${Year}-${Mon}-${Day}
        newline=`grep YYYY-MM-DD thinlist| sed -e "s/_YYYY-MM-DD_/\$timestr/g"`
        sed -e "/YYYY-MM-DD/a $newline" thinlist> thinlist.1
        mv thinlist.1 thinlist
        if [ ${!var} -eq $PDYm2 ]; then
          sed -e "/YYYY-MM-DD/d" thinlist >thinlist.1
          mv thinlist.1 thinlist
        fi
      fi
    fi
done

# Split the list on lines that begin with a forward slash ("/") or "com/"
csplit -zf thindirparms ./thinlist '/^\(com\)\?\//' {*} --quiet

# For each directory in the thinning list, thin the indicated files
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

    # Set the rsync program and options
    export pgm=$(which rsync)
    rsync_options=${RSYNC_OPTIONS:-"--recursive --delete-excluded"}
    if [[ "${SENDCOM^^}" != "YES" ]] && [[ "$rsync_options" != *--dry-run* ]]; then
        rsync_options+=" --dry-run"
    fi

    # Create a filter rules file to specify advanced exclude and include options # (default is include) by removing the first (which contains the dir and # keepdays) and delete/compress option lines from the directory parameters file.
    sed -e '1d' -e '/^[BDETZ]/d' $dirparms > filterrules
    if [ -s filterrules ]; then
        echo "----------------- filterrules CONTENTS -----------------"
        cat filterrules
        echo "--------------------------------------------------------"
    else
        echo "   Skipping $thin_dir_base because no valid rules were found in the list file"
        continue
    fi

    if [ -s ./filterrules ]; then
        rsync_options+=" --exclude-from=./filterrules"
    fi

    for thin_dir in $(cat ./thin_dir_list); do
        # Sanity check that the directory is not for a future date
        DirDate=$(echo $thin_dir | sed 's/^.*\([0-9]\{8\}\)[0-9]*$/\1/')
        if [[ "$DirDate" =~ ^2[0-9][0-9][0-9][0-9][0-9][0-9][0-9]$ ]] && [ $DirDate -gt $PDY ]; then continue; fi

        # Start the thinning process
        rsync_success=false
        rsync_attempts=0
        echo
        while [ $rsync_success = "false" ]; do
            echo "   Thinning $thin_dir"
            set -x
            $pgm -v $rsync_options $thin_dir/ $thin_dir/
            err=$?
            { set +x; } 2>/dev/null
            if [ $err -eq 23 ] || [ $err -eq 24 ]; then
                >&2 echo "WARNING: error code $err - something may not have been thinned correctly!"
                rsync_success=uncertain
            elif [ $err -ne 0 ]; then
                ((rsync_attempts++))
                if [ $rsync_attempts -ge 2 ]; then
                    err_exit "rsync failed after two attempts trying to thin $thin_dir"
                else
                    sleep 5
                fi
            else
                rsync_success=true
            fi
        done
    done

#    rm ./filterrules ./thin_dir_list
done

#rm ./thindirparms?? ./thinlist
