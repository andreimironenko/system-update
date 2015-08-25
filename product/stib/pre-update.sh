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
	exit $EXIT_FAIL_UPDATE_CONF 
fi
source /etc/update.conf
printf "%s\n" "Ok"

printf "%s" "Check /etc/pre-post-update.conf ... "
if [ ! -f /etc/pre-post-update.conf ] ; then 
	printf "%s\n" "Failed"
	printf "%s\n" "/etc/pre-post-update.conf is not found!"
	exit 195 
fi
source /etc/pre-post-update.conf
printf "%s\n" "Ok"

# Cleanup handler
function cleanup_handler () 
{
	printf "%s\n" "pre-update cleanup_handler is called"
}
export -f cleanup_handler

# This is EXIT handler
function exit_handler () 
{
  	#Store exit value in the local variable
	_exit_status=$?
	
	case ${_exit_status} in
	
		$EXIT_SUCCESS)
		
		# Clean up temp.files	
		cleanup_handler
	
		printf "%s" "Set result code and message  ... "
		result_flag=0
		exit_msg="EXIT: Success"
		echo ${result_flag} > $PRE_UPDATE_RESULT_FILE 
		echo ${exit_msg} > $PRE_UPDATE_RESULT_MSG
		printf "%s\n" "Done"
	
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

printf "%s" "Check $updatedir, create if it does not exist ... " 
if [ ! -d $updatedir ] ; then
	executeL mkdir -p $updatedir 
fi
printf "%s\n" "Ok"

printf "%s" "Check $tmpdir, create if it does not exist ... " 
if [ ! -d $tmpdir ] ; then 
	executeL mkdir -p $tmpdir 
fi
printf "%s\n" "Ok"

printf "%s" "Check $logdir, create if it does not exist ... " 
if [ ! -d $logdir ] ; then
	executeL mkdir -p $logdir
fi
printf "%s\n" "Ok"

printf "%s" "Check $LOGFILE, create if it does not exist ... "
if [ ! -f $LOGFIL ] ; then 
	executeL touch $LOGFILE
fi
printf "%s\n" "Ok"

printf "%s" "Killing STIBApp and python processes ... "
killall -s SIGUSR1 ${stib_app_exe}
killall python
printf "%s\n" "Ok"

printf "%s" "Reset .ssh/known_hosts ... "
echo "" > /home/root/.ssh/known_hosts
printf "%s\n" "Ok"

if [ ! -d  ${updatedir}/${ftp_obc_dir} ] ; then
	executeL mkdir -p ${updatedir}/${ftp_obc_dir}
fi

printf "%s\n" "Check ${ftp_obc_dir}/${ready_stib_flag}"
ftp_download ${ftp_obc_dir}/${ready_stib_flag}
stib_flag=$?
	
printf "%s\n" "Check ${ftp_obc_dir}/${ready_iptft_flag}"
ftp_download ${ftp_obc_dir}/${ready_iptft_flag}
iptft_flag=$?

printf "%s\n" "Check ${ftp_obc_dir}/${ready_ipled_flag}"
ftp_download ${ftp_obc_dir}/${ready_ipled_flag}
ipled_flag=$?
	
printf "%s\n" "stib_flag=$stib_flag"
printf "%s\n" "iptft_flag=$iptft_flag"
printf "%s\n" "ipled_flag=$ipled_flag"


if [ $stib_flag = "0" ] ; then
	printf "%s\n" "Start downloading STIB updates" | tee -a $LOGFILE
	executeL pushd $PWD
	executeL cd ${tmpdir}
	executeL touch ${updating_stib_flag}
	
	printf "%s" "Getting installed STIB releases ... " | tee -a $LOGFILE
	installed_stib_releases=( $( ls -1 ${updatedir}/${ftp_stib_dir}/${BUILD_PURPOSE} ) )
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" "installed_stib_releases: ${installed_stib_releases[*]}"
	
	printf "%s" "Setting up ${updating_stib_flag} flag on OBC-SAE ... " | tee -a $LOGFILE
	ftp_uploadL ./${updating_stib_flag} ${ftp_obc_dir}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	executeL popd
	
	printf "%s" "Removing ${ready_stib_flag} ... "  | tee -a $LOGFILE
	ftp_deleteL ${ftp_obc_dir}/${ready_stib_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s" "Removing ${updated_stib_flag} ... "  | tee -a $LOGFILE
	ftp_delete ${ftp_obc_dir}/${updated_stib_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" "" | tee -a $LOGFILE
	printf "%s\n" "List remote files under ${ftp_stib_dir}: " | tee -a $LOGFILE
	stib_list=( $( curl -s -u ${ftp_user}:${ftp_pswd} --list-only ftp://${obcsae_ip_addr}/${ftp_stib_dir}/ ) )
	for (( i=0; i<${#stib_list[*]}; i++ )) ; do 
		_file=`basename ${stib_list[$i]}` 
		printf "%s\n" "${_file}" | tee -a $LOGFILE
	done
	printf "%s\n" "" | tee -a $LOGFILE

	printf "%s" "Building up available STIB releases ... "  | tee -a $LOGFILE
	for (( i=0; i<${#stib_list[*]}; i++ )) ; do 
		ftp_stib_releases[$i]=${stib_list[$i]%*.tar.bz2}
		ftp_stib_releases[$i]=${ftp_stib_releases[$i]%.*}
	done
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" ""
	printf "%s\n" "Available STIB releases on FTP server: "
	printf "%s\n" "${ftp_stib_releases[@]}"
	printf "%s\n" ""
	
	d=0
	
	for (( i=0; i < ${#ftp_stib_releases[*]}; i++ )) ; do
		status=0
		for (( j=0; j < ${#installed_stib_releases[*]}; j++ )) ; do
		
			if [ "${ftp_stib_releases[$i]}" == "${installed_stib_releases[$j]}" ] ; then
				status=$(( status | 1 ))
 			fi 
		done
		
		if [ $status -eq 0 ] ; then
			stib_delta_list[$d]=${stib_list[$i]}
			d=$(( d + 1 ))
		fi  
	done

	printf "%s\n" ""	
	printf "%s\n" "New STIB releases available on FTP server: "
	printf "%s\n" "${stib_delta_list[@]}"	
	printf "%s\n" ""	

	printf "%s" "Check ${updatedir}/${ftp_stib_dir}/${BUILD_PURPOSE} ... " | tee -a $LOGFILE
	if [ ! -d ${updatedir}/${ftp_stib_dir}/${BUILD_PURPOSE} ] ; then
		mkdir -p ${updatedir}/${ftp_stib_dir}/${BUILD_PURPOSE} 
	fi
	printf "%s\n" "Ok" | tee -a $LOGFILE

	printf "%s\n" "" | tee -a $LOGFILE
	printf "%s\n" "Download, check MD5 and untar STIB files:" | tee -a $LOGFILE
	executeL pushd $PWD
	executeL cd ${updatedir}/${ftp_stib_dir}/${BUILD_PURPOSE}
 
	#Download the files and check MD5 checksum
	#for ((i=0 ; i<${#stib_list[*]}; i++ )) ; do
	for ((i=0 ; i<${#stib_delta_list[*]}; i++ )) ; do
		_file=`basename ${stib_delta_list[$i]}`
		printf "%s" "${_file} ... " | tee -a $LOGFILE

		ftp_download ${ftp_stib_dir}/${stib_delta_list[$i]} 
		if [ $? -ne "0" ] ; then
			exit_msg="EXIT: FTP file ${ftp_stib_dir}/${stib_delta_list[$i]} download has failed"
			echo $exit_msg | tee -a $LOGFILE 
			exit $EXIT_FAIL_STIB_FTP_DOWNLOAD
		fi
	
		#Calculate MD5 
		_md5=`md5sum ${_file}`
		_md5=${_md5:0:32}
	
		# Get MD5 value from the file name, example:
		# iptft.r01-rc02.3a679927f36d57c62f17b492196be45a.tar.bz2		
		_md5_orig=${_file#*.}
		_md5_orig=${_md5_orig#*.}
		_md5_orig=${_md5_orig%*.tar.bz2}
	
		# Compare calculated MD5 with the original one
		if [ "${_md5}" != "${_md5_orig}" ] ; then
			exit_msg="EXIT: MD5 mismatch for ${_file}, expected ${_md5_orig} got ${_md5}"
			echo $exit_msg | tee -a $LOGFILE
			exit $EXIT_FAIL_STIB_MD5_MISMATCH   	
		fi

		# Utaring ...	
		executeL tar xvjf ${_file}
		# Removing tar.ball
		executeL rm ${_file}
		printf "%s\n" "Ok" | tee -a $LOGFILE
	done

fi # End of STIB update


if [ $iptft_flag = "0" ] ; then
	printf "%s\n" "Start downloading IPTFT updates" | tee -a $LOGFILE
	executeL pushd $PWD
	executeL cd ${tmpdir}
	executeL touch ${updating_iptft_flag}
	
	printf "%s" "Getting installed IPTFT releases ... " | tee -a $LOGFILE
	installed_iptft_releases=( $( ls -1 ${updatedir}/${ftp_iptft_dir}/${BUILD_PURPOSE} ) )
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s" "Setting up ${updating_iptft_flag} flag on OBC-SAE ... " | tee -a $LOGFILE
	ftp_uploadL ./${updating_iptft_flag} ${ftp_obc_dir}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	executeL popd
	
	printf "%s" "Removing ${ready_iptft_flag} ... "  | tee -a $LOGFILE
	ftp_deleteL ${ftp_obc_dir}/${ready_iptft_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s" "Removing ${updated_iptft_flag} ... "  | tee -a $LOGFILE
	ftp_delete ${ftp_obc_dir}/${updated_iptft_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" "" | tee -a $LOGFILE
	printf "%s\n" "List remote files under ${ftp_iptft_dir}: " | tee -a $LOGFILE
	iptft_list=( $( curl -s -u ${ftp_user}:${ftp_pswd} --list-only ftp://${obcsae_ip_addr}/${ftp_iptft_dir}/ ) )
	for (( i=0; i<${#iptft_list[*]}; i++ )) ; do 
		_file=`basename ${iptft_list[$i]}` 
		printf "%s\n" "${_file}" | tee -a $LOGFILE
	done
	printf "%s\n" "" | tee -a $LOGFILE
	
	printf "%s" "Building up available IPTFT releases ... "  | tee -a $LOGFILE
	for (( i=0; i<${#iptft_list[*]}; i++ )) ; do 
		ftp_iptft_releases[$i]=${iptft_list[$i]%*.tar.bz2}
		ftp_iptft_releases[$i]=${ftp_iptft_releases[$i]%.*}
	done
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" ""
	printf "%s\n" "Available IPTFT releases on FTP server: "
	printf "%s\n" "${iptft_stib_releases[@]}"
	printf "%s\n" ""
	
	d=0
	
	for (( i=0; i < ${#ftp_iptft_releases[*]}; i++ )) ; do
		status=0
		for (( j=0; j < ${#installed_iptft_releases[*]}; j++ )) ; do
		
			if [ "${ftp_iptft_releases[$i]}" == "${installed_iptft_releases[$j]}" ] ; then
				status=$(( status | 1 ))
 			fi 
		done
		
		if [ $status -eq 0 ] ; then
			iptft_delta_list[$d]=${iptft_list[$i]}
			d=$(( d + 1 ))
		fi  
	done

	printf "%s\n" ""	
	printf "%s\n" "New IPTFT releases available on FTP server: "
	printf "%s\n" "${iptft_delta_list[@]}"	
	printf "%s\n" ""	

	printf "%s" "Check ${updatedir}/${ftp_iptft_dir}/${BUILD_PURPOSE} ... " | tee -a $LOGFILE
	if [ ! -d ${updatedir}/${ftp_iptft_dir}/${BUILD_PURPOSE} ] ; then
		mkdir -p ${updatedir}/${ftp_iptft_dir}/${BUILD_PURPOSE} 
	fi
	printf "%s\n" "Ok" | tee -a $LOGFILE


	printf "%s\n" "" | tee -a $LOGFILE
	printf "%s\n" "Download, check MD5 and untar IPTFT files:" | tee -a $LOGFILE
	executeL pushd $PWD
	executeL cd ${updatedir}/${ftp_iptft_dir}/${BUILD_PURPOSE}
 
	#Download the files and check MD5 checksum
	for ((i=0 ; i<${#iptft_delta_list[*]}; i++ )) ; do
	
		_file=`basename ${iptft_delta_list[$i]}`
		printf "%s" "${_file} ... " | tee -a $LOGFILE

		ftp_download ${ftp_iptft_dir}/${iptft_delta_list[$i]} 

		if [ $? -ne "0" ] ; then
			exit_msg="EXIT: FTP download file ${ftp_iptft_dir}/${iptft_delta_list[$i]} has failed"
			echo $exit_msg | tee -a $LOGFILE
			exit $EXIT_FAIL_IPTFT_FTP_DOWNLOAD
		fi

		#Calculate MD5 
		_md5=`md5sum ${_file}`
		_md5=${_md5:0:32}
		# Get MD5 value from the file name, example:
		# iptft.r01-rc02.3a679927f36d57c62f17b492196be45a.tar.bz2		
		_md5_orig=${_file#*.}
		_md5_orig=${_md5_orig#*.}
		_md5_orig=${_md5_orig%*.tar.bz2}

		# Compare calculated MD5 with the original one
		if [ "${_md5}" != "${_md5_orig}" ] ; then
			exit_msg="EXIT: MD5 mistmatch for ${_file}, expected ${_md5_orig} got ${_md5}"
			echo $exit_msg | tee -a $LOGFILE  
			exit $EXIT_FAIL_IPTFT_MD5_MISMATCH   	
		fi

		# Untaring 	
		executeL tar xvjf ${_file}
		# Removing tarball
		executeL rm ${_file}
		printf "%s\n" "Ok" | tee -a $LOGFILE
	done
	executeL popd

fi # End of IPTFT update


if [ $ipled_flag = "0" ] ; then
printf "%s\n" "Start downloading IPLED updates" | tee -a $LOGFILE
	executeL pushd $PWD
	executeL cd ${tmpdir}
	executeL touch ${updating_ipled_flag}
	
	printf "%s" "Getting installed IPLED releases ... " | tee -a $LOGFILE
	installed_ipled_releases=( $( ls -1 ${updatedir}/${ftp_ipled_dir} ) )
	printf "%s\n" "Ok" | tee -a $LOGFILE

	printf "%s" "Setting up ${updating_ipled_flag} flag on OBC-SAE ... " | tee -a $LOGFILE
	ftp_uploadL ./${updating_ipled_flag} ${ftp_obc_dir}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	executeL popd
	
	printf "%s" "Removing ${ready_ipled_flag} ... "  | tee -a $LOGFILE
	ftp_deleteL ${ftp_obc_dir}/${ready_ipled_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s" "Removing ${updated_ipled_flag} ... "  | tee -a $LOGFILE
	ftp_delete ${ftp_obc_dir}/${updated_ipled_flag}
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" "" | tee -a $LOGFILE
	printf "%s\n" "Download, check MD5 and utar IPLED files:" | tee -a $LOGFILE

	if [ ! -d ${updatedir}/${ftp_ipled_dir} ] ; then
		executeL mkdir -p ${updatedir}/${ftp_ipled_dir}
	fi

	executeL pushd $PWD
	executeL cd  ${updatedir}/${ftp_ipled_dir}

	printf "%s\n" "List remote files under ${ftp_ipled_dir}: " | tee -a $LOGFILE
	ipled_list=( $( curl -s -u ${ftp_user}:${ftp_pswd} --list-only ftp://${obcsae_ip_addr}/${ftp_ipled_dir}/ ) )
	for (( i=0; i<${#ipled_list[*]}; i++ )) ; do 
		_file=`basename ${ipled_list[$i]}` 
		printf "%s\n" "${_file}" | tee -a $LOGFILE	
	done
	printf "%s\n" "" | tee -a $LOGFILE
	
	printf "%s" "Building up available IPLED releases ... "  | tee -a $LOGFILE
	for (( i=0; i<${#ipled_list[*]}; i++ )) ; do 
		ftp_ipled_releases[$i]=${ipled_list[$i]%*.tar.bz2}
		ftp_ipled_releases[$i]=${ftp_ipled_releases[$i]%.*}
		ftp_ipled_releases[$i]="${ftp_ipled_releases[$i]}.bin"

	done
	printf "%s\n" "Ok" | tee -a $LOGFILE
	
	printf "%s\n" ""
	printf "%s\n" "IPLED releases available on FTP server: "
	printf "%s\n" "${ftp_ipled_releases[@]}"
	printf "%s\n" ""
	
	d=0
	
	for (( i=0; i < ${#ftp_ipled_releases[*]}; i++ )) ; do
		status=0
		for (( j=0; j < ${#installed_ipled_releases[*]}; j++ )) ; do
		
			if [ "${ftp_ipled_releases[$i]}" == "${installed_ipled_releases[$j]}" ] ; then
				status=$(( status | 1 ))
 			fi 
		done
		
		if [ $status -eq 0 ] ; then
			ipled_delta_list[$d]=${ipled_list[$i]}
			d=$(( d + 1 ))
		fi  
	done

	printf "%s\n" ""	
	printf "%s\n" "New IPLED releases available on FTP server: "
	printf "%s\n" "${ipled_delta_list[@]}"	
	printf "%s\n" ""	
	
	#Download the files and check MD5 checksum
	for ((i=0 ; i<${#ipled_delta_list[*]}; i++ )) ; do
	
		_file=`basename ${ipled_delta_list[$i]}`
		printf "%s" "${_file} ... " | tee -a $LOGFILE

		ftp_download ${ftp_ipled_dir}/${ipled_delta_list[$i]} 

		if [ $? -ne "0" ] ; then
			exit_msg="EXIT: FTP file ${ftp_ipled_dir}/${ipled_delta_list[$i]} has failed"
			echo $exit_msg | tee -a
			exit $EXIT_FAIL_IPLED_FTP_DOWNLOAD
		fi

		#Calculate MD5 
		_md5=`md5sum ${_file}`
		_md5=${_md5:0:32}
		# Get MD5 value from the file name, example:
		# iptft.r01-rc02.3a679927f36d57c62f17b492196be45a.tar.bz2		
		_md5_orig=${_file#*.}
		_md5_orig=${_md5_orig#*.}
		_md5_orig=${_md5_orig%*.tar.bz2}

		# Compare calculated MD5 with the original one
		if [ "${_md5}" != "${_md5_orig}" ] ; then
			exit_msg="EXIT: MD5 mismatch for ${_file}, expected ${_md5_orig} got ${_md5}"
			echo $exit_msg | tee -a $LOGFILE
			exit $EXIT_FAIL_IPLED_MD5_MISMATCH   	
		fi

		# Utaring 	
		executeL tar xvjf ${_file}
		# Removing tarball
		executeL rm ${_file}
		printf "%s\n" "Ok" | tee -a $LOGFILE
	done
	executeL popd
fi #End of IPLED update








exit $EXIT_SUCCESS 