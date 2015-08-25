#! /bin/bash

declare -rx SCRIPT=${0##*/}
SCRIPT_PATH="$PWD"

#Global variables
product_release_path="";
update_conf="/etc/update.conf"
hanover_conf="/etc/hanover.conf"

#List of all available releases under the export folder
available_releases=""

# For the sequential update, the system is upgraded from the current_release to
# the requested release step-by-step. The release variable holds 
# the current release which has being installed. 

# Recently installed release
current_release=""
current_id=""
# Release to install
release=""
release_id=""
# Requested release
requested_release=""
requested_id=""

#Bypass pre/post-update stage flag
bypass_flag=0


boot_scr_slink=""
sequential_flag=0

export LOCAL_PATH=""
export HTTP_PATH=""
export FTP_PATH=""

# Exit message which is returned to the user and stored in the 
# update.result.msg file
exit_msg="EXIT: Success"

# Number of maximum attempts to establish FTP/HTTP connection
MAX_ATTEMPT_COUNT=3


# Completion flag, is set by initial_update_handler and checked 
# by after_reboot_handler. If the flag is not set then the initial update has
# failed and the problem must be reported back
# Values:
#    0              Successful update
#    non-zero        Fail exit causes 
result_flag=0

#EXITs
EXIT_SUCCESS=0
EXIT_FAIL_NO_UPDATE_CONF=192
EXIT_FAIL_NO_HANOVER_CONF=193
EXIT_FAIL_NO_RELEASE_PROVIDED=194
EXIT_FAIL_INVALID_PARAMETERS=195
EXIT_FAIL_WRONG_RELEASE=196
EXIT_FAIL_PRE_UPDATE=197
EXIT_FAIL_POST_UPDATE=198
EXIT_FAIL_AFTER_REBOOT_NO_SYMLINK=199
EXIT_FAIL_AFTER_REBOOT_NO_UPDATE_SCR=200
EXIT_FAIL_AFTER_REBOOT_RESULT_FLAG=201
EXIT_FAIL_AFTER_REBOOT_FIRST_STAGE_UPDATE=202
EXIT_FAIL_EXECUTEL=203
EXIT_FAIL_NO_CURRENT_REL_FOUND=205
EXIT_FAIL_RETRIEVE_LOCAL=206
EXIT_FAIL_RETRIEVE_HTTP=207
EXIT_FAIL_RETRIEVE_FTP=208




# This function takes one parameter - command to execute
# Run it with disabled output and return the result. 
#  
function execute ()
{
	#Redirect standard error stream to standard output
	2>&1
	
    $* >/dev/null
    return $?
}
export -f execute

# This function takes one parameter - command to execute
# Run it with disabled output and check the result. In case of fault it will
# leave that is denoted by capital L.
function executeL ()
{
	#Redirect standard error stream to standard output
	2>&1
	#Store command
	_cmd=$*
	
	#Execute the command
    $* >/dev/null
    
    #Store exit code 
	_exit_code=$?
	
    #Check the return result, if it fails exit
    if [ ${_exit_code} -ne 0 ]; then
    	echo "" | tee -a $LOGFILE
        exit_msg="ERROR: executing ${_cmd} returns ${_exit_code}"
		echo ${exit_msg} | tee -a $LOGFILE
        echo "" | tee -a $LOGFILE
        exit $EXIT_FAIL_EXECUTEL
    fi
}
export -f executeL

# This function takes two parameters:
# 1: number of attempts to execute
# 2: command to execute
# The command is ran with disabled output. The number attempts defined by first  
# parameter will be performed. It does not exit and just return the error code. 
function executeR ()
{
	_max=$1
	_cmd=$2
	_r=0
	
	#Redirect standard error stream to standard output
	2>&1

	for (( a=0; a<${_max} ; a++ )) ; do  	
    	${_cmd} > /dev/null
    	_r=$?
    	if [ ${_r} -eq "0" ] ; then
    		break;
    	fi
	done
	
   	return ${_r}
}
export -f executeR



function cleanup_handler ()
{
	printf "%s" "Renaming /boot/update.scr to disable.update.scr ... " | tee -a $LOGFILE
	if [ -f /boot/update.scr ] ; then
		executeL mv /boot/update.scr /boot/disable.update.scr
	fi
	printf "%s\n" "Done"  | tee -a $LOGFILE

	printf "%s" "Removing symlink in rc5.d ... " | tee -a $LOGFILE
	if [ -L /etc/rc5.d/S99update ] ; then 
		executeL rm /etc/rc5.d/S99update
	fi
	printf "%s\n" "Done" | tee -a $LOGFILE
	
	
	printf "%s" "Cleaning up temporary files ... " | tee -a $LOGFILE
	if [ -f $TMPDIR/install.packages ] ; then
		executeL rm $TMPDIR/install.packages
	fi
	
	if [ -f $TMPDIR/remove.packages ] ; then
		executeL rm $TMPDIR/remove.packages
	fi
		
	if [ -f $TMPDIR/current.packages ] ; then
		executeL rm $TMPDIR/current.packages
	fi
	
	if [ -f $TMPDIR/new.packages ] ; then
		executeL rm $TMPDIR/new.packages
	fi
	printf "%s\n" "Done" | tee -a $LOGFILE
}
export -f cleanup_handler

# Exit handler, this function is called every time when exit is invoked
function exit_handler ()
{
	#Store exit value in the local variable
	_exit_status=$?
	
	printf "%s\n" "Touch $UPDATE_READY_FILE, to indicate update has completed" | tee -a $LOGFILE
	touch $UPDATE_READY_FILE
		
	case ${_exit_status} in
	
		$EXIT_SUCCESS)
			
		
		printf "%s" "Set result code and message" | tee -a $LOGFILE
		exit_msg="EXIT: Success"
		echo $exit_msg | tee -a $LOGFILE
		result_flag=0
		echo ${result_flag} > $UPDATE_RESULT_FILE 
		echo ${exit_msg} > $UPDATE_RESULT_MSG
				
		if [ -f /etc/init.d/post-update.sh -a $bypass_flag -ne 1  ] ; then
			printf "%s" "Post-update procedure ... "	| tee -a $LOGFILE
			/etc/init.d/post-update.sh
			result_flag=$?
			
			# Clean up temp.files	
			cleanup_handler
	
			if [ $result_flag -ne 0 ] ; then
				printf "%s\n" "Failed"                  | tee -a $LOGFILE
			else
				printf "%s\n" "Done"					| tee -a $LOGFILE
			
			fi
		fi
		;;
	
		$EXIT_FAIL_INVALID_PARAMETERS)
		mkdir -p ${LOGDIR} 
		echo 195 > ${LOGDIR}/update.result.flag
		echo "EXIT: 195: Failed, invalid user parameters" > ${LOGDIR}/update.result.msg
		;;
		
		$EXIT_FAIL_NO_UPDATE_CONF)
		mkdir -p ${LOGDIR} 
		echo 192 > ${LOGDIR}/update.result.flag
		echo "EXIT: 192: Failed, /etc/update.conf is not found" > ${LOGDIR}/update.result.msg
		;;
		
		$EXIT_FAIL_NO_HANOVER_CONF)
		mkdir -p ${LOGDIR} 
		echo 193 > ${LOGDIR}/update.result.flag
		echo "EXIT: 193: Failed, /etc/hanover.conf is not found" > ${LOGDIR}/update.result.msg
		;;	
		
		
		$EXIT_FAIL_NO_RELEASE_PROVIDED					| \
		$EXIT_FAIL_WRONG_RELEASE 						| \
		$EXIT_FAIL_PRE_UPDATE							| \
		$EXIT_FAIL_POST_UPDATE							| \
		$EXIT_FAIL_AFTER_REBOOT_NO_SYMLINK				| \
		$EXIT_FAIL_AFTER_REBOOT_NO_UPDATE_SCR			| \
		$EXIT_FAIL_AFTER_REBOOT_RESULT_FLAG				| \
		$EXIT_FAIL_EXECUTEL								| \
		$EXIT_FAIL_NO_CURRENT_REL_FOUND					| \
		$EXIT_FAIL_RETRIEVE_LOCAL						| \
		$EXIT_FAIL_RETRIEVE_HTTP						| \
		$EXIT_FAIL_RETRIEVE_FTP)	
			echo "${_exit_status}" > $UPDATE_RESULT_FILE
			echo ${exit_msg} > $UPDATE_RESULT_MSG
			cleanup_handler
		;;
		
		*) 
			echo "${_exit_status}" > ${UPDATE_RESULT_FILE}
			echo ${exit_msg} > ${UPDATE_RESULT_MSG}
			cleanup_handler
	esac	
}
export -f exit_handler

# This function extract generate the list of the packages from opkg status file
function extract_package ()
{
	status_file=$1
	package_file=$2
	
	exec 3< $status_file
	
	if [ -f $TMPDIR/packages.tmp ] ; then
		rm  $TMPDIR/packages.tmp
	fi
	
	PACKAGE_PREFIX="Package:"
	VERSION_PREFIX="Version:"
	PACKAGE=""
	VERSION=""
	
	executeL touch $TMPDIR/package.tmp
	  
	while read LINE <&3 ; do
	   if test "${LINE#*$PACKAGE_PREFIX}" != "${LINE}"  ; then
	    PACKAGE=${LINE:9}   
	   fi 
	   
		if [ -n "$PACKAGE" ] ; then
	    echo "${PACKAGE}" >> $TMPDIR/package.tmp
	     PACKAGE=""
	     VERSION=""
		fi
	done
	
	sort -f $TMPDIR/package.tmp > $package_file
	executeL rm -rf $TMPDIR/package.tmp
	return $EXIT_SUCCESS
}
export -f extract_package

# This function compares two list of packages and generates the list of 
# the new and obsolete packages
function compare_packages () 
{
	current_package=$1
	new_package=$2
	output_path=$3
	
	exec 4< $current_package
	exec 5< $new_package
	
	if [ -f $output_path/remove.packages ] ; then
		executeL rm $output_path/remove.packages
	fi
	
	if [ -f $output_path/install.packages ] ; then
		executeL rm $output_path/install.packages
	fi
	
	index=0
	while read LINE <&4 ; do
		grep $LINE $new_package > /dev/null
		if [ $? -ne "0" ] ; then
			echo $LINE >> $output_path/remove.packages
			let "index++"
		fi
	done
	
	index=0
	while read LINE <&5 ; do
		grep $LINE $current_package > /dev/null
		if [ $? -ne "0" ] ; then
			echo $LINE >> $output_path/install.packages
			let "index++"
		fi
	done
	return 0 
}
export -f compare_packages
 
# This function will retrieve the file from the update media
# Parameters:
# 	source_file  - Path must be relative to LOCAL_PATH, HTTP_PATH or FTP_PATH
#	destdir      - Destination folder where it should be copied
# Return:
#	EXIT_SUCCESS - In success
#   EXIT_FAIL_RETRIEVE_XXX - If the file can't be retrieved
function retrieve_file () 
{
	source_file=$1
	destdir=$2

	case ${UPDATESRC} in 
	
	local)
	
	if [ ! -f ${LOCAL_PATH}/$source_file ] ; then
		exit_msg="EXIT: Failed to retrieve file ${LOCAL_PATH}/$source_file" 
		echo $exit_msg | tee -a $LOGFFILE
		exit  $EXIT_FAIL_RETRIEVE_LOCAL 
	fi
	
	executeL cp ${LOCAL_PATH}/$source_file $destdir
	;;
	
	http)
	
	executeL pushd $PWD
	executeL cd $destdir 
	executeR $MAX_ATTEMPT_COUNT "wget -q  http://${HTTP_SERVER}/${HTTP_PATH}/$source_file"
	if [ !  $? -eq 0 ] ; then
		exit_msg="EXIT: wget returns $?, failed to retrieve file http://${HTTP_SERVER}/${HTTP_PATH}/$source_file"
		echo $exit_msg | tee -a $LOGFILE
		executeL popd
		exit $EXIT_FAIL_RETRIEVE_HTTP
	fi
	executeL popd
	;;
	
	ftp)
	
	executeL pushd $PWD
	executeL cd $destdir 
	executeR $MAX_ATTEMPT_COUNT "wget -q ftp://ftp@${FTP_SERVER}/${FTP_PATH}/$source_file"
	if [ $? -ne 0 ] ; then
		exit_msg="EXIT: wget returns $?, failed to retrieve file ftp://${FTP_SERVER}/${FTP_PATH}/$source_file" 
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_FTP
	fi
	executeL popd
	;;
	
	esac
	

	return $EXIT_SUCCESS	
}
export -f retrieve_file 

# Retrieve available releases from the remote repository
# This function will return EXIT_SUCCESS and the list will be stored in local
# variable available_releases.
# In case of failure it returns non-zero value 
function retrieve_available_releases () 
{
	case ${UPDATESRC} in 
	
	local)
	
	LOCAL_PATH=${LOCAL_BASE_PATH}/${BUILD_PURPOSE} 
	
	if [ ! -d  ${LOCAL_PATH} ] ; then
		exit_msg="EXIT: The folder ${LOCAL_PATH} does not exist"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_LOCAL 
	fi
	
	available_releases=( $(ls -1 ${LOCAL_PATH} | grep ${PRODUCT}) )
	for (( i=0 ; i < ${#available_releases[@]} ; i ++ )) ; do
		available_releases[$i]=${available_releases[$i]/$PRODUCT./}
	done
	
	;;
	
	http)
	
	if [ -z $HTTP_BASE_PATH ] ; then
		HTTP_PATH="${BUILD_PURPOSE}"
	else
		HTTP_PATH="${HTTP_BASE_PATH}/${BUILD_PURPOSE}"
	fi
	
	executeL pushd $PWD
	executeL cd $TMPDIR
	executeR $MAX_ATTEMPT_COUNT wget -q --spider -np -r -l 1 http://${HTTP_SERVER}/${HTTP_PATH}/
	if [ !  $? -eq 0 ] ; then
		exit_msg="EXIT: wget returns $?, failed to retrieve http://${HTTP_SERVER}/${HTTP_PATH}"
		echo $exit_msg | tee -a $LOGFILE
		executeL popd
		exit $EXIT_FAIL_RETRIEVE_HTTP
	fi
	
	available_releases=( $(ls -1 ${TMPDIR}/${HTTP_SERVER}/${HTTP_PATH} | grep ${PRODUCT}) )
	for (( i=0 ; i < ${#available_releases[@]} ; i ++ )) ; do
		available_releases[$i]=${available_releases[$i]/$PRODUCT./}
	done

	executeL rm -rf ${HTTP_SERVER}
	executeL popd
	;;
	
	ftp)
	
	if [ -z $FTP_BASE_PATH ] ; then
		FTP_PATH="${BUILD_PURPOSE}"
	else
		FTP_PATH="${FTP_BASE_PATH}/${BUILD_PURPOSE}"
	fi
	
	executeL pushd $PWD
	executeL cd $TMPDIR
	executeR $MAX_ATTEMPT_COUNT wget -q --spider -r -l 2  ftp://ftp@${FTP_SERVER}/${FTP_PATH}/
	if [ $? -ne 0 ] ; then
		exit_msg="EXIT: wget returns $?, failed to retrieve ftp://${FTP_SERVER}/${FTP_PATH}"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_FTP 
	fi
	
	available_releases=( $(ls -1 ${TMPDIR}/${FTP_SERVER}/${FTP_PATH} | grep ${PRODUCT}) )
	for (( i=0 ; i < ${#available_releases[@]} ; i ++ )) ; do
		available_releases[$i]=${available_releases[$i]/$PRODUCT./}
	done

	executeL rm -rf ${HTTP_SERVER}
	executeL popd
	;;
	
	esac
	
	return 0 
}
export -f retrieve_available_releases 


#Retrieving current release from /etc/hanover.conf
function retrieve_current_release ()
{
	rel=`cat /etc/hanover.conf | grep PRODUCT_RELEASE` 
	rel=${rel#*=}
	
	ver=`cat /etc/hanover.conf | grep PRODUCT_VERSION`
	ver=${ver#*=}
	
	current_release="$rel-$ver"
}
export -f retrieve_current_release


#Get release index from available_releases array
# param		Release
# return    release_id
function get_release_id ()
{
	_rel=$1
	_found=0
	
	for (( r=0 ; r < ${#available_releases[*]}; r++ )); do
		if [ "${_rel}" = "${available_releases[$r]}" ] ; then
			_found=1	
			break;
		fi
	done
	
	if [  ${_found} -ne 1 ] ; then
		r=255
	fi
	
	return $r;
}

# This function sources hanover.conf and update.conf. Retrieve available 
# releases and initialize local variable available_releases. 
function update_init ()
{ 
	#Local variable
	_res=0;
	
	printf "%s" "Source $hanover_conf ..." 
	if [ ! -f $hanover_conf ] ; then 
		printf "%s\n" "Fail" 
		exit_msg="Configuration file $hanover_conf is not found!"
		echo $exit_msg
		exit $EXIT_FAIL_NO_HANOVER_CONF
	fi
	executeL source $hanover_conf
	printf "%s\n" "Done"

	printf "%s" "Source $update_conf ... " 
	if [ ! -f $update_conf ] ; then 
		printf "%s\n" "Fail"
		exit_msg="Configuration file $update_conf is not found!"
		echo $exit_msg 
		exit $EXIT_FAIL_NO_UPDATE_CONF
	fi
	executeL source $update_conf
	printf "%s\n" "Done" 
	
	
	##########################################################	
	# After reboot initialisation steps                      # 
	##########################################################
	if [[ -f /boot/update.scr && -L /etc/rc5.d/S99update ]] ; then
		printf "%s" "Checking temproary $TMPDIR directory ... "
		if [ ! -d $TMPDIR ] ; then
			executeL mkdir -p $TMPDIR
		fi
		printf "%s\n" "Done"
	
		printf "%s" "Checking temproary $LOGDIR directory ... "
		if [ ! -d $LOGDIR ] ; then
			executeL mkdir -p $LOGDIR
		fi
		printf "%s\n" "Done"
	
		printf "%s" "Creating $LOGFILE ..."
		if [ ! -f $LOGFILE ] ; then 
			executeL touch $LOGFILE
		fi
		printf "%s\n" "Done"
			
		printf "%s" "Check presence of $UPDATE_RESULT_FILE ... " | tee -a $LOGFILE
		if [ ! -f $UPDATE_RESULT_FILE ] ; then
			printf "%s\n" "Failed" | tee -a $LOGFILE
			exit_msg="The file $UPDATE_RESULT_FILE is not found"
			echo $exit_msg | tee -a $LOGFILE
			exit $EXIT_FAIL_AFTER_REBOOT_RESULT_FLAG  
		fi
		printf "%s\n" "Done"
		
		printf "%s" "Check result_flag value ... " | tee -a $LOGFILE 
		result_flag=`cat $UPDATE_RESULT_FILE`
		if [ $result_flag != "0" ] ; then
			printf "%s\n" "Failed" | tee -a $LOGFILE
			exit_msg="Exit: First stage failed returning $result_flag" 
			echo $exit_msg | tee -a $LOGFILE 
			exit $EXIT_FAIL_AFTER_REBOOT_FIRST_STAGE_UPDATE
		else
			printf "%s\n" "Done" | tee -a $LOGFILE
		fi 
	##########################################################	
	# After reboot error condition, S99update was not found  #
	##########################################################
	elif [[ -f /boot/update.scr && (! -L /etc/rc5.d/S99update) ]] ; then
		exit_msg="After reboot, symlink S99update is not found!"
		echo $exit_msg
		exit $EXIT_FAIL_AFTER_REBOOT_NO_SYMLINK
	##########################################################	
	# After reboot error condition, update.scr was not found #
	##########################################################
	elif [[ (! -f /boot/update.scr) && -L /etc/rc5.d/S99update ]] ; then
		exit_msg="After reboot, /boot/update.scr is not found!"
		echo $exit_msg
		exit $EXIT_FAIL_AFTER_REBOOT_NO_UPDATE_SCR
	##########################################################	
	# Initial update initialisation procedure                #	
	##########################################################	
	else
		printf "%s" "Checking temproary $TMPDIR directory ... "
		if [ ! -d $TMPDIR ] ; then
			executeL mkdir -p $TMPDIR
		fi
		printf "%s\n" "Done"
	
		printf "%s" "Checking temproary $LOGDIR directory ... "
		if [ ! -d $LOGDIR ] ; then
			executeL mkdir -p $LOGDIR
		else
			executeL rm -rf $LOGDIR/*
		fi
		printf "%s\n" "Done"
	
		printf "%s" "Creating $LOGFILE ..."
		executeL touch $LOGFILE
		printf "%s\n" "Done"
	fi
	##########################################################	
	# Common initialisation steps                            #	
	##########################################################	
		
	return 0	
}
export -f update_init 


function update_pre_check() 
{
# Retrive available releases and set LOCAL_PATH, HTTP_PATH or FTP_PATH
# variables
retrieve_available_releases

#Retrive current release
retrieve_current_release
	
printf "%s" "Is requested release available? ... " | tee -a $LOGFILE
echo ${available_releases[@]} | grep $release > /dev/null
if [ $? -eq 0 ] ; then
	printf "%s\n" "Yes" | tee -a $LOGFILE
else
	printf "%s\n"  "No" | tee -a $LOGFILE
	printf "%s\n" "Available releases:" | tee -a $LOGFILE
	printf "%s\n" ${available_releases[*]} | tee -a $LOGFILE
	exit_msg="Requested release $release was not found among available releases"
	echo $exit_msg | tee -a $LOGFILE
	exit $EXIT_FAIL_NO_RELEASE_PROVIDED
fi

printf "\n%s\n" "Start upgrading $PRODUCT "				| tee -a $LOGFILE
printf "\t%s\n" "from $current_release to $release"     | tee -a $LOGFILE 

# Generate Product release path
product_release_path="${PRODUCT}.${release}/${RELDIR}/ipk"

printf "%s" "Checking ipk folder ... " 					| tee -a $LOGFILE

case ${UPDATESRC} in 
	
	local)
	
	execute cat ${LOCAL_PATH}/${product_release_path}/Packages
	if [ ! $? = "0" ] ; then
		exit_msg="Failed to retrieve ${LOCAL_PATH}/${product_release_path}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_LOCAL
	fi
	
	execute cat ${LOCAL_PATH}/${product_release_path}/all/Packages
	if [ ! $? = "0" ] ; then
		exit_msg="Failed to retrieve ${LOCAL_PATH}/${product_release_path}/all/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_LOCAL
	fi

	execute cat ${LOCAL_PATH}/${product_release_path}/${FEED_ARCH}/Packages
	if [ ! $? = "0" ] ; then
		exit_msg="Failed to retrieve ${LOCAL_PATH}/${product_release_path}/${FEED_ARCH}/Packages" 
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_LOCAL
	fi

	execute cat ${LOCAL_PATH}/${product_release_path}/${MACHINE}/Packages
	if [ ! $? = "0" ] ; then
		exit_msg="Failed to retrieve ${LOCAL_PATH}/${product_release_path}/${MACHINE}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_LOCAL
	fi
	
	;;
	
	http)
	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/Packages"
	if [ ! $? = "0" ] ; then
		exit_msg="wget returns $?, failed to retrieve http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETRIEVE_HTTP		
	fi
	
	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/all/Packages"
	if [ ! $? = "0" ] ; then
		exit_msg="wget returns $?, failed to retrieve http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/all/Packages"
		echo $exit_msg | tee -a $LOGFILE 
		exit $EXIT_FAIL_RETREIVE_HTTP 
	fi

	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/${FEED_ARCH}/Packages"
	if [ ! $? = "0" ] ; then
		exit_msg="wget returns $?, failed to retrieve http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/${FEED_ARCH}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETREIVE_HTTP 
	fi

	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/${MACHINE}/Packages"
	if [ ! $? = "0" ] ; then
		exit_msg="wget returns $?, failed to retrieve http://${HTTP_SERVER}/${HTTP_PATH}/${product_release_path}/${MACHINE}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETREIVE_HTTP 
	fi
	
	;;
	
	ftp)
	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet ftp://ftp@${FTP_SERVER}/${FTP_PATH}/${product_release_path}/Packages"
	if [ $? -ne 0 ] ; then
		exit_msg="wget returns $?, failed to retrieve ftp://${FTP_SERVER}/${FTP_PATH}/${product_release_path}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETREIVE_FTP
	fi
	
	executeR $MAX_ATTEMPT_COUNT  "wget --spider --quiet ftp://ftp@${FTP_SERVER}/${FTP_PATH}/${product_release_path}/all/Packages"
	if [ $? -ne 0 ] ; then
		exit_msg="wget returns $?, failed to retrieve ftp://${FTP_SERVER}/${FTP_PATH}/${product_release_path}/all/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETREIVE_FTP
	fi

	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet ftp://ftp@${FTP_SERVER}/${FTP_PATH}/${product_release_path}/${FEED_ARCH}/Packages"
	if [ $? -ne 0 ] ; then
		exit_msg="wget returns $?, failed to retrieve ftp://${FTP_SERVER}/${FTP_PATH}/${product_release_path}/${FEED_ARCH}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETREIVE_FTP
	fi

	executeR $MAX_ATTEMPT_COUNT "wget --spider --quiet ftp://ftp@${FTP_SERVER}/${FTP_PATH}/${product_release_path}/${MACHINE}/Packages"
	if [ $? -ne 0 ] ; then
		exit_msg="wget returns $?, failed to retrieve ftp://${FTP_SERVER}/${FTP_PATH}/${product_release_path}/${MACHINE}/Packages"
		echo $exit_msg | tee -a $LOGFILE
		exit $EXIT_FAIL_RETREIVE_FTP
	fi
	
	;;
esac

printf "%s\n" "Done"

return 0
}
export -f update_pre_check


 
# This is initial action made by update.sh script before the system reboots.
# During the execution of this code, S99update symlink is created under rc5.d,
# so after the reboot the update.sh will be started automatically again 
function initial_update_handler ()
{
	if [ ! -d $LOGDIR ] ; then
		printf "%s\n" "Creating log directory" | tee -a $LOGFILE
		executeL mkdir -p $LOGDIR
	fi
	
	printf "%s" "Preserving boot.scr symlink ..." | tee -a $LOGFILE
    curdir="$PWD"
    executeL cd /boot
    boot_scr_slink=`readlink boot.scr`
    executeL cd $curdir
	printf "%s\n" "Done" | tee -a $LOGFILE
    
	printf "%s" "Retrieving opkg.status from update media ... " | tee -a $LOGFILE
	retrieve_file ${product_release_path}/${MACHINE}/opkg.status	$TMPDIR
	printf "%s\n" "Done" | tee -a $LOGFILE
	
	printf "%s" "Extract all package names from the generated new.status ... " | tee -a $LOGFILE
	extract_package  $TMPDIR/opkg.status $TMPDIR/new.packages
	printf "%s\n" "Done" | tee -a $LOGFILE
	
	printf "%s" "Extract all package names from the target status file ... " | tee -a $LOGFILE
	extract_package  /usr/lib/opkg/status $TMPDIR/current.packages
	printf "%s\n" "Done" | tee -a $LOGFILE

	#Compare current.packages and new.packages list and create two files under
	# /tmp:
	# remove.packages - list of packages to be removed
	# install.packages - list of packages to be installed
	printf "%s" "Compare generated current.packages and new.packages lists ... " | tee -a $LOGFILE
	compare_packages $TMPDIR/current.packages    $TMPDIR/new.packages $TMPDIR 
	printf "%s\n" "Done" | tee -a $LOGFILE

	printf "%s" "Start updating opkg configuration" | tee -a $LOGFILE
	opkg update | tee -a $LOGFILE
	
	# hanover-configs and build-scripts must be always re-installed because
	# they contained build-time information and although the release of the 
	# package is the same, the content is product/build specific. 
	opkg  install --force-reinstall hanover-configs | tee -a $LOGFILE
	opkg  install --force-reinstall build-scripts   | tee -a $LOGFILE
	opkg  install --force-reinstall initscripts     | tee -a $LOGFILE
	opkg  install --force-reinstall hanover-security| tee -a $LOGFILE
	
	if [ -f $TMPDIR/remove.packages ] ; then
		exec 5< $TMPDIR/remove.packages
		printf "%s\n" "These packages are obsolete and will be removed:" | tee -a $LOGFILE 
		cat $TMPDIR/remove.packages | tee -a $LOGFILE
		#Read all packages need to be removed
		while read LINE <&5 ; do
		opkg --force-depends remove ${LINE} | tee -a $LOGFILE
		done
	fi

	if [ -f $TMPDIR/install.packages ] ; then
		exec 6< $TMPDIR/install.packages
		printf "%s\n" "These packages are new and will be installed:" | tee -a $LOGFILE
		cat $TMPDIR/install.packages | tee -a $LOGFILE
		#Read all packages need to be installed	
		while read LINE <&6 ; do
			opkg --force-depends install ${LINE} | tee -a $LOGFILE
		done
	fi

	printf "%s" "Start upgrading packages " | tee -a $LOGFILE
	opkg upgrade | tee -a $LOGFILE 
	
	printf "%s" "Restoring boot.scr symlink ... " | tee -a $LOGFILE
	if [ ! -z $boot_scr_slink ] ; then
		curdir="$PWD"
		executeL cd /boot
		executeL ln -sf $boot_scr_slink boot.scr
		executeL cd $curdir
	fi
	printf "%s\n" "Done" | tee -a $LOGFILE
	
	if [ -e /dev/mtd1 ] ; then
		printf "%s" "Writing u-boot.bin to NAND ... " | tee -a $LOGFILE
		executeL flash_erase /dev/mtd1 0 0
		executeL nandwrite -p /dev/mtd1 /boot/img/u-boot.bin
		printf "%s\n" "Done" | tee -a $LOGFILE
	fi
	
	if [ -e /dev/mtd2 ] ; then
		printf "%s" "Writing default.scr to NAND ... " | tee -a $LOGFILE
		executeL flash_erase /dev/mtd2 0 0
		executeL nandwrite -p /dev/mtd2 /boot/img/default.scr
		printf "%s\n" "Done" | tee -a $LOGFILE
	fi
		
	printf "%s" "Renaming disable.update.scr to update.scr ... " | tee -a $LOGFILE
	if [ -f /boot/disable.update.scr ] ; then
		executeL mv /boot/disable.update.scr /boot/update.scr
	fi
	printf "%s\n" "Done" | tee -a $LOGFILE

	printf "%s" "Creating symlink in rc5.d ... " | tee -a $LOGFILE
	executeL cd /etc/rc5.d
	executeL ln -sf ../init.d/update.sh S99update
	printf "%s\n" "Done" | tee -a $LOGFILE
	
}
export -f initial_update_handler



# This function implements after the reboot steps performed by update.sh
function after_reboot_handler ()
{
	printf "%s" "Source $hanover_conf ..." | tee -a $LOGFILE
	if [ ! -f $hanover_conf ] ; then 
		exit_msg="Configuration file $hanover_conf is not found!"
		echo $exit_msg | tee -a $LOGFILE 
		exit $EXIT_FAIL_NO_HANOVER_CONF
	fi
	source $hanover_conf
	printf "%s\n" "Done" | tee -a $LOGFILE

	printf "%s" "Source $update_conf ... " | tee -a $LOGFILE
	if [ ! -f $update_conf ] ; then 
		exit_msg="Configuration file $update_conf is not found!"
		echo $exit_msg | tee -a $LOGFILE 
		exit $EXIT_FAIL_NO_UPDATE_CONF
	fi
	source $update_conf
	printf "%s\n" "Done" | tee -a $LOGFILE
	
	printf "%s\n" "Running after reboot opkg upgrade " | tee -a $LOGFILE
	opkg upgrade  | tee -a $LOGFILE
		
	return $EXIT_SUCCESS 
}
export -f after_reboot_handler


function regenerate_opkg_conf () 
{
	printf "%s" "Regenerating opkg configuration files ... "
	if [ -f /etc/opkg/opkg.conf ] ; then
		executeL mv /etc/opkg/opkg.conf /etc/opkg/opkg.default
	fi

	executeL cat /etc/opkg/opkg.default > /etc/opkg/opkg.http.cfg
	executeL cat /etc/opkg/opkg.default > /etc/opkg/opkg.ftp.cfg 
	executeL cat /etc/opkg/opkg.default > /etc/opkg/opkg.local.cfg  

   #HTTP
   if [ -z ${HTTP_BASE_PATH} ] ; then  
        echo "src/gz all       http://${HTTP_SERVER}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/all" >> /etc/opkg/opkg.http.cfg
        echo "src/gz feed_arch http://${HTTP_SERVER}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${FEED_ARCH}" >> /etc/opkg/opkg.http.cfg
        echo "src/gz machine   http://${HTTP_SERVER}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${MACHINE}" >> /etc/opkg/opkg.http.cfg 
   else
        echo "src/gz all       http://${HTTP_SERVER}/${HTTP_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/all" >> /etc/opkg/opkg.http.cfg
        echo "src/gz feed_arch http://${HTTP_SERVER}/${HTTP_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${FEED_ARCH}" >> /etc/opkg/opkg.http.cfg
        echo "src/gz machine   http://${HTTP_SERVER}/${HTTP_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${MACHINE}" >> /etc/opkg/opkg.http.cfg   
   fi 
    
   #FTP
   if [ -z ${FTP_BASE_PATH} ] ; then 
        echo "src/gz all       ftp://ftp@${FTP_SERVER}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/all" >> /etc/opkg/opkg.ftp.cfg 
        echo "src/gz feed_arch ftp://ftp@${FTP_SERVER}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${FEED_ARCH}" >> /etc/opkg/opkg.ftp.cfg 
        echo "src/gz machine   ftp://ftp@${FTP_SERVER}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${MACHINE}" >> /etc/opkg/opkg.ftp.cfg
   else
        echo "src/gz all       ftp://ftp@${FTP_SERVER}/${FTP_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/all" >> /etc/opkg/opkg.ftp.cfg 
        echo "src/gz feed_arch ftp://ftp@${FTP_SERVER}/${FTP_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${FEED_ARCH}" >> /etc/opkg/opkg.ftp.cfg 
        echo "src/gz machine   ftp://ftp@${FTP_SERVER}/${FTP_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${MACHINE}" >> /etc/opkg/opkg.ftp.cfg  
   fi  
    
    #LOCAL FILE SYSTEM
   if [ -z ${LOCAL_BASE_PATH} ] ; then
        echo "src/gz all       file:///${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/all" >> /etc/opkg/opkg.local.cfg  
        echo "src/gz feed_arch file:///${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${FEED_ARCH}" >> /etc/opkg/opkg.local.cfg  
        echo "src/gz machine   file:///${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${MACHINE}" >> /etc/opkg/opkg.local.cfg  
   else
        echo "src/gz all       file:///${LOCAL_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/all" >> /etc/opkg/opkg.local.cfg  
        echo "src/gz feed_arch file:///${LOCAL_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${FEED_ARCH}" >> /etc/opkg/opkg.local.cfg  
        echo "src/gz machine   file:///${LOCAL_BASE_PATH}/${BUILD_PURPOSE}/${PRODUCT}.${release}/${RELDIR}/ipk/${MACHINE}" >> /etc/opkg/opkg.local.cfg  
   fi

   # Creating opkg.conf symbol link   
	executeL pushd $PWD
	executeL cd /etc/opkg   
  case ${UPDATESRC} in 
	local)
		executeL ln -sf opkg.local.cfg opkg.conf
	;;
	
	http)
		executeL ln -sf opkg.http.cfg opkg.conf
	;;
	
	ftp)
		executeL ln -sf opkg.ftp.cfg opkg.conf
	;;
  esac
 executeL popd

printf "%s\n" "Done"
}
export -f regenerate_opkg_conf 


while [ $# -gt 0 ]; do
  case $1 in
    --help | -h) 
    printf "%s\n"             
    printf "%s\n" "Upgrading the target from local media, HTTP or FTP server"
	printf "%s\n"
	printf "%s\n" "Usage: $SCRIPT [options] release"
	printf "%s\n"
	printf "%s\n" "Options:"
	printf "%s\n"
	printf "%s\t%s\n" "-s, --sequential"  "Optional. Sequential product update" 
	printf "%s\n"
	printf "%s\t%s\n" "-b, --bypass"      "Optional. Bypass execution of the pre-update.sh and post-update.sh" 
	printf "%s\n"
	printf "%s\t%s\n" "-c, --cfg"         "Optional. Customer provided update.cfg file."
	printf "\t\t%s\n"                     "If it's not provided, the default /etc/update.cfg is used."
	printf "%s\n"
	printf "%s\t%s\n" "-l, --list"        "Optional. List available product releases" 
	printf "%s\n"
	printf "%s\t%s\n" "-r, --reconf"       "Optional. Regenerate opkg.conf, based on update.cfg parameters" 
	printf "%s\n"
	printf "%s\t%s\n" "-h, --help"        "This help"
	printf "%s\n"
	printf "%s\n" "Examples:"
	printf "%s\n" "To upgrade to the latest release with default configuration " 
	printf "\t%s\n" "$SCRIPT"
	printf "%s\n"
	printf "%s\n" "To make release specific upgrade, with default configuration" 
	printf "\t%s\n" "$SCRIPT r03-rc04"
	printf "%s\n"
	printf "%s\n" "To make user configured upgrade for the certain release:"
	printf "\t%s\n" "$SCRIPT -c ~/update.cfg r03-rc04 "
	printf "%s\n"
	exit $EXIT_SUCCESS
    ;;
    
    --list| -l)  shift;
    	update_init
    	
		# Retrive available releases and set LOCAL_PATH, HTTP_PATH or FTP_PATH
		# variables
		retrieve_available_releases
		
		#Retrive current release
		retrieve_current_release
	
		if [ -z $requested_release ] ; then
			printf "\n%s\n" "Warning: New release ID was not provided," | tee -a $LOGFILE
			requested_release=${available_releases[${#available_releases[*]}-1]} 
			printf "%s\n" "taking the newest one - $requested_release" | tee -a $LOGFILE
		fi
		
    	printf "\n%s\n" "Available releases for $PRODUCT:"
		printf "\t%s\n" ${available_releases[@]}
    	exit $EXIT_SUCCESS
    ;;
    
    --cfg| -c)  shift;
    	update_conf=$1
    	continue 
    ;;
   
    --sequential| -s)  shift;
     	sequential_flag=1	
    	continue 
    ;;
   
    --bypass| -b) shift; 
		bypass_flag=1
		continue;
	;;
    
    --reconf| -r)  shift;
    	update_init
    	regenerate_opkg_conf 
    	exit $EXIT_SUCCESS
    ;;
    
        
	-*)  exit_msg="Switch not supported"; printf "%s\n" $exit_msg >&2; exit $EXIT_FAIL_INVALID_PARAMETERS ;;
	
	*)  requested_release=$1
		#shift
		break;
		;;  
esac
done



###########################################
# SCRIPT ENTRY POINT                      #
###########################################

# Declare exit handler
trap exit_handler EXIT

if [ -f /boot/update.scr -a -L /etc/rc5.d/S99update ] ; then
	###########################################################################
	# After reboot, second stage update procedure                             #
	###########################################################################
	
	#Initializing update configuration
	update_init

	#After reboot update procedure
	after_reboot_handler 
	
	printf "%s\n" "Update has successfully completed" | tee -a $LOGFILE
	exit $EXIT_SUCCESS
	
else
	###########################################################################
	# Intial, before reboot, update procedure                                 #
	###########################################################################
	update_init
	
	# Executing pre-update.sh	
	if [ -f /etc/init.d/pre-update.sh -a $bypass_flag -ne 1  ] ; then
		printf "%s" "Pre-update procedure ... "		| tee -a $LOGFILE
		/etc/init.d/pre-update.sh
		if [ $? -ne 0 ] ; then
			printf "%s\n" "Failed"
			exit_msg="EXIT: pre-update.sh failed with return code $?"
			echo $exit_msg | tee -a $LOGFILE
			exit $EXIT_FAIL_PRE_UPDATE
		fi
		printf "%s\n" "Done"						| tee -a $LOGFILE
	fi
	
	# Retrive available releases and set LOCAL_PATH, HTTP_PATH or FTP_PATH
	# variables
	retrieve_available_releases
		
	#Retrive current release
	retrieve_current_release
	
	if [ -z $requested_release ] ; then
		printf "\n%s\n" "Warning: New release ID was not provided," | tee -a $LOGFILE
		requested_release=${available_releases[${#available_releases[*]}-1]} 
		printf "%s\n" "taking the newest one - $requested_release" | tee -a $LOGFILE
	fi
	
	printf "%s" "Set result_flag  ... "
	result_flag=255
	echo $result_flag > $UPDATE_RESULT_FILE 
	printf "%s\n" "Done"
	
	
	# Update the environment pre-check	
	# update_pre_check

	# Store requested_id in global variable 
	get_release_id $requested_release
	requested_id=$?
	
	# Store current release
	get_release_id $current_release
	current_id=$?
	
	printf "%s\n" "Available releases: ${available_releases[*]}" 
	printf "%s\n" "requested_release=$requested_release"
	printf "%s\n" "requested_id=$requested_id"
	printf "%s\n" "current_release=$current_release"
	printf "%s\n" "current_id=$current_id"

	if [ $current_id -lt 255 ] ; then
		if [[ (! $current_id -lt $requested_id) ]] ; then
			printf "%s\n" "Warning:" | tee -a $LOGFILE
			echo "The release is already installed or newer than requested one" | tee -a $LOGFILE
			exit $EXIT_SUCCESS
		fi
		
	#else
		#exit_msg="EXIT: currently installed release is not found among provided releases"
		#echo $exit_msg | tee -a $LOGFILE
		#exit $EXIT_FAIL_NO_CURRENT_REL_FOUND 
	fi
	
	if [ $sequential_flag -eq 0 ] ; then
		
		# The global variable release is used in all other operations	
		release=$requested_release
		release_id=$requested_id
	
		# Update the environment pre-check	
		update_pre_check

		# Regenerating opkg configuration files
		regenerate_opkg_conf 

		#Start the update procedure
		initial_update_handler 
	else
	
		# If the get_release_id returns 255 value, it means that the
		# release was not found among the available_release table. This could  
		# also means that this is base release 	
		if [ ${current_id} -eq 255 ] ; then
			release_id=0
			release=${available_releases[$release_id]}
		else
			release_id=$(( current_id + 1 ))
			release=${available_releases[$release_id]}
		fi		
		
		
		# Perform sequential update until the requested one is reached
		while true ; do
			# Update the environment pre-check	
			update_pre_check

			# Regenerating opkg configuration files
			regenerate_opkg_conf 
		
			#Start the update procedure
			initial_update_handler 
		
			#Get a new value for the current_release variable
			retrieve_current_release
		
			get_release_id $current_release
			current_id=$?
		
			if [ "$release_id" -lt "$requested_id" ] ; then
				release_id=$(( release_id + 1 ))
				release=${available_releases[$release_id]}
			else
				break;
			fi
		done
	fi
	
	printf "%s" "Reset result_flag ... "
	result_flag=0
	echo $result_flag > $UPDATE_RESULT_FILE 
	printf "%s\n" "Done"
	
	printf "%s\n" "Rebooting the system to pick up the changes!" | tee -a $LOGFILE
	if [ $MACHINE = "dm365-htc" ] ; then
		# For HTC, we stop watchdog daemon and wait until it get's reboot
		# The watchdog period is 60 sec 
		/etc/init.d/watchdog stop
		sleep 60
	else
		#For all other machines it's just reboot command
		reboot
	fi
fi
