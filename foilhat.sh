#!/bin/bash

###################################################################################
# Copyright (c) 2012-2015 Mark Casey
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


# Foilhat v2 - A semi-paranoid cron job wrapper that handles job locking/PID, improved output control, and verification of required mount points.


set -e
set -u
set -o pipefail

# Job that will be wrapped
JOB="$1"
FULLCMD="$@"

# Temp storage of job's output
FH_OUT="/tmp/foilhat.out.$$"
FH_ERR="/tmp/foilhat.err.$$"

LCK_FILE="/tmp/$(basename ${JOB})${FH_LCK_APPEND:-}.foilhat.lck"

JOB_STARTED_AT=$(date)



##############################
#  -Define functions-
##############################

function write_lock_file {
# Writes and verifies the job's lock file

	set +e; echo $$ 2>/dev/null > "${LCK_FILE}"; R=$?; set -e
	#R=1  # Debug
	if [ "${R}" != 0 ]
	then
		echo -e "\n--foilhat.sh-- Exiting on error: Could not write to lock file ["${LCK_FILE}"]." >&2
		exit 1
	fi
	
	# Block race conditions and verify lock obtained
	chmod -w "${LCK_FILE}"
	chattr +i "${LCK_FILE}"
	read -r PID_AS_READ < "${LCK_FILE}"
	#PID_AS_READ=-999  # Debug
	if [ "${PID_AS_READ}" -ne $$ ]
	then
		echo -e "\n--foilhat.sh-- Exiting on error: PID in (supposedly) new lock file does not match the PID of the job." >&2
		echo "--foilhat.sh-- The full command that WOULD have been run is: ${FULLCMD}" >&2
		echo "--foilhat.sh-- Current PID [$$] != PID in lock file '"${LCK_FILE}"' ["${PID_AS_READ}"]." >&2
		exit 1
	fi

}



function obtain_lock {
# Verifies no prior job instance is still active, then calls 'write_lock_file'

	if [ -f "${LCK_FILE}" ]
	then
		echo -e "\n--foilhat.sh-- Warning: A prior lock file exists for the job (\""${JOB}"\"); reading last known PID..." >&2
		
		LCK_FILE_LINE_COUNT=$(wc -l <"${LCK_FILE}")
		#LCK_FILE_LINE_COUNT=0  # Debug
		if [ "${LCK_FILE_LINE_COUNT}" -eq 0 -o "${LCK_FILE_LINE_COUNT}" -gt 1 -o $(stat -c%s "${LCK_FILE}") -gt 20 ]
		then
			echo "--foilhat.sh-- Exiting on error: Prior lock file exists but is either empty or contains too much data." >&2
			exit 1
		fi
		
		read -r LAST_PID < "${LCK_FILE}"
		set +e; CHECK_WITH_PS=$(ps -fp "${LAST_PID}"); R=$?; set -e
		#R=0  # Debug
		if [ "${R}" != 0 ]
		then
			echo "--foilhat.sh-- OK!: The last instance of foilhat that ran the job (\""${JOB}"\") is not running under its last known PID ["${LAST_PID}"]" >&2
			echo "--foilhat.sh-- Continuing as normal..." >&2
			
			# The next two lines are the ONLY ones in this script that can clear the lock file
			# during an error state that actually *involves* the lock file.
			chattr -i "${LCK_FILE}"
			rm -f "${LCK_FILE}"
			
			write_lock_file
			
		else
			echo "--foilhat.sh-- Exiting on error: A prior foilhat instance for the job (\""${JOB}"\") is already/still running as ["${LAST_PID}"] based on:" >&2
			echo "${CHECK_WITH_PS}" >&2
			exit 1
		fi
	else
		write_lock_file
	fi

}

function mount_check {
# NOT called in foilhat.sh; exported to job's environment. Used by job to verify required mount points on this host or on remote hosts
# See sample job scripts and documentation for use examples (function *should* be callable from binaries/other script languages using their system() call too!).
# Use is recommended, but not required

INPUT=("${@}")
ALL_FOUND='true'  # Default to "all is well" prior to looking for problems below

if [ -z "${FH_MOUNT_CHECK_CALLER:-}" ]
# Set where errors come from (some non-bash jobs like perl scripts can pre-set this before calling mount_check, so their own name will show instead of just 'bash')
# Not an issue for bash jobs, as mount_check is exported to and called by the job, using its own "basename ${0}"
then
	FH_MOUNT_CHECK_CALLER=$(basename ${0})	# Set the default, if not otherwise set
fi

for LINE in "${INPUT[@]}"
do
	MOUNT_NEEDED=''
	HOST=''
	PORT='22'
	KEY=''
	VERBOSE=''
	
	OPTIND=1
	LINE_AS_ARRAY=(${LINE})
	
	# Get arguments
	while getopts ":m:h:p:k:v" opt "${LINE_AS_ARRAY[@]}"
	do
		case ${opt} in
		m)
			MOUNT_NEEDED="${OPTARG}"
			;;
		h)
			HOST="${OPTARG}"
			;;
		p)
			PORT="${OPTARG}"
			;;
		k)
			KEY="${OPTARG}"
			;;
		v)
			VERBOSE='true'
			;;
		\?)
			echo "--mount_check()-- Invalid option: -$OPTARG" >&2
			#exit 1
			;;
		:)
			echo "--mount_check()-- Option -$OPTARG requires an argument." >&2
			#exit 1
			;;
		esac
	done
	
	if [ "${VERBOSE:-}" == 'true' -o -z "${MOUNT_NEEDED:-}" ]
	then
		echo >&2
		echo "Checking mount string: ${LINE}" >&2
		if [ -n "${MOUNT_NEEDED:-}" ]; then echo "    MOUNT: ${MOUNT_NEEDED}" >&2; fi
		if [ -n "${HOST:-}" ]; then echo "    HOST: ${HOST}" >&2; fi
		echo "    PORT: ${PORT} (Will always equal 22 if not set otherwise)" >&2
		if [ -n "${KEY:-}" ]; then echo "    KEY: ${KEY}" >&2; fi
		if [ -n "${VERBOSE:-}" ]; then echo "    VERBOSE: ${VERBOSE}" >&2; fi
		
		if [ -z "${MOUNT_NEEDED:-}" ]
		then
			echo >&2
			echo "--mount_check()-- Exiting on error: mount_check() requires at least a mount point parameter." >&2
			exit 1
		fi
	fi
	
	# Check for mount
	FOUND='false'
	
	MOUNT_NEEDED="${MOUNT_NEEDED} type "  # This makes our parameter look like $(mount)'s output formatting; reduces false positives
	
	# If local
	if [ -z "${HOST:-}" -o "${HOST:-}" == 'local' ]
	then
		IFS=$'\n\b'  # Don't wordsplit on space
		for MOUNTS in $(mount)
		do
			if [[ "${MOUNTS}" == *"${MOUNT_NEEDED}"* ]]
			then
				FOUND=true
			fi
		done
		
		if [ "${FOUND}" == 'false' ]
		then
			ALL_FOUND='false'
		fi

	# Else remote
	else
		CMD_TMP='ssh'  # Begin prep of remote query
		
		if [ -n "${PORT:-}" ]
		then
			CMD_TMP="${CMD_TMP} -p ${PORT}"
		fi
		
		if [ -n "${KEY:-}" ]
		then
			CMD_TMP="${CMD_TMP} -i ${KEY}"
		fi
		
		if [ -n "${HOST:-}" ]
		then
			CMD_TMP="${CMD_TMP} ${HOST}"
		fi
		
		CMD_TMP="${CMD_TMP} 'mount'"  # Query ready
		
		CMD_TMP=( ${CMD_TMP} )  # Convert to array to avoid an 'evil use of eval' later
		
		IFS=$'\n\b'  # Don't wordsplit on space
		for MOUNTS in $("${CMD_TMP[@]}")
		do
			if [[ "${MOUNTS}" == *"${MOUNT_NEEDED}"* ]]
			then
				FOUND=true
			fi
		done
		
		if [ "${FOUND}" == false ]
		then
			ALL_FOUND='false'
		fi
	fi
	
	if [ "${VERBOSE:-}" == 'true' ]
	then
		echo "    FOUND?: ${FOUND}" >&2
		echo >&2
	fi
	
	# A mount came up missing; give up early
	if [ "${ALL_FOUND}" == 'false' ]
	then
		echo >&2
		echo "--${FH_MOUNT_CHECK_CALLER}-- Exiting on error: Failed to verify mount point. (failed to find line: ${LINE})" >&2
		echo >&2
		exit 1
	fi

	unset IFS	
done

}
export -f mount_check



##############################
#  -Begin main block-
##############################

# Don't run if we aren't root
if [ $(id -u) -ne 0 ]; then
	echo -e "\n--foilhat.sh-- Exiting on error: Sorry, you are not root." >&2
	exit 1
fi

obtain_lock

# Run job; capture outputs and exit status
set +e
eval ${FULLCMD} >$FH_OUT 2>$FH_ERR
RESULT=$?
set -e

JOB_ENDED_AT=$(date)

# Calculate job duration (get time in seconds, divide out number of days, mod off leftover seconds...ditto with hours/minutes)
SECONDS=$(( $(date --date "${JOB_ENDED_AT}" +%s) - $(date --date "${JOB_STARTED_AT}" +%s) ))
DAYS=$((SECONDS / 86400)); SECONDS=$((SECONDS % 86400))
HOURS=$((SECONDS / 3600)); SECONDS=$((SECONDS % 3600))
MINUTES=$((SECONDS / 60))
SECONDS=$((SECONDS % 60))
DURATION="${DAYS} days, ${HOURS} hours, ${MINUTES} minutes, ${SECONDS} seconds"

# Disable STDOUT if no failures or errors
if [ $RESULT -eq 0 -a ! -s "$FH_ERR" ]
then
	exec > /dev/null
fi

# Check whether the job placed an outopts file
FH_OUTOPTS="/tmp/foilhat.outopts.$$"

if [ -r "${FH_OUTOPTS}" ]
then
	source "${FH_OUTOPTS}"

	if [ "${OUT_TO_LOG:-}" == 'true' -a -n "${LOGFILE:-}" ]
	then
		if [ "${OVERWRITE_LOG:-}" == 'true' ]
		then
			exec > >(tee "${LOGFILE}")
		else
			exec > >(tee -a "${LOGFILE}")
		fi
	fi
fi


# Write output
echo "Foilhat report for job:"
echo "${FULLCMD}"
echo
echo "Exit Status: ${RESULT}"
echo "Start time: ${JOB_STARTED_AT}"
echo "End time: ${JOB_ENDED_AT}"
echo "Duration: ${DURATION}"
echo
echo "STDERR:"
echo "-----------------"
cat "${FH_ERR}" | sed 's/^/   /'
echo "-----------------"
echo
echo
echo "STDOUT:"
echo "-----------------"
cat "${FH_OUT}" | sed 's/^/   /'
echo "-----------------"
echo
echo "===END FOILHAT REPORT $(date)==="
echo

rm -f "${FH_OUT}"
rm -f "${FH_ERR}"
rm -f "${FH_OUTOPTS}" || true  # Might not exist

chattr -i "${LCK_FILE}"
rm -f "${LCK_FILE}"


