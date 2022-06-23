#!/bin/ksh
###################################################################
# "------------------------------------------------"
# "J101 - " 
# "------------------------------------------------"
# "History: OCT 1996 - First implementation of this new script."
# "History: FEB 1998 - Dropped /com/ncepdate (2-digit year)"
# "                    from utility zdate.sh"
# "History: MAR 1999 - Adapted for running on CLASS-VIII IBM"
# "         FEB 2001 - Split from the ex100.sh.sms script"
# "         OCT 2004 - Renamed ex101.sh.sms to exprod_cleanup.sh.sms"
# "         DEC 2011 - Add cleanup of /com/output/transfer"
# "         DEC 2011 - Modify cleanup of /tmpnwprd1 and add "
# "                    recursive flag to correct rm of "
# "                    /nwges/wsr subdirectories"
#####################################################################

set -x
postmsg "$jlogfile" "$0 has begun"

if test "$cleanup_com" = "YES"
then
   grep -v "#" $PARMcleanup/cleanup_rm_rzdm | sed "s/ //g" > tmp_clean
   for clean_list in `cat tmp_clean`
   do
      if echo $clean_list |grep -q nco_mag
        #MAG CLEANUP
      then
        NET=""
        directory=`echo $clean_list | awk -F"|" '{print "/home/www/"$1"/"$2""}'`
        prod_keep00=`echo $clean_list | awk -F"|" '{print $3}'`
        prod_keep12=`echo $clean_list | awk -F"|" '{print $4}'`
        para_keep00=`echo $clean_list | awk -F"|" '{print $5}'`
        para_keep12=`echo $clean_list | awk -F"|" '{print $6}'`
        eval_keep00=`echo $clean_list | awk -F"|" '{print $7}'`
        eval_keep12=`echo $clean_list | awk -F"|" '{print $8}'`
        if [ ${cleanup_com:?} == YES ]; then
           com=`eval echo ${directory/\${envir}/${clean_envir}}`
           keep=`eval echo "$"${clean_envir}_keep${cyc}`
           
           for site in $SITELIST
           do
           let numattempts=3
           while [ $numattempts -gt 0 ]; do
             date
             timeout ${MAXTIME} ssh nwprod@${site}  "date; hostname; export PDYp1=$PDYp1 cyc=$cyc;  /home/people/nco/nwprod/bin/cleanup_rmdir_rzdm.sh $PDY $com $keep $cyc 2>&1"
             err=$?
             if [ $err -eq 124 ]; then
               ((numattempts--))
               sleep 5
             else
               let numattempts=-1  # successful completion on ssh
             fi
           done # for numattempts loop
           if [ $numattempts -eq 0 ]; then
             echo "FATAL ERROR: ssh failed after three attempts"
             err_exit
           fi
           done # for site loop
        fi
      elif echo $clean_list| grep -q hysplit
        #HYSPLIT CLEANUP
      then
        NET=""
        directory=`echo $clean_list | awk -F"|" '{print "/home/www/"$1"/"$2""}'`
        prod_keep00=`echo $clean_list | awk -F"|" '{print $3}'`
        prod_keep12=`echo $clean_list | awk -F"|" '{print $4}'`
        para_keep00=`echo $clean_list | awk -F"|" '{print $5}'`
        para_keep12=`echo $clean_list | awk -F"|" '{print $6}'`
        test_keep00=`echo $clean_list | awk -F"|" '{print $7}'`
        test_keep12=`echo $clean_list | awk -F"|" '{print $8}'`
        sdm_keep00=`echo $clean_list | awk -F"|" '{print $9}'`
        sdm_keep12=`echo $clean_list | awk -F"|" '{print $10}'`
        if [ ${cleanup_com:?} == YES ]; then
           com=`eval echo ${directory/\${envir}/${clean_envir}}`
           keep=`eval echo "$"${clean_envir}_keep${cyc}`
           if test `eval echo $clean_envir` = "prod" -o `eval echo $clean_envir` = "para"
           then
           NET=`echo $clean_list | awk -F"|" '{print $1}'`
             for site in $SITELIST
             do
               let numattempts=3
               while [ $numattempts -gt 0 ]; do
                 date
                 timeout ${MAXTIME} ssh nwprod@${site}  "date; hostname; export PDYp1=$PDYp1 cyc=$cyc;  /home/people/nco/nwprod/bin/cleanup_rmdir_rzdm.sh $PDY ${com/prod/} $keep $cyc $NET 2>&1"
                 err=$?
                 if [ $err -eq 124 ]; then
                   ((numattempts--))
                   sleep 5
                 else
                   let numattempts=-1  # successful completion on ssh
                 fi
               done # for numattempts loop
               if [ $numattempts -eq 0 ]; then
                 echo "FATAL ERROR: ssh failed after three attempts"
                 err_exit
               fi
             done # for site loop
           else
             for site in $SITELIST
             do
               let numattempts=3
               while [ $numattempts -gt 0 ]; do
                 date
                 timeout ${MAXTIME} ssh nwprod@${site}  "date; hostname; export PDYp1=$PDYp1 cyc=$cyc;  /home/people/nco/nwprod/bin/cleanup_rmdir_rzdm.sh $PDY ${com/prod/} $keep $cyc 2>&1"
                 err=$?
                 if [ $err -eq 124 ];  then
                   ((numattempts--))
                   sleep 5
                 else
                   let numattempts=-1  # successful completion on ssh
                 fi
               done # for numattempts loop
               if [ $numattempts -eq 0 ]; then
                 echo "FATAL ERROR: ssh failed after three attempts"
                 err_exit
               fi
             done # for site loop
           fi
        fi
      else
        echo "NET/runid not set "
        exit 1
      fi

   done
fi

postmsg "$jlogfile" "$0 completed normally"
