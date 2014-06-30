Foilhat, a semi-paranoid cronjob wrapper.

**Warning**: By design, Foilhat gives no output whatsoever under normal
operation. You are asking to lose cronjob log data if you fail to at
least read the "Output Control and Logging" section below prior to use.


## Summary

Foilhat v2.0 offers three main features for handling cron jobs, along with a
few minor extras. The main features are:
 - Output control
 - Local and remote mount point checking
 - PID/lock fle handling

Foilhat aims to handle these relatively simple tasks in a low maintenace,
centralized manner and has been found to add quite a bit of power, safety,
and flexibility to everyday job handling.


## General Use

Call foilhat.sh in front of your existing script or command, like in these examples:

    /usr/local/sbin/foilhat.sh /usr/local/sbin/example_job1.sh
    
    /usr/local/sbin/foilhat.sh /usr/local/sbin/somescript.sh
    
    /usr/local/sbin/foilhat.sh /some/path/someperl.pl
    
    /usr/local/sbin/foilhat.sh /some/path/custom_binary

OR (though not recommended) if you find a situation that warrants it you could
just run an arbitrary command as a job:

    /full/path/to/foilhat.sh tar -czvpf foo.tgz bar

BUT be mindful of the lock with such "generic" commands (simply '/tmp/tar.foilhat.lck'
in this case). You could not call tar via foilhat.sh a second time until the first
instance had finished.

You should NOT just run multiple commands in-line. For one it negates most of
Foilhat's purpose but also, quoting multiple commands together will break the
lock-file generation and Foilhat will simply exit:

    ./foilhat.sh "touch foo; ls -la foo >&2; rm foo"

Dropping the quotes and escaping instead (although technically functional) is an abomination:

    ./foilhat.sh touch foo\; ls -la foo \>\&2\; rm foo


## Output Control and Logging

Under normal operation Foilhat gives no output whatsoever (meaning cron will not email).
This is so that whoever receives cron's emails does not get countless daily emails
saying 'Job foo went great'. When this happens people may stop paying attention and
when cron finally does send an email with strange output, sometimes no one will see it
through the onslaught of 'Way to go job foo!'

Instead, Foilhat starts a job and then accumulates its stdout and stderr within files
in /tmp. When the job is done Foilhat simply discards these files unless any or all of
the following things has occurred:

    1. The job printed to its stderr
    2. The job's exit status was non-zero
    3. The job was coded to "request" Foilhat's report be written or appended to a log file.

If either of the first or second events occur Foilhat will print a report (to its stdout)
on all of the job's outputs (which will then end up in email). If the third event occurs
Foilhat will write or append it's report to the log file specified. These two output
methods do not interact: If a log is "requested" it will be written regardless of whether
an email event occurs. Likewise, "requesting" a log will not change the rules on when
you get emails. So one, both, or neither may occur for a given job.

Some current software (ex.: rsnapshot) does not allow full logging of its output. This
is likely due to stdio's output buffering, which affects stdout when disconnected from a
terminal but does not affect stderr. The result is such that if both outputs are being
sent to a file, any stderr lines will appear in the file interleaved differently than
the original cronological order. Although there are good tools to combat this in newer
Linux distributions ('stdbuf') and some relatively bloated ways in older ones ('unbuffer',
available with 'expect'), their use is still more the exception than the rule.

This is not as big of an issue when cron is emailing you all output, but it does become
an issue when Foilhat is added and successful jobs start passing silently in the night.
Suddenly there is no record to refer to in cases such as "I accidentally deleted
foo.dat some time in the last 6 months." For this reason, Foilhat supports writing or
appending its job output report to a log file after every run, regardless of job
outcome. To enable this option, simply execute something similar to the Bash code
below before starting work in your script:
```
#!/bin/bash

set -e
set -u
set -o pipefail

## Set output options for Foilhat to retrieve
FH_OUTOPTS=/tmp/foilhat.outopts.$PPID
echo 'OUT_TO_LOG="true"' > "${FH_OUTOPTS}"
echo 'OVERWRITE_LOG="false"' >> "${FH_OUTOPTS}"
echo 'LOGFILE="/var/log/logfile.log"' >> "${FH_OUTOPTS}"

###########################################
########## End pre-script config ##########
###########################################

# start of your script #
```

Once your job has completed, Foilhat will check for the existence of the FH_OUTOPTS
file and will act as requested if it is found. The file does not have to be output by
any certain language or method, of course. If you are wrapping a perl job or a
custom binary or etc., you can write the file from there. Note that the log file will
not be overwritten unless APPEND_TO_LOG is false and OVERWRITE_LOG is true; setting
only one or the other (or neither) will result in an append to the current log. Also
note that the FH_OUTOPTS filename should end with Foilhat's PID ($PPID), not your
script's PID ($$).

Logging options are set from within each job so that foilhat.sh needn't be modified
to allow different jobs to use different settings, and jobs can be moved around as
needed without first adding and/or removing their logging preferences in a central
config file(s).


## Locking

Foilhat will set a lock file for your job that is not likely to conflict with any
lock file the job might be configured to set on its own. You do not have to enable,
disable, or reconfigure the job's own default locking options to add Foilhat to
the mix (or to remove it), since the lock layers will be fully independent.
Foilhat's locking functions include several checks for sanity and should not be
susceptible to race conditions (barring considerable and intentional tampering
from root while the job is running).


## Mount checking

Foilhat exports a function to jobs that they can (optionally) use to make sure that
the filesystems they expect to be mounted are really there. This is intended to
prevent things like starting an empty mount point directory into your backups, or
filling up the parent volume if a large backup volume becomes unmounted.

The example below shows checking both a local mount and a remote mount. Adding
similar lines above your job's work section will check the mounts you specify
and exit with an error if they are not present.

```
#!/bin/bash

set -e
set -u
set -o pipefail

REQ_MOUNTS[0]="-m /mnt/bkusb500g"
REQ_MOUNTS[1]="-m /mnt/data -h usr@host.domain.com -p 22 -k ~/.ssh/key"
mount_check "${REQ_MOUNTS[@]}"

###########################################
########## End pre-script config ##########
###########################################

# start work #
```

Foilhat should export the mount_check function to the job's environment regardless
of language, similar to how the FH_OUTOPTS file can be set by any language. If
you want to utilize mount_check from your binary, perl script, or etc., try using
your language's system call command to set the mount list and execute mount_check
before starting work.

Here is a perl example. *Note that unlike the more integrated Bash example above,
here you must check the exit status and act accordingly*:

```
#!/usr/bin/perl

use warnings;
use strict;

my @req_mounts = ( '"-m /mnt/bkusb500g"',
                   '"-m /mnt/data -h usr@host.domain.com -p 22 -k ~/.ssh/key.key"' );

# (We pre-set FH_MOUNT_CHECK_CALLER, or any errors will just start
# with --bash-- instead of --/path/script.pl--)
if ( system("bash", "-c", "FH_MOUNT_CHECK_CALLER=$0; mount_check @req_mounts") != 0 )
{
        exit 1;
}

###########################################
########## End pre-script config ##########
###########################################

# start work #
```

## Other

There are some other minor beneficial things you can do that may not be
immediately obvious.

1. If you want to use Foilhat's mount checking and logging but still want a
   job to be portable you can wrap the pre-script config in a conditional
   that checks whether the mount_check function is defined, such as:

```
if [ $(type -t mount_check) ]
then
    ## Set mount points to look for
    REQ_MOUNTS[0]="-m /mnt/bkusb500g"
    REQ_MOUNTS[1]="-m /mnt/data -h usr@host.domain.com -p 22 -k ~/.ssh/key.key"
    mount_check "${REQ_MOUNTS[@]}"

    ## Set output options for Foilhat to retrieve
    FH_OUTOPTS=/tmp/foilhat.outopts.$PPID
    echo 'OUT_TO_LOG="true"' > "${FH_OUTOPTS}"
    echo 'OVERWRITE_LOG="false"' >> "${FH_OUTOPTS}"
    echo 'LOGFILE="/var/log/logfile.log"' >> "${FH_OUTOPTS}"

    ###########################################
    ########## End pre-script config ##########
    ###########################################
fi

# start work #
```

2. Usually you can't monitor a cron job until its output is emailed to you (to tell you nothing is wrong, no doubt). Sometimes
you just want to know how complete a job is or that it is still working. Jobs run by Foilhat can be monitored as long as
you can find the PID of the parent Foilhat instance. ('tail -f /tmp/foilhat.out.1234' or 'tail -f /tmp/foilhat.err.1234')

3. Because Foilhat is accumulating the job's output for you and the job can programatically determine the PID of its parent,
jobs wrapped by Foilhat have the benefit of making decisions based on what they've output so far. For example:

```
###########################################
########## End pre-script config ##########
###########################################

set +e
rsync -av --delete data backup
set -e

# Now look at STDOUT (via Foilhat's tmp filehandle) and generate
# a warning if too many files have been deleted/moved.
FH_OUT="/tmp/foilhat.out.${PPID}"

WARN_AT=85
set +e
DEL_COUNT=$( grep -c ^deleting "${FH_OUT}" )
set -e

if [ ${DEL_COUNT} -gt ${WARN_AT} ]
then
    echo -e "\nWARNING: This job has deleted or moved "${DEL_COUNT}" \
    files which is more than your threshold of "${WARN_AT}". The activity \
    is shown below:\n" >&2
fi
```

Just be sure when doing something like this that you do not get in a loop where your
job indefinitely prints responses to its own output. As before, you could also wrap a
trick like this in an if statement based on whether mount_check is present, though
there is likely a point at which the added code and clutter will cease to be worth the
extra portability.
