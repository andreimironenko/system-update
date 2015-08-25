#! /bin/bash

#Pre-execution check

if [ ! -f /etc/update.conf ] ; then 
	exit 0
fi
source /etc/update.conf

if [ ! -f /etc/pre-post-update.conf ] ; then 
	exit 0
fi
source /etc/pre-post-update.conf

cd ${LOGDIR}

while true ; do 
	
	printf "%s\n" "Check ${ftp_obc_dir}/${ready_stib_flag}"
	ftp_download ${ftp_obc_dir}/${ready_stib_flag}
	stib_flag=$?
	
	printf "%s\n" "Check ${ftp_obc_dir}/${ready_iptft_flag}"
	ftp_download ${ftp_obc_dir}/${ready_iptft_flag}
	iptft_flag=$?

	printf "%s\n" "Check ${ftp_obc_dir}/${ready_ipled_flag}"
	ftp_download ${ftp_obc_dir}/${ready_ipled_flag}
	ipled_flag=$?

	# Result of FTP download can either 0 - meaning success, or non-zero value - meaning failure	
	printf "%s\n" "stib_flag=$stib_flag"
	printf "%s\n" "iptft_flag=$iptft_flag"
	printf "%s\n" "ipled_flag=$ipled_flag"
	
	if [[ ${stib_flag} != "0" && (${iptft_flag} = "0" || ${ipled_flag} = "0")]] ; then
	
		printf "%s\n" "Delete log files left from previous update"
		if [ -d ${LOGDIR} -a  ! -z ${LOGDIR}  ] ; then
			rm ${LOGDIR}/*
		fi
	
		#STIB update is not requested 
		printf "%s\n" "/etc/init.d/pre-uptdate.sh "
		/etc/init.d/pre-update.sh 
		
		printf "%s\n" "/etc/init.d/post-update.sh "
		/etc/init.d/post-update.sh 
		
	elif [[ ${stib_flag} != "0" && ${iptft_flag} != "0" && ${ipled_flag} != "0" ]] ; then
		printf "%s\n" "No flags were found!"	
	else
		# All other scenarios ...
		printf "%s\n" "Delete log files left from previous update"
		if [ -d ${LOGDIR} -a  ! -z ${LOGDIR} ] ; then
			rm ${LOGDIR}/*
		fi
		printf "%s\n" "Start new normal update"
		/etc/init.d/update.sh -s
	fi
	
	sleep 15 
done