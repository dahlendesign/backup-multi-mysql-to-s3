#! /bin/sh

set -e

i=1
use_cron=0
while [ "$i" -le "${NUMBER_OF_JOBS}" ]; do
	eval USE_SCHEDULE=\$SCHEDULE_$i
	
	if [ "${USE_SCHEDULE}" = "**None**" ]; then
	  echo "Job $i run directly"
	  sh backup.sh $i
	else
		echo "Job $i added to cron"
		(crontab -l ; echo "$USE_SCHEDULE	/bin/sh /backup.sh $i") | crontab -
		use_cron=1
	fi
	
	i=$(( i + 1 ))
done

if [ $use_cron == 1 ]; then
	# run cron daemon in foreground
	# if no cron jobs, the container will stop (no need to keep running)
	crond -f
fi