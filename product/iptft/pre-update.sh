#! /bin/bash

printf "%s\n" "Pre-update script"

printf "%s" "Check /etc/hanover.conf ... "
if [ ! -f /etc/hanover.conf ] ; then
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/hanover.conf is not found!"
	exit $EXIT_FAIL_HANOVER_CONF
fi	
source /etc/hanover.conf
printf "%s\n" "Ok"

printf "%s" "Check /etc/update.conf ... "
if [ ! -f /etc/update.conf ] ; then
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/update.conf is not found!"
	exit $EXIT_FAIL_NO_UPDATE_CONF
fi
source /etc/update.conf
printf "%s\n" "Ok"

printf "%s\n" "Check the presence of /etc/pre-post-update.conf ... "
if [ ! -f /etc/pre-post-update.conf ] ; then
	printf "%s\n" "Faile"
	exit $EXIT_FAIL_NO_PRE_POST_CONF 
fi  
printf "%s\n" "Ok"
source /etc/pre-post-update.conf 

UPDATEVARS_CONF=/etc/updatevars.conf

if [ -f $UPDATEVARS_CONF ] ; then
	rm $UPDATEVARS_CONF
	touch $UPDATEVARS_CONF
fi

function cleanup_handler ()
{
	printf "%s\n" "Pre-update cleanup handler"	
	
	printf "%s" "Start tftmode.sh ... "
	/etc/init.d/tftmode.sh
	printf "%s\n" "Ok"
}
export -f cleanup_handler

# This is EXIT handler
function exit_handler () 
{
  	#Store exit value in the local variable
	_exit_status=$?
	
	case ${_exit_status} in
	
		$EXIT_SUCCESS)
		

		printf "%s" "Set result code and message  ... "
		result_flag=0
		exit_msg="EXIT: Success"
		echo ${result_flag} > $PRE_UPDATE_RESULT_FILE 
		echo ${exit_msg} > $PRE_UPDATE_RESULT_MSG
		printf "%s\n" "Done"

		;;
		
		EXIT_FAIL_NO_UPDATE_CONF   | \
		EXIT_FAIL_NO_HANOVER_CONF  | \
		EXIT_FAIL_NFS_MOUNT)
			echo "${_exit_status}" > $PRE_UPDATE_RESULT_FILE
			echo ${exit_msg} > $PRE_UPDATE_RESULT_MSG
			cleanup_handler
		;;
		
		*) 
			echo "${_exit_status}" > $PRE_UPDATE_RESULT_FILE
			echo ${exit_msg} > $PRE_UPDATE_RESULT_MSG
			cleanup_handler
	esac	
}
export -f exit_handler

#Declare exit handler
trap exit_handler EXIT

printf "%s" "Check the presence of /etc/update.conf ... "
if [ ! -f /etc/update.conf ] ; then
	printf "%s\n" "Failed"
	exit $EXIT_FAIL_NO_UPDATE_CONF
fi
printf "%s\n" "Ok" 
source /etc/update.conf


printf "%s\n" "Check the presence of /etc/hanover.conf ... "
if [ ! -f /etc/hanover.conf ] ; then
	printf "%s\n" "Failed"
	exit $EXIT_FAIL_NO_HANOVER_CONF 
fi
printf "%s\n" "Ok"	
source /etc/hanover.conf

	
printf "%s\n" "Preserving /usr/share/ChannelX configuration"
if [ -f "/usr/info/channel_*" ] ; then 
   	CHANNEL_X=`ls /usr/info/channel_*` > /dev/null
else
  	mkdir -p /usr/info > /dev/null
  	CHANNEL_X="/usr/info/channel_A"
fi
echo "CHANNEL_X=$CHANNEL_X" >> $UPDATEVARS_CONF

    
printf "%s\n" "Check the presence of /etc/tftmode.conf ... "
if [ -f /etc/tftmode.conf ] ; then
   	TFTMODE=`cat /etc/tftmode.conf`
else
   	#If this is first start after re-flashing we need to start ApplicationA
   	TFTMODE="0"
	"TFTMODE=$TFTMODE" 
	echo $TFTMODE > /etc/tftmode.conf
fi
printf "%s\n" "Ok"
echo "TFTMODE=$TFTMODE" >> $UPDATEVARS_CONF 
    
printf "Check /etc/hosts, add HT5 IP address if it's necessary ... "
grep ht5 /etc/hosts
if [ $? -ne 0 ] ; then
  	echo "192.168.9.2 ht5" >> /etc/hosts
fi
printf "%s\n" "Ok"

printf "%s\n" "Send SIGUSR1 signal to the applications indicating we need to run an update"
killall -s SIGUSR1 bootmonitor
killall -s SIGINT sdlrender
	    
printf "%s\n" "Kill mountnfs.sh, which maintains the automatic NFS mount" 
mountnfs_pid=`ps | grep bash | grep mountnfs`

mountnfs_pid=${mountnfs_pid:0:5}
printf "%s\n" "kill -s SIGKILL $mountnfs_pid"
kill -s SIGKILL $mountnfs_pid

printf "%s\n" "Unmount NFS folders"
umount ${updatedir} 

printf "%s\n" "Mount NFS again"
/etc/init.d/mountnfs.sh

nfs_mount_attempt_count=0	
while [ ! -d ${updatedir}/${BUILD_PURPOSE} ] ; do
	printf "%s\n" "Waiting for NFS mount..."
	
	if [ $nfs_mount_attempt_count -le 5 ] ; then
		let "nfs_mount_attempt_count ++"
		printf "%s\n" "nfs_mount_attempt_count = $nfs_mount_attempt_count"
		printf "%s\n" "Sleep for 3 seconds"
		sleep 3
		continue
	else
		printf "%s\n" "Something wrong with HTC, I can't mount NFS share."
		exit $EXIT_FAIL_NFS_MOUNT
			
	fi
done

printf "%s\n" "Pre-update script has successfully finished"
exit $EXIT_SUCCESS 