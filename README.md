# GORM
GNSS Operations, Register and Monitoring system

Theese scripts are used for receiving, process and distribute RINEXv3
data files received from Permanent GNSS Stations.
Developed on CentOS 7, but should run RHEL 7. RHEL 8 is not quite supported yet, as some of
the perl packages are unavailable for RHEL 8.

Currently support Leica, Trimbple and Septentrio data.

## Overall Dataflow
- gpspickup detect new file in /data/ftp (FTP server inbound)
  - unpack zip/gz into workdir
  - create job in /data/queue
- jobengine detect now job in /data/queue
  - read job and spawn a process (Job.pm)
  - if hourly file and day is complete
    - create day files
    - create day job in /data/queue
- Job.pm workdir
  - rewrite RINEX headers
  - create required intervals
  - Gapanalyze
  - QC
  - copy to /data/upload
  - if daily file
    - remove workdir
- ftpuploader
  - spawn a process per destination
  - wait for all childs, reload config periodically
  - ftpuploader childs
    - ftpupload detect new file(s) in /data/upload
    - upload file to destination(s) using either ftp og sftp

## Components
### vsftpd
  FTP server receiving files from GNSS stations.
  Data arrives in /data/ftp

### gpspickup
  Monitors /data/ftp for new files.
  When a new file arrives, gpspickup unpacks zip or gz into workdir
  and creates a jobfile in /data/queue. The files are renamed
  to conform to RINEXv3 name standard.

### jobengine
  Monitors /data/queue
  A simple process manager ensuring not too many jobs are running in parallel. Max currently 4.
  jobengine creates a Job object (Job.pm) for the job.

### Job.pm
  This is the main program containing all the conversions to be done
  on RINEX files.

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

### /home/gpsuser
  The script home directory

### /data/upload
  ftpuploader home directory
  Subdirectories monitored by ftpuploader (configured in DB)

## Author
Soren Juul Moller, Nov 2019
