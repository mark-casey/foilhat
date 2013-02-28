#!/bin/bash

###################################################################################
# Copyright (c) 2012, Mark Casey
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###################################################################################


# The less than reliable cron job. This tounge in cheek job just prints that is it done, unless a number of excuses kick in.
# Sometimes it gets tired and just takes longer than usual. The job is intended to show where different types of events and output go.

# NOTE: Since this is only an example job, most of the logging and mount_check lines are commented out.
#	However, it does run a verbose mount_check on '/' for show, since that should always be there (and if not the job will just exit early).



set -e
set -u
set -o pipefail

if [ $(type -t mount_check) ]
then
	## Set mount points to look for
	REQ_MOUNTS[0]="-v -m /"
	#REQ_MOUNTS[0]="-m /mnt/storage"
	#REQ_MOUNTS[1]="-m /mnt/backups -h user@host.domain.com -p 22 -k /root/.ssh/access.key" 
	
	mount_check "${REQ_MOUNTS[@]}"
	
	## Set output options for Foilhat to retrieve
	#FH_OUTOPTS=/tmp/foilhat.outopts.$PPID
	#echo 'OUT_TO_LOG="true"' > "${FH_OUTOPTS}"
	#echo 'OVERWRITE_LOG="false"' >> "${FH_OUTOPTS}"
	#echo 'LOGFILE="/var/log/dayjob.log"' >> "${FH_OUTOPTS}"
fi

###########################################
########## End pre-script config ##########
###########################################



declare -i HOW_TIRED
declare -i SECOND
SECOND=$(date '+3600*10#%H+60*10#%M')  # current minute of day, in seconds

if [ $((${RANDOM}%100)) -gt 75 ]
then
	echo "Error: Job is home sick." >&2
	exit 1

elif [ ${SECOND} -lt 28800 -o ${SECOND} -gt 300000 ]
then
	echo "Error: Undefined variable: overtime. Try again 8am-5pm." >&2
	exit 1

elif [ $((${RANDOM}%5)) -gt 2 ]
then
	HOW_TIRED=$((${RANDOM}%3+2))
	echo "Warning: +${HOW_TIRED} restlessness." >&2
fi

# Max execution time should be 12 seconds
sleep $(((${RANDOM}%3+1)*${HOW_TIRED:-1}))
echo "Less than reliable job completed."


