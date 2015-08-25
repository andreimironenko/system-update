#! /bin/bash

printf "%s" "Check /etc/update.conf ... "
if [ ! -f /etc/update.conf ] ; then
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/update.conf is not found!"
	exit $EXIT_FAIL_UPDATE_CONF 
fi
source /etc/update.conf
printf "%s\n" "Ok"

printf "%s" "Check /etc/hanover.conf ... "
if [ ! -f /etc/hanover.conf ] ; then
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/hanover.conf is not found!"
	exit $EXIT_FAIL_HANOVER_CONF
fi	
source /etc/hanover.conf
printf "%s\n" "Ok"

printf "%s" "Check /etc/pre-post-update.conf ... "
if [ ! -f /etc/pre-post-update.conf ] ; then 
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/pre-post-update.conf is not found!"
	exit $EXIT_FAIL_PRE_POST_CONF
fi
source /etc/pre-post-update.conf
printf "%s\n" "Ok"

printf "%s" "Check /etc/pre-update.sh results ... "
if [ ! -f $logdir/pre.update.result.flag ] ; then
	printf "%s\n" "Failed"
	printf "%s\n" "The log file $logdir/pre.update.resulst.flag is not found!"
	exit $EXIT_FAIL_PRE_UPDATE_FLAG_NOT_FOUND
fi	

pre_update_flag=`cat $logdir/pre.update.result.flag`
pre_update_msg=`cat $logdir/pre.update.result.msg`

if [ $pre_update_flag -ne "0" ] ; then
	printf "%s\n" "Failed"
	printf "%s\n" "pre-update.sh has failed, returning $pre_update_flag and message:"
	printf "%s\n" "$pre_update_msg" 
	exit $EXIT_FAIL_PRE_UPDATE_FAILED 
fi 
printf "%s\n" "Ok"

# Cleanup handler
function cleanup_handler () 
{
printf "%s\n" " "	
printf "%s\n" "Transferring log files: "	| tee -a $LOGFILE
executeL pushd $PWD
executeL cd ${logdir}
log_files=( $( ls -1 ) )
for (( f=0; f<${#log_files[*]} ; f++ )) ; do
	printf "%s" "Transferring ${log_files[$f]} ... " | tee -a $LOGFILE
	ftp_uploadL ${log_files[$f]} ${ftp_logs_dir}
	printf "%s\n" "Ok" | tee -a $LOGFILE
done
executeL popd

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
	
		$EXIT_FAIL_INVALID_PARAMETERS)
		;;
			
		EXIT_FAIL_UPDATE_CONF					| \
		EXIT_FAIL_HANOVER_CONF					| \
		EXIT_FAIL_OBCSAE_FTP_TRANSFER			| \
		EXIT_FAIL_PRE_POST_CONF					| \
		EXIT_FAIL_IPTFT_MD5_MISMATCH			| \
		EXIT_FAIL_IPTFT_FTP_DOWNLOAD			| \
		EXIT_FAIL_IPLED_MD5_MISMATCH            | \
		EXIT_FAIL_IPLED_FTP_DOWNLOAD            | \
		EXIT_FAIL_IPLED_DIR_NOT_FOUND)
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

printf "%s\n" "Check ${ftp_obc_dir}/${updating_stib_flag}"
ftp_download ${ftp_obc_dir}/${updating_stib_flag}
stib_flag=$?
	
printf "%s\n" "Check ${ftp_obc_dir}/${updating_iptft_flag}"
ftp_download ${ftp_obc_dir}/${updating_iptft_flag}
iptft_flag=$?

printf "%s\n" "Check ${ftp_obc_dir}/${updating_ipled_flag}"
ftp_download ${ftp_obc_dir}/${updating_ipled_flag}
ipled_flag=$?

if [ $stib_flag = "0" ] ; then
	
	#Setting up updated_ip_led flag
	executeL pushd $PWD
	executeL cd ${tmpdir}
	executeL touch ${updated_stib_flag}
	printf "%s" "Setting up ${updated_stib_flag} flag on OBC-SAE ... " | tee -a $LOGFILE
	ftp_uploadL ./${updated_stib_flag} ${ftp_obc_dir}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	executeL popd	
	
	printf "%s" "Removing ${updating_stib_flag} ... "  | tee -a $LOGFILE
	ftp_deleteL ${ftp_obc_dir}/${updating_stib_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE


fi #STIB update final steps 

		
if [ $iptft_flag = "0" ] ; then
	
printf "%s" "Restart NFS server ... " | tee -a $LOGFILE
execute /etc/init.d/nfsserver stop
sleep 1
execute /etc/init.d/nfsserver start
printf "%s\n" "Ok" | tee -a $LOGFILE

for (( index=0; index<${#IP_ADDR[*]}; index ++)) ; do
	printf "%s\n" "Restart mountnfs.sh in ${IP_ADDR[$index]} " | tee -a $LOGFILE
	input=( $(ssh -y -i ${db_rsa_key} root@${IP_ADDR[$index]} ps | grep bash | grep mountnfs) ) &> /dev/null
	ssh -y -i ${db_rsa_key} root@${IP_ADDR[$index]} kill ${input[0]} &> /dev/null
	ssh -y -i ${db_rsa_key} root@${IP_ADDR[$index]} /etc/init.d/mountnfs.sh &> /dev/null
done

printf "%s\n" "Checking IPTFTs presence on the network" | tee -a $LOGFILE
alive_index=0
for (( index=0; index<${#IP_ADDR[*]}; index ++)) ; do
	
	ping -w 1 ${IP_ADDR[$index]} > /dev/null
	RESULT=$?
	
	if [ $RESULT -ne 0 ] ; then
		printf "%s\n" "Host ${IP_ADDR[$index]} is not alive" | tee -a $LOGFILE
		printf "%s\n" "Skipping update for host ${IP_ADDR[$index]}!" | tee -a $LOGFILE
		continue
	else
		ALIVE_IP[$alive_index]=${IP_ADDR[$index]}
		let "alive_index ++"
		printf "%s\n" "${IP_ADDR[$index]} is alive, start update procedure" | tee -a $LOGFILE
		
		printf "%s" "Force to rename update.scr to disable.update.scr ... " | tee -a $LOGFILE
		ssh -y -i ${db_rsa_key} root@${IP_ADDR[$index]} mv /boot/update.scr /boot/disable.update.scr &> /dev/null
		printf "%s\n" "Done" | tee -a $LOGFILE
		
		printf "%s" "Force to remove /etc/rc5.d/S99update symlink ... " | tee -a $LOGFILE
		ssh -y -i ${db_rsa_key} root@${IP_ADDR[$index]} rm /etc/rc5.d/S99update &> /dev/null
		printf "%s\n" "Done" | tee -a $LOGFILE
	
		#TODO: Quick hack! It needs to be removed soon 		
		printf "%s" "Copying tftmode.conf and channelX config files  ... " | tee -a $LOGFILE
		scp -i ${db_rsa_key} root@${IP_ADDR[$index]}:/etc/tftmode.conf ${tmpdir}/${IP_ADDR[$index]}.tftmode.conf
		scp -i ${db_rsa_key} root@${IP_ADDR[$index]}:/usr/info/channel_A ${tmpdir}/${IP_ADDR[$index]}.channel_A 
		printf "%s\n" "Done" | tee -a $LOGFILE

		printf "%s" "Start software update ${IP_ADDR[$index]} ... " | tee -a $LOGFILE
		(ssh -y -i ${db_rsa_key} root@${IP_ADDR[$index]} /etc/init.d/update.sh -s &> /dev/null) &> /dev/null &
		printf "%s\n" "Done" | tee -a $LOGFILE
		
	fi
done

#Wait untill all background jobs are completed!
wait

printf "%s\n" "Sleep for the next 5 seconds to let IPTFTs initialize reboot" | tee -a $LOGFILE
sleep 5

################################################################################
# Now let's check the result of the IPTFTs update                              #
################################################################################
ready_flag=1
ready_count=0
ready_count_sleep=15
MAX_READY_COUNT=24

	
while [ true ] ; do
	
	ready_flag=1

	for (( index=0; index<${#ALIVE_IP[$index]}; index ++ )) ; do
		file_presence=""
		file_presence=`ssh -y -i ${db_rsa_key} root@${ALIVE_IP[$index]} ls -1 $IPTFT_UPDATE_READY_FILE` &> /dev/null
		printf "%s\n" "UPDATE_READY_FILE=$IPTFT_UPDATE_READY_FILE"
		printf "%s\n" "file_presence=$file_presence"
		printf "%s\n" "ALIVE_IP[$index]=${ALIVE_IP[$index]}"
		
		if [ ! -z $file_presence ] ; then
			let "ready_flag &= 1"
			printf "%s\n" "${ALIVE_IP[$index]} is ready" | tee -a $LOGFILE
			
			if [   "${ALIVE_IP[$index]}" == "192.168.9.10" ] ; then
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_LOGFILE} ${LOGDIR}/update.tft.double.log > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_UPDATE_RESULT_FILE} ${LOGDIR}/update.result.tft.double.flag > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_UPDATE_RESULT_MSG} ${LOGDIR}/update.result.tft.double.msg > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_PRE_UPDATE_RESULT_FILE} ${LOGDIR}/pre.update.result.tft.double.flag > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_PRE_UPDATE_RESULT_MSG} ${LOGDIR}/pre.update.result.tft.double.msg > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_POST_UPDATE_RESULT_FILE} ${LOGDIR}/post.update.result.tft.double.flag > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_POST_UPDATE_RESULT_MSG} ${LOGDIR}/post.update.result.tft.double.msg > /dev/null 
			else
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_LOGFILE} ${LOGDIR}/update.tft.single.log > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_UPDATE_RESULT_FILE} ${LOGDIR}/update.result.tft.single.flag > /dev/null 
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_UPDATE_RESULT_MSG} ${LOGDIR}/update.result.tft.single.msg > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_PRE_UPDATE_RESULT_FILE} ${LOGDIR}/pre.update.result.tft.single.flag > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_PRE_UPDATE_RESULT_MSG} ${LOGDIR}/pre.update.result.tft.single.msg > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_POST_UPDATE_RESULT_FILE} ${LOGDIR}/post.update.result.tft.single.flag > /dev/null
				scp -i ${db_rsa_key} root@${ALIVE_IP[$index]}:${IPTFT_POST_UPDATE_RESULT_MSG} ${LOGDIR}/post.update.result.tft.single.msg > /dev/null 

			fi
		else
			let "ready_flag &= 0"
			printf "%s\n" "${ALIVE_IP[$index]} is not ready" | tee -a $LOGFILE
		fi
	done
	
	printf "%s\n" "Ready flag value = $ready_flag" | tee -a $LOGFILE
	
	if [ "$ready_flag" -eq 1 ] ; then
		printf "%s" "Removing ${updating_iptft_flag} ... "  | tee -a $LOGFILE
		ftp_deleteL ${ftp_obc_dir}/${updating_iptft_flag}
		printf "%s\n" "Ok" | tee -a $LOGFILE
		
		executeL pushd $PWD
		executeL cd ${tmpdir} 
		executeL touch ${updated_iptft_flag}
		printf "%s" "Setting up ${updated_iptft_flag} flag on OBC-SAE ... " | tee -a $LOGFILE
		ftp_uploadL ./${updated_iptft_flag} ${ftp_obc_dir}
		printf "%s\n" "Ok" | tee -a $LOGFILE

		
		printf "%s\n"
		printf "%s\n" "All TFTs have been upgraded successfully. Check log files for further details" | tee -a $LOGFILE
		break;
		
	elif [ "$ready_count" -ge "$MAX_READY_COUNT" ] ; then
		printf "%s\n" "Error: Max. time-out reached, some of IPTFTs were not updated" | tee -a $LOGFILE
		break;
	else
		ready_count=$(( ready_count + 1 ))
		sleep ${ready_count_sleep}
		printf "%s\n" "Sleep ${ready_count_sleep} seconds waiting ready status from TFTs" | tee -a $LOGFILE
		continue;
	fi
 done

	#TODO: Quick hack, needs to be removed!	
 for (( index=0; index<${#ALIVE_IP[$index]}; index ++ )) ; do
	printf "%s\n" "Copy tftmode.conf and channelA files to ${ALIVE_IP[$index]}"
	echo 1 >  ${tmpdir}/${ALIVE_IP[$index]}.tftmode.conf
	scp -i ${db_rsa_key} ${tmpdir}/${ALIVE_IP[$index]}.tftmode.conf root@${ALIVE_IP[$index]}:/etc/tftmode.conf > /dev/null 
	scp -i ${db_rsa_key} ${tmpdir}/${ALIVE_IP[$index]}.channel_A root@${ALIVE_IP[$index]}:/usr/info/channel_A > /dev/null 
 done

fi #End of IPTFTs update

################################################################################
# IPLEDs update procedure                                                      #
################################################################################
if [ $ipled_flag = "0" ] ; then

	printf "%s\n" "" | tee -a $LOGFILE
	printf "%s" "Check the presence of ${updatedir}/${ftp_ipled_dir} ... " | tee -a $LOGFILE
	if [ ! -d  ${updatedir}/${ftp_ipled_dir} ] ; then
		exit_msg="The ${updatedir}/${ftp_ipled_dir} is not found!"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_IPLED_DIR_NOT_FOUND
	fi 
	printf "%s\n" "Ok" | tee -a $LOGFILE 

	printf "%s\n" "List IPLEDs firmware binaries:" | tee -a $LOGFILE
	executeL pushd $PWD
	executeL cd ${updatedir}/${ftp_ipled_dir}
	ipled_list=( $( ls -1 ) )
	
	if [ -z ${ipled_list[0]} ] ; then
		printf "%s\n" "No IPLEDs firmware binaries were found!" | tee -a $LOGFILE
		exit $EXIT_SUCCESS
	fi 
	
	for (( f=0 ; f < ${#ipled_list[*]} ; f++ )) ; do
		printf "%s\n" "${ipled_list[$f]}" | tee -a $LOGFILE
	done 
	
	printf "%s\n" "The latest available release: ${ipled_list[${#ipled_list[*]} - 1]}" | tee -a $LOGFILE
	
	ping -w 1 ${ipled_addr[$ipled_front_id]} > /dev/null
	if [ $? = "0" ] ; then
		printf "%s\n" "Start updating job for FRONT ipled" | tee -a $LOGFILE
		( firmloader --eth=${ipled_addr[$ipled_front_id]}:2101 ${ipled_list[${#ipled_list[*]} - 1]} > ${LOGDIR}/update.sign.front.log && echo $? > ${LOGDIR}/update.sign.front.flag ) &
	else
		printf "%s\n" "Front IPLED is not connected!" | tee -a $LOGFILE
		printf "%s\n" "Skip it" | tee -a $LOGFILE
	fi
	
	ping -w 1 ${ipled_addr[$ipled_side_id]} > /dev/null
	if [ $? = "0" ] ; then
		printf "%s\n" "Start updating job for SIDE ipled" | tee -a $LOGFILE
		( firmloader --eth=${ipled_addr[$ipled_side_id]}:2101 ${ipled_list[${#ipled_list[*]} - 1]} > ${LOGDIR}/update.sign.side.log && echo $? > ${LOGDIR}/update.sign.side.flag ) & 
	else
		printf "%s\n" "Side IPLED is not connected!" | tee -a $LOGFILE
		printf "%s\n" "Skip it" | tee -a $LOGFILE
	fi
	
	ping -w 1 ${ipled_addr[$ipled_rear_id]} > /dev/null
	if [ $? = "0" ] ; then
		printf "%s\n" "Start updating job for REAR ipled" | tee -a $LOGFILE
		( firmloader --eth=${ipled_addr[$ipled_rear_id]}:2101 ${ipled_list[${#ipled_list[*]} - 1]} > ${LOGDIR}/update.sign.rear.log && echo $? > ${LOGDIR}/update.sign.rear.flag ) & 
	else
		printf "%s\n" "Rear IPLED is not connected!" | tee -a $LOGFILE
		printf "%s\n" "Skip it"	| tee -a $LOGFILE
	fi
	
	printf "%s" "Waiting IPLEDs to complete ... "
	wait 
	printf "%s\n" "Done"
	executeL popd

	#Setting up updated_ip_led flag
	executeL pushd $PWD
	executeL cd ${tmpdir}
	executeL touch ${updated_ipled_flag}
	printf "%s" "Setting up ${updated_ipled_flag} flag on OBC-SAE ... " | tee -a $LOGFILE
	ftp_uploadL ./${updated_ipled_flag} ${ftp_obc_dir}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	executeL popd
		
	#Removing updating_ip_led flag
	printf "%s" "Removing ${updating_ipled_flag} ... "  | tee -a $LOGFILE
	ftp_deleteL ${ftp_obc_dir}/${updating_ipled_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE

	

fi #End of IPLEDs update 


exit $EXIT_SUCCESS
