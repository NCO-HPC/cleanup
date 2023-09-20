#!/bin/bash
#  April 2021: Modified by Alex Richert. Adapting for WCOSS2.
#  This script is to be used to delete com subdirectories.
#  To execute the script execute the command
#    ./cleanup_rmdir.sh directory RUN KEEPTIME type
#  directory is the parent path to the RUN subdirectory to be cleaned,
#  KEEPTIME is the number to  days to keep which includes the current day.
#
#  This script will not delete directories containing either todays
#  date or some future date.

# Base path to com directory to delete (RUN will be appended)
directory=${1:?"The directory path is required to be provided as the first argument"}
if [ ! -d $directory ]; then
  echo "$directory not found. Skipping."
  exit
fi
# RUN
RUN=${2:?"RUN is required as the second argument"}
# Time to keep, with units (used by 'date' command)
KEEPTIME=${3:?"Time to keep (with units for 'date' command) is required to be provided as the third argument"}
# YMD for dated directory (gfs.YYYYMMDD), YMDH for dated with cyc (radar.YYYYMMDDHH),
# FIXED for undated directory (gifs), SUBYMD if RUN subdirectories are YMD dates only (YYYYMMDD),
# SUBYM is RUN subdirectories are year-month dates only (YYYYMM).
type=${4:?"Directory type? YMD, FIXED, SUBYMD, YMDH, or SUBYM for fourth argument"}
 
# Figure out what directories to delete:
deletethisdateandolder=$(date -d "$PDY -${KEEPTIME}" +%Y%m%d)
#echo "'date -d \"$PDY -${KEEPTIME}\" +%Y%m%d'"
if [ $? -ne 0 ]; then echo "date command with PDY '$PDY' and KEEPTIME '$KEEPTIME' failed"; exit 1; fi
#echo oldest: $deletethisdateandolder
if [ $type == YMD ]; then
  dirstodelete=($(ls -d $directory/$RUN.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] | awk "{if (\$1 <= \"$directory/$RUN.$deletethisdateandolder\") print}"))
elif [ $type == FIXED ]; then
  dirstodelete=($(find $directory/$RUN/* -not -newermt "$deletethisdateandolder ${cyc:-00}00"))
elif [ $type == SUBYMD ]; then
  dirstodelete=($(ls -d $directory/$RUN/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] | awk "{if (\$1 <= \"$directory/$RUN/$deletethisdateandolder\") print}"))
elif [ $type == YMDH ]; then
  deletethisdateandolder=$(date -d "$PDY ${cyc} -${KEEPTIME}" +%Y%m%d%H)
  dirstodelete=($(ls -d $directory/$RUN.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] | awk "{if (\$1 <= \"$directory/$RUN.$deletethisdateandolder\") print}"))
elif [ $type == YM ]; then
  deletethisdateandolder=${deletethisdateandolder::6}
  dirstodelete=($(ls -d $directory/$RUN.[0-9][0-9][0-9][0-9][0-9][0-9] | awk "{if (\$1 <= \"$directory/$RUN.$deletethisdateandolder\") print}"))
elif [ $type == SUBYM ]; then
  deletethisdateandolder=${deletethisdateandolder::6}
  dirstodelete=($(ls -d $directory/$RUN/[0-9][0-9][0-9][0-9][0-9][0-9] | awk "{if (\$1 <= \"$directory/$RUN/$deletethisdateandolder\") print}"))
fi
echo "deletethisdateandolder: $deletethisdateandolder"

# DO THE DELETION:
if [[ $SENDCOM == YES && ${#dirstodelete[@]} -gt 0 ]] ; then
  set -x
  rm -rf ${dirstodelete[@]}
  set +x
elif [ $SENDCOM == YES ]; then
  echo "Nothing to delete."
elif [ ${#dirstodelete[@]} -gt 0 ]; then
  echo "SENDCOM!=YES. The following directories and their contents would have been deleted: ${dirstodelete[@]}"
else
  echo "Nothing would have been deleted under $directory for RUN=$RUN"
fi
