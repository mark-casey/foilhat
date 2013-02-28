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


# This "backup job" prints output to simulate an rsync call, and then sets a random number for how many files were supposedly deleted or moved.
# The rest of the job checks this value against a warning threshold and prints to stderr if the value is too high.
# The intent is to alert if a user deletes tons of files, or (for big shares) moves more files around than your backups might keep up with.

# The method used to retrieve the output is discussed more in the "-<< Other >>-" section at the end of Foilhat's documentation.

# NOTE: Since this is only an example job, most of the logging and mount_check lines are commented out.
#	However, it does run a mount_check on '/' for show, since that should always be there (and if not the job will just exit early).



set -e
set -u
set -o pipefail

if [ $(type -t mount_check) ]
then
	## Set mount points to look for
	REQ_MOUNTS[0]="-m /"
	#REQ_MOUNTS[0]="-m /mnt/storage"
	#REQ_MOUNTS[1]="-m /mnt/backups -h user@host.domain.com -p 22 -k /root/.ssh/access.key" 
	
	mount_check "${REQ_MOUNTS[@]}"
	
	## Set output options for Foilhat to retrieve
	#FH_OUTOPTS=/tmp/foilhat.outopts.$PPID
	#echo 'OUT_TO_LOG="true"' > "${FH_OUTOPTS}"
	#echo 'OVERWRITE_LOG="false"' >> "${FH_OUTOPTS}"
	#echo 'LOGFILE="/var/log/backup.log"' >> "${FH_OUTOPTS}"
fi

###########################################
########## End pre-script config ##########
###########################################



# Simulate a backup's output; throw errors every now and then
set +e
#rsync -av --delete /mnt/storage/share1 /mnt/backups/

echo "This is some output like rsync would have printed to stdout."
echo "deleting /path/to/a/deleted/file"
echo "deleting /path/to/a/file/oldname"
sleep 1
echo "/path/to/a/file/newname"
sleep 1
if [ $(($RANDOM%10)) -gt 7 ]; then echo "file has vanished: '/path/to/some/other/file'" >&2; else echo "/path/to/some/other/file"; fi
sleep 1
echo "done. lots of numbers would be here."

# Set how many files were supposedly deleted or moved by rsync (0 to 99)
SUPPOSEDLY_DELETED=$(($RANDOM%100))
set -e



# Look at STDOUT (via Foilhat's tmp filehandle) and generate a warning if too many files have been "deleted/moved."
FH_OUT="/tmp/foilhat.out.${PPID}"

WARN_AT=70
set +e
#DEL_COUNT=$( grep -c ^deleting "${FH_OUT}" )
DEL_COUNT=$SUPPOSEDLY_DELETED
set -e

if [ ${DEL_COUNT} -gt ${WARN_AT} ]
then
        echo -e "\nWARNING: This job has deleted or moved "${DEL_COUNT}" files which is more than your threshold of "${WARN_AT}" files as specified in JOB_NAME.sh. The activity is shown below:\n" >&2
fi

