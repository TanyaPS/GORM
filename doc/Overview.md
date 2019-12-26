# System overview

Paths are defined in BaseConfig.pm as variables. Paths mentioned below
may be different.<br/>
gpspickup, jobengine and ftpuploader are running as daemons managed by systemd.

## Overall Dataflow
- gpspickup detect new file in /data/ftp (FTP server inbound)
  - unpack zip/gz/raw into workdir/unpack.$h
  - move all files in workdir/unpack.$h to workdir if state allows it
  - create job in /data/queue
  - return to listen
- jobengine detect now job in /data/queue
  - if job is a command
    - do commmand and return to listen
  - read job and spawn a process (Job.pm)
  - return to listen
- Job.pm workdir (child process)
  - if hour2daily job
    - create day from hours and continue as a daily file
  - rewrite RINEX headers
  - create required intervals
  - Gapanalyze
  - QC
  - copy to /data/upload (distribute)
  - if daily file
    - remove workdir
    - exit
  - if hourly file
    - if day is complete
      - submit hour2daily job
  - exit
- ftpuploader
  - spawn a process per destination
  - wait for all childs, reload config periodically
  - ftpuploader childs
    - ftpupload detect new file(s) in /data/upload
    - upload file to destination(s) using either ftp og sftp
    - return to listen

## Components
gpspickup, jobengine and ftpuploader are installed in /usr/local/sbin.
All .pm are installed in /usr/lccal/lib/gnss.
Utilities and binaries are installed in /usr/local/bin.

### gpspickup
  Monitors /data/ftp for new files.
  When a new file arrives, gpspickup unpacks file(s) into workdir
  and creates a jobfile in /data/queue. The files are renamed
  to conform to RINEXv3 name standard.

### jobengine
  Monitors /data/queue
  A simple process manager ensuring not too many jobs are running in parallel. Max currently 4.
  jobengine creates a Job object (Job.pm) for the job.
  Job files named "command" are custom commands to be executed by jobengine.

### Job.pm
  This is the main program containing all the conversions to be done
  on RINEX files, both 1 hour and 1 day file sets.

### RinexSet.pm
  Each hour and day consists of multiple files, observations and navigation data.
  Files belonging to same hour/day is represented by a RinexSet object.
  RinexSet handles the naming of files as well.

### ftpuploader
  Monitors /data/upload
  Upload files to final destinations. That can be other FTP servers, SFTP servers
  or local directories (NFS mounts).

### BaseConfig.pm
  Global variables - mostly file paths

### GPSDB.pm
  Interface to the MariaDB.

### Utils.pm
  Utility functions used in all modules

### cgi/status.cgi
  Web page show the current status of processing.<br/>
  Installed in /var/www/gnss-cgi and accessed by http://host/status.cgi

### cgi/admin.cgi
  Administration of runtime configuration in the database.<br/>
  Installed in /var/www/gnss-cgi and accessed by http://host/admin.cgi.<br/>
  Requires username and password which is defined in /usr/local/etc/gnss-admin.psw (htpasswd file).

### /usr/local/etc/gorm.conf
  Overrides default global constants defined in BaseConfig.pm

## Paths
Override defaults by modifing /usr/local/etc/gorm.conf.

### $INCOMING
  Defaults to /data/ftp.<br/>
  Home directory for vsFTPd. This is where inbound data arrives. Monitored by gpspickup

### $WORKDIR
  Defaults to /data/work.<br/>
  Temporary files. All processing happens here.

### $JOBQUEUE
  Default: /data/queue<br/>
  Job spool directory. Monitored by jobengine.

### $SAVEDIR
  Default: /data/saved<br/>
  All files arriving in $INCOMING will be move to here. If it is a known site,
  the files will be moved to $SAVEDIR/sitename. If it an unknown file type,
  it will be moved to $SAVEDIR/stale ($STALEDIR).<br/>
  Files will be removed from $SAVEDIR when they become older than 60 days.

### ftpuploader
  ftpuploader do not have a specific home dir or paths. It is configured in DB.

## Global variables
Override defaults by modifying /usr/local/etc/gorm.conf.

### $JOBINSTANCES
  The number of processors.<br/>
  jobengine and gpspickup will start this number of processors. Set to 2 x number of CPU's.

### $ANUBIS, $BNC, $GFZRNX, $RNX2CRX, $CRX2RNX, $SBF2BIN
  The full path names of external programs needed by these scripts. See INSTALL.

### $SYSLOG_FACILITY
  The syslog(3) facility name to use. Default is local1.
