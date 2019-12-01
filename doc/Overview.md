# System overview

Paths are defined in BaseConfig.pm as variables. Paths mentioned below
may be different.<br/>
gpspickup, jobengine and ftpuploader are running as daemons managed by systemd.

## Overall Dataflow
- gpspickup detect new file in /data/ftp (FTP server inbound)
  - unpack zip/gz/raw into workdir
  - create job in /data/queue
  - return to listen
- jobengine detect now job in /data/queue
  - if job is a command
    - do commmand and return to listen
  - read job and spawn a process (Job.pm)
  - if hourly file and day is complete
    - create day files
    - create day job in /data/queue
  - return to listen
- Job.pm workdir (child process)
  - rewrite RINEX headers
  - create required intervals
  - Gapanalyze
  - QC
  - copy to /data/upload
  - if daily file
    - remove workdir
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
  Interface to the MariaDB on local

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
### /data/ftp
  Home directory for vsFTPd.
  This is where inbound data arrives.
  Monitored by gpspickup

### /data/work
  Temporary files. All processing happens here.

### /data/queue
  Job spool directory.
  Monitored by jobengine.

### /data/upload
  ftpuploader home directory
  Subdirectories monitored by ftpuploader (configured in DB)
