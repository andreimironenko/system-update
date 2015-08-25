#! /bin/bash

printf "%s\n" "Post-update script"

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
	exit $EXIT_FAIL_UPDATE_CONF 
fi
source /etc/update.conf
printf "%s\n" "Ok"

printf "%s" "Check /etc/pre-post-update.conf ... "
if [ ! -f /etc/pre-post-update.conf ] ; then 
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/pre-post-update.conf is not found!"
	exit $EXIT_FAIL_NO_PRE_POST_CONF
fi
source /etc/pre-post-update.conf
printf "%s\n" "Ok"


function cleanup_handler ()
{
	 printf "%s\n" "Post-update cleanup handler"	
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
		echo ${result_flag} > $POST_UPDATE_RESULT_FILE 
		echo ${exit_msg} > $POST_UPDATE_RESULT_MSG
		printf "%s\n" "Done"

		cleanup_handler
		;;
	
		EXIT_FAIL_NO_UPDATE_CONF   | \
		EXIT_FAIL_NO_HANOVER_CONF  | \
		EXIT_FAIL_NFS_MOUNT)
			echo "${_exit_status}" > $POST_UPDATE_RESULT_FILE
			echo ${exit_msg} > $POST_UPDATE_RESULT_MSG
			cleanup_handler
		;;
		
		*) 
			echo "${_exit_status}" > $POST_UPDATE_RESULT_FILE
			echo ${exit_msg} > $POST_UPDATE_RESULT_MSG
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

printf "%s" "Check the presence of /etc/hanover.conf ... "
if [ ! -f /etc/hanover.conf ] ; then
	printf "%s\n" "Failed"
	exit $EXIT_FAIL_NO_HANOVER_CONF 
fi
printf "%s\n" "Ok"	
source /etc/hanover.conf

printf "%s" "Restoring /etc/tftmode.conf ... "
if [ -z $TFTMODE ] ; then
	TFTMODE="0"
fi
echo "$TFTMODE" > /etc/tftmode.conf
printf "%s\n" "Ok"

printf "%s" "Restoring $CHANNEL_X ... "
touch $CHANNEL_X
printf "%s\n" "Ok"

printf "%s" "Starting IPTFT applications ... "
execute /etc/init.d/tftmode.sh
printf "%s\n" "Ok"

printf "%s" "Removing temproary file $UPDATEVARS_CONF ... "
rm $UPDATEVARS_CONF
printf "%s\n" "Ok" 

printf "%s\n" "Post-update script has successfully finished"
exit $EXIT_SUCCESS 