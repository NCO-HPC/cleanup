#!/bin/bash
################################################################################
# History: APR 2021 - Adapted for WCOSS2
#
# For a given environment (/lfs/h1/ops/<envir>/):
#   1) Clean com/ directories
#   2) Thin com/ directories
#   3) Clean tmp/
#   4) Clean dcom/
#   5) Package up and clean com/output/
#   6) Clean packages/
################################################################################
postmsg "$jlogfile" "$0 has begun"

################################################################################
# 1.  Clean com/ directories
################################################################################
if [ $cleanup_com == YES ]; then
    date
    echo "Clean com/ directories"
    sed -e '/^\s*\#/d' -e '/^\s*$/d' -e 's/ //g' ${PARMcleanup:?}/cleanup_rm_com > cleanup_rm_com
    export pgm=${USHcleanup:?}/cleanup_rmdir.sh # SENDCOM check is in cleanup_rmdir.sh
    export IFS="|"
    while read NET DUMMYSHORTVER RUN COMFS TYPE KEEPTIME ; do
	    SHORTVER=$(get2dver.py $NET)
#	    SHORTVER=$(python ${USHcleanup}/get2dver.py $NET)
        echo
        if [ "${COMFS,,}" = "compath" ]; then
            COM=$(compath.py --envir=$envir $NET/$SHORTVER/$RUN)
            MODELCOMROOT=${COM%/$NET/$SHORTVER/$RUN}
            if [[ "$MODELCOMROOT" != /lfs/* ]]; then
                echo " - NET=$NET RUN=$RUN MODELCOMROOT=$MODELCOMROOT"
                continue
            fi
        elif [ "${COMFS,,}" = "comh1" ]; then # add other file systems by duplicating this clause
            MODELCOMROOT=${COMROOT:-/lfs/h1/ops/${envir}/com}
        elif [ "${COMFS^^}" = "ALL" ]; then
            MODELCOMROOT="/lfs/h1/ops/${envir}/com" # separate with vertical pipes when adding new comroots
        fi
        echo " * NET=$NET RUN=$RUN MODELCOMROOT=$MODELCOMROOT KEEPTIME=$KEEPTIME TYPE=$TYPE"

        for comroot in $MODELCOMROOT; do
            version_list=$(ls $comroot/$NET | awk -F"/" '{print $NF}')
            while read -r veri; do
            	if [[ ! $comroot =~ "/$envir/" ]]; then err_exit "comroot $comroot does not contain envir $envir (NET=$NET RUN=$RUN)" ; fi
            	directory=$comroot/$NET/$veri
            	echo "Cleaning up $directory/$RUN"
            	echo ${pgm:?} ${directory:?} ${RUN:?} ${KEEPTIME:?} ${TYPE:?}
            	${pgm:?} ${directory:?} ${RUN:?} ${KEEPTIME:?} ${TYPE:?}
            	if [ $? -ne 0 ]; then
            	    err_exit "Command '$pgm $directory $RUN $KEEPTIME $TYPE' did not complete successfully"
            	fi
           done <<< "$version_list"
        done
    done < cleanup_rm_com
    unset IFS
fi
# Check for files not owned by production or para users/groups:
badfiles=$(find /lfs/h1/ops/${envir}/com -maxdepth 3 \( ! \( -user ops.prod -o -user ops.para \) -o ! \( -group prod -o -group para -o -group rstprod \) \))
if [ ! -z $badfiles ]; then
  echo -e "WARNING: The following files have illegal owners/groups:\n$badfiles" | mail.py -s "$envir cleanup: illegal com file ownership" $MAILTO
fi
echo -e "com/ cleanup complete\n"

################################################################################
# 2.  Thin com/ directories
################################################################################
if [ $thin_com == YES ]; then # SENDCOM check is in cleanup_thindir.sh
    date
    echo "Thin com/ directories..."
    for thinfile in ${PARMcleanup}/cleanup_thin_*.list; do
        if [ -s $thinfile ]; then
	    read -r NET DUMMYSHORTVER RUN < <(awk -F'[/ ]' '{NR=1;print $2,$3,$4}' $thinfile)
	    SHORTVER=$(get2dver.py $NET)
#	    SHORTVER=$(python ${USHcleanup}/get2dver.py $NET)
	    echo NET=$NET SHORTVER=$SHORTVER RUN=$RUN
	    echo "setting com to : compath.py --envir=$envir $NET/$SHORTVER/$RUN"
            COM=$(compath.py --envir=$envir $NET/$SHORTVER/$RUN)
	    echo COM=$COM
            MODELCOMROOT=${COM%/$NET/$SHORTVER/$RUN}
	    echo MODELCOMROOT=$MODELCOMROOT
            version_list=$(ls $MODELCOMROOT/$NET | awk -F"/" '{print $NF}')
	    echo version_list=$version_list
            echo "Finding other model versions of thinfile '$thinfile'"
	    mkdir $(basename $thinfile)
	    cd $(basename $thinfile)
	    echo $thinfile
            while read -r veri; do
              COM=$(compath.py --envir=$envir $NET/$veri/$RUN)
              err=$?
              if [ $err -ne 0 ]; then continue; fi
	      v_thinfile=${veri}_$(basename $thinfile)
	      sed "s,$SHORTVER,$veri,g" $thinfile > $v_thinfile
	      if [[ "$thinfile" =~ _keep.list ]]; then  # use rm instead of rsync
                export pgm=${USHcleanup:?}/cleanup_thindir_rmfiles.sh
	      else
	        export pgm=${USHcleanup:?}/cleanup_thindir.sh
	      fi
              echo "Proccessing the version based  '$v_thinfile'"
              echo $pgm $v_thinfile $COM
              $pgm $v_thinfile $COM
              export err=$? ; err_chk "$pgm $thinfile did not complete successfully"
            done <<< "$version_list"
            cd ..
        fi
    done
fi

################################################################################
# 3. Remove working directories/files older than one day.
#    Dec 2011 - Changed from mtime to ctime to avoid premature cleanup of
#    files added via 'cp -p'.
################################################################################
if [[ "${thin_tmp^^}" == YES && "$SENDCOM" == YES ]]; then
    date
    echo "Thinning tmp (DATAROOT=${DATAROOT})"
    find ${DATAROOT?"DATAROOT not set"}/* -ctime +1 > thin_tmp_list.$jobid
    for file in $(cat thin_tmp_list.$jobid); do
        rm -rf $file
    done
fi

#########################################################################
# 4. Clean up dcom/
#########################################################################

if [[ ${DCOMROOT:?} =~ /$envir/ && "$cleanup_dcom" == YES ]]; then
    date
    echo "Cleaning dcom (DCOMROOT=$DCOMROOT)"
    # SENDCOM check is in cleanup_rmdir.sh
    echo "Cleaning YYYYMMDD dcom subdirectories"
    ${USHcleanup:?}/cleanup_rmdir.sh ${DCOMROOT} / 10days SUBYMD
    echo "Cleaning YYYYMM dcom subdirectories"
    ${USHcleanup:?}/cleanup_rmdir.sh ${DCOMROOT} / 7months SUBYM
    echo "Cleaning dbntmp"
    ${USHcleanup:?}/cleanup_rmdir.sh ${DCOMROOT} dbntmp 2day FIXED
    # Check for directories with bad names (all numbers but not valid dates):
    nwstraydirs=$(find ${DCOMROOT} -maxdepth 1 -type d \( -user ops.prod -o -user ops.para \) -regextype posix-egrep -regex '.*/[[:digit:]]+$' \( ! -regex '.*/20[[:digit:]]{4}$' -a ! -regex '.*/20[[:digit:]]{6}$' \))
    dfstraydirs=$(find ${DCOMROOT} -maxdepth 1 -type d \( -user dfprod -o -user dfpara \) -regextype posix-egrep -regex '.*/[[:digit:]]+$' \( ! -regex '.*/20[[:digit:]]{4}$' -a ! -regex '.*/20[[:digit:]]{6}$' \))
    if [[ ! -z $nwstraydirs ]]; then
      echo -e "The following directories were found in ${DCOMROOT}:\n$nwstraydirs"  | mail.py -s "$envir cleanup: stray DCOM directories (ops)" $MAILTO
    fi
    if [[ ! -z $dfstraydirs ]]; then
      echo -e "The following directories were found in ${DCOMROOT}:\n$dfstraydirs"  | mail.py -s "$envir cleanup: stray DCOM directories (df)" $MAILTO -c $MAILCC
    fi
elif [ "$cleanup_dcom" == YES ]; then
    err_exit "dcom was not cleaned due to environment mismatch between ${DCOMROOT} and ${envir}"
fi

#########################################################################
# 5. Package up output/ directories and remove old ones
#########################################################################
if [[ $SENDCOM != YES || $cleanup_output != YES ]]; then
    postmsg "$jlogfile" "$0 has completed"
    exit 0
fi

date
echo "Cleaning $OUTPUTROOT"
set -x
oldestdatetokeep=$PDYm7

# Looping over YYYYMMDD-formatted directories:
for dirfullpath in $(ls -d $OUTPUTROOT/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]); do
    # Skip recent dates:
    if (( "$(basename ${dirfullpath:?})" >= "${oldestdatetokeep:?}" )); then continue; fi
    tarfullpath=${dirfullpath}.tar.xz
    # Package it up if it's not already packaged:
    if [ ! -f $tarfullpath ]; then
        echo -n "Creating ${tarfullpath}..."
#        tar --create --xz --file $tarfullpath $dirfullpath
        tar -c -I 'xz -T8' -f $tarfullpath $dirfullpath
        if [[ $? -ne 0 || ! -f $tarfullpath ]]; then err_exit "Failed to create $tarfullpath"; continue; fi
    fi
    # Verify everything got saved before deleting:
    diffs=$(diff <(find $dirfullpath -type f | sort) <(tar tf $tarfullpath | grep -v "/$" | sed 's|^|/|' | sort))
    if [ $? -ne 0 ]; then err_exit "Verification failed for $tarfullpath"; continue; fi
    # DELETE:
    if [ -f $tarfullpath ]; then rm -rf $dirfullpath; fi
done

#########################################################################
# 6. Clean packages/
#########################################################################
if [[ $cleanup_packages == YES && ${day,,} == monday ]]; then
    date
    echo "Cleaning packages/ (PACKAGEROOT=$PACKAGEROOT)"
    $USHcleanup/getpackagestodelete.py ${PACKAGEROOT:-/lfs/h1/ops/$envir/packages} > $DATA/packagepathstodelete 2> $DATA/packagewarnings
    export err=$? ; pgm=getpackagestodelete.py err_chk "getpackagestodelete.py error, $(cat $DATA/packagewarnings)"
    if [ $(grep -c . $DATA/packagepathstodelete) -gt 0 ]; then
        echo -e "\nThe following packages have been deleted: \n" > $DATA/packagedeletions
    fi
    for packagepathtodelete in $(cat packagepathstodelete) ; do
	brspath=$(echo $packagepathtodelete | sed  "s/\/packages/\/brs\/packages/")
	if [[ $SENDCOM == YES && -d "$brspath" ]]; then
            if [[ ${envir} == prod ]]; then
                rm -rf $packagepathtodelete
         	echo "OLD PRODUCTION PACKAGE - $packagepathtodelete DELETED." >> $DATA/packagewarnings
            elif [[ ${envir} == para ]]; then
                echo "(${envir^^} TEST ONLY) $packagepathtodelete DELETED." >> $DATA/packagewarnings
            else
                echo "(${envir^^} TEST ONLY) $packagepathtodelete DELETED." >> $DATA/packagewarnings
            fi
	elif [[ ! -d "$brspath" && ${envir} == prod ]]; then
            echo "NO BRS BACKUP FOUND FOR $packagepathtodelete. SKIP..." >> $DATA/packagedeletions
	elif [[ ! -d "$brspath" && ${envir} == para ]]; then
            echo "NO BRS BACKUP FOUND FOR $packagepathtodelete. SKIP..." >> $DATA/packagewarnings
        else
            echo "WOULD HAVE DELETED $packagepathtodelete." >> $DATA/packagewarnings
        fi
    done
    if [[ $(grep -c . $DATA/packagedeletions) -gt 1 && ${envir} == prod ]]; then
        mail.py -s "$envir cleanup: package warnings ($jobid)" $MAILTO < $DATA/packagedeletions
    fi
    if [ $(grep -c . $DATA/packagewarnings) -gt 0 ]; then
    	set +x
        echo -ne "=================WARNINGS: PACKAGEROOT=$PACKAGEROOT envir=$envir PDY=$PDY PBS_JOBID=$PBS_JOBID: ==========================\n"
        cat $DATA/packagewarnings | sort -r
        echo -ne "==========================================================================================================================\n"
	set -x
    fi

    # Send deleted paths to ecFlow label
    ecflow_client --label cleanup_packages "$(cat $DATA/packagedeletions)" ${ECF_NAME} --port=${ECF_PORT}
else
    echo -ne "\n==========================================================================================================================\n"
    echo "Skipping package cleanup.  Cleanup runs on Mondays and when \$cleanup_packages is set to YES."
    echo -ne "==========================================================================================================================\n"
fi

postmsg "$jlogfile" "$0 has completed"
