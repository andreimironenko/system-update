#!/bin/sh

#TODO: Implement a proper init script with start/stop/restart commands!

ps | grep bash | grep update_trigger.sh 

if [ $? -eq 0 ] ; then
    printf "%s\n" "Another instance of update_trigger.sh is already running!"
	pid=`ps | grep bash | grep update_trigger.sh`
	pid=${pid:0:6}                                                     
	kill -s SIGKILL ${pid}                       
fi

printf "%s\n" "Start a new background update_trigger.sh process" 
 nohup /bin/bash /usr/share/scripts/update_trigger.sh  >/dev/null &

exit 0
