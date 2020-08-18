"""This script imports 1hr rinex files from remote server and merges them to 24hr files. 
The 1hr files are deleted remotely and stored locally in the saved folder. 
24hr files are uploaded to the remote location.
Unfinished days are saved in the unfinished folder in a local dir (hours2days/unfinished) given in the gorm.ini file.
Info on the remote host is given in the gorm.ini file
- Creates logfile (located as specified in logfile_path) and notes days where one or more hour files are missing
- Sends email to adress given in email_to
- Change host, password, user, remote path to cahnge source
- The script can either be run manually from the terminal or set up as a cron job.
Create folder structure: 
    hours2days
        saved (all 1hr files stored here in XXXX folders)
            XXXX (4 letter station name)
        unfinished (1hr files for unfinished days are stored here in XXXX folders)
            XXXX (4 letter station name)

The script is run by a cronjob
"""

from ftplib import FTP
from ftplib import all_errors
import datetime as dt
import subprocess
import re
import os
import logging
from logging.handlers import TimedRotatingFileHandler
from datetime import datetime
from pathlib import Path
import socket

import configparser


parser = configparser.ConfigParser()
parser.read(Path(__file__).resolve().parent / "../etc/gorm.ini")


port = parser.get("Leica connection", "port")
host = parser.get("Leica connection", "host")
password = parser.get("Leica connection", "password")
user = parser.get("Leica connection", "user")
remote_path = parser.get("setup", "remote_path")
email_to = parser.get("setup", "email_to")

foldername = parser.get("setup", "foldername")
path = parser.get("setup", "path")
path_to_files = path + foldername
logfilename = parser.get("setup", "logfilename")
logfile_path = path + logfilename

local_name = socket.gethostname()
local_host = parser.get("Local", "host")
local_user = parser.get("Local", "user")

last_filename = ""
os.system("mkdir -m777 -p %s" % (path_to_files))
list_of_files = []


logHandler = TimedRotatingFileHandler(logfile_path, when="W6")
logFormatter = logging.Formatter(
    "%(asctime)s %(filename)s: %(message)s", datefmt="%d-%b-%y %H:%M:%S"
)
logHandler.setFormatter(logFormatter)
logger = logging.getLogger("MyLogger")
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

newlog = False

# connet to remote server
ftp = FTP(host)
ftp.login(user, password)

# ftp.retrlines("LIST")

ftp.cwd(remote_path)

# ftp.retrlines("LIST")


current_year = str(dt.datetime.now().year)
doy = dt.datetime.today().timetuple().tm_yday
ftp.cwd(current_year)  # current year directory
# ftp.cwd("temp")
filelist = ftp.nlst()


def get_move(filename, path_to_files):
    # gets file from ftp server and place in folder
    fhandle = open(filename, "wb")
    ftp.retrbinary("RETR " + filename, fhandle.write)
    fhandle.close()
    os.system("mv %s %s" % (filename, path_to_files))
    # move hour files to saved folder
    stationname = filename[0:4]
    os.system(r"mkdir -m777 -p %s/saved/%s" % (path_to_files, stationname))
    os.system(
        r"cp %s/%s %s/saved/%s" % (path_to_files, filename, path_to_files, stationname)
    )
    os.system("gunzip %s/%s" % (path_to_files, filename))


def merge_upload(filename, path_to_files):
    station_doy = filename[0:-8]
    yr = filename[-6:-4]
    file_type = filename[11]
    # Merge files
    osstring = r"teqc -warn -phc %s/%s[a-xA-X]\.%s%s > %s/%s0\.%s%s" % (
        path_to_files,
        station_doy,
        yr,
        file_type,
        path_to_files,
        station_doy,
        yr,
        file_type,
    )
    os.system(osstring)
    if file_type == "o":
        os.system(r"rnx2crx %s/%s0\.%so" % (path_to_files, station_doy, yr))
        os.system(r"gzip %s/%s0\.%sd" % (path_to_files, station_doy, yr))
        file_type = "d"
    else:
        os.system(r"gzip %s/%s0\.%s%s" % (path_to_files, station_doy, yr, file_type))

    # upload merged file to remote
    f = open(path_to_files + "/" + station_doy + "0." + yr + file_type + ".gz", "rb")
    try:
        ftp.storbinary("STOR " + station_doy + "0." + yr + file_type + ".gz", f)
    except all_errors as e:
        errorcode_string = str(e).split(None, 1)[1]
        logger = logging.getLogger("MyLogger")
        logger.error("Upload to ftp.sdfe.dk failed: " + errorcode_string)
        global newlog
        newlog = True
        os.system(r"mkdir -m777 -p %s/saveddays" % (path_to_files))
        os.system(
            r"mv %s/%s0.%s%s.gz %s/saveddays"
            % (path_to_files, station_doy, yr, file_type, path_to_files,)
        )
    f.close


def unfinished_days(last_filename, path_to_files):
    # moves and zips unfinished days
    last_file_type = last_filename[11]
    last_yr = last_filename[-6:-4]
    last_station_doy = last_filename[0:-8]
    last_stationname = last_filename[0:4]
    global newlog
    newlog = True
    os.system(r"mkdir -m777 -p %s/unfinished/%s" % (path_to_files, last_stationname))
    os.system(
        r"mv %s/%s[a-xA-X]\.%s%s %s/unfinished/%s"
        % (
            path_to_files,
            last_station_doy,
            last_yr,
            last_file_type,
            path_to_files,
            last_stationname,
        )
    )
    os.system(
        r"gzip %s/unfinished/%s/%s[a-xA-X]\.%s%s"
        % (path_to_files, last_stationname, last_station_doy, last_yr, last_file_type,)
    )
    logger = logging.getLogger("MyLogger")
    logger.info(last_station_doy + " is unfinished")


def list_merge(list_of_files, path_to_files, doy):
    list_of_files.append("listender.000.gz") #add extra name to list, so last station/doy is included
    last_filename = ""
    doy_list = []
    for filename in list_of_files:
        if filename != list_of_files[-1]:
            get_move(filename, path_to_files)
        locationName = filename[0:-8]
        if (
            last_filename and last_filename[0:-8] == locationName
        ):  # same station and doy as last file
            doy_list.append(filename)
            if (
                re.match(r".*[xX]{1}\.[0-9]{2}[gno]\.gz$", filename)
                and len(doy_list) == 24
            ):  # last file of finished doy
                # merge files
                merge_upload(filename, path_to_files)
                # delete files locally
                os.system(
                    r"find  %s/%s[a-z]%s -maxdepth 1 -type f -delete"
                    % (path_to_files, filename[0:7], filename[8:12])
                )
        else:  # start new station/doy
            # detect and move unfinished days if not today
            if (
                last_filename[0:-8] != ""
                and len(doy_list) < 24
                and last_filename[4:7] != str(doy)
            ):
                unfinished_days(last_filename, path_to_files)
                os.system(
                    r"find  %s/%s[a-z]%s -maxdepth 1 -type f -delete"
                    % (path_to_files, last_filename[0:7], last_filename[8:12])
                )
            # delete last station and/or doy files from remote (if it is not this doy and unfinished)
            if not (len(doy_list) < 24 and last_filename[4:7] == str(doy)):
                for item in doy_list:
                    # delete files on remote
                    ftp.delete(item)

            doy_list = [filename]

        last_filename = filename

def main():

    obs_list = []
    GPS_list = []
    GLO_list = []
    for filename in filelist:
        if re.match(r".*[a-xA-X]{1}\.[0-9]{2}[gno]\.gz$", filename):
            file_type = filename[11]
            # get file
            # GetMove(filename, path_to_files)
            if file_type == "o":
                obs_list.append(filename)

            elif file_type == "n":
                GPS_list.append(filename)

            elif file_type == "g":
                GLO_list.append(filename)

    # merge obs hour files to days
    list_merge(obs_list, path_to_files, doy)

    # merge GPS nav hour files to days
    list_merge(GPS_list, path_to_files, doy)

    # merge GLONASS nav hour files to days
    list_merge(GLO_list, path_to_files, doy)

    # Delete files locally (possibly large number of files)
    # if still too many files, divide into further groups
    
    os.system(r"find  %s/[a-l]*[0-9][o] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[m-z]*[0-9][o] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[a-l]*[0-9][d] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[m-z]*[0-9][d] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[a-l]*[0-9][n] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[m-z]*[0-9][n] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[a-l]*[0-9][g] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(r"find  %s/[m-z]*[0-9][g] -maxdepth 1 -type f -delete" % (path_to_files))
    os.system(
        r"find  %s/[a-f]*[0-9][odgnP]\.gz -maxdepth 1 -type f -delete" % (path_to_files)
    )
    os.system(
        r"find  %s/[g-m]*[0-9][odgnP]\.gz -maxdepth 1 -type f -delete" % (path_to_files)
    )
    os.system(
        r"find  %s/[n-q]*[0-9][odgnP]\.gz -maxdepth 1 -type f -delete" % (path_to_files)
    )
    os.system(
        r"find  %s/[r-z]*[0-9][odgnP]\.gz -maxdepth 1 -type f -delete" % (path_to_files)
    )

    ftp.quit()

    # monitor disk usage
    batcmd = "df --total"
    dfresult = subprocess.check_output(batcmd, shell=True)
    disk_usage = re.findall(r"total\s.*$", dfresult)[0]
    disk_usage = disk_usage.split(" ")[-2]
    used_float = float(disk_usage.strip("%"))
    if used_float >= 80:
        logger.warning(local_name + " disk usage " + disk_usage)
        os.system(
            r"echo \"%s: disk usage on %s is %s\" | mail -s \"%s_disk_usage_warning\" -r %s@%s %s"
            % (__file__, local_name, local_name, local_user, local_host, disk_usage, email_to)
        )


    if newlog:
        os.system(
            r"mail  -s \"%s_warning\" -r %s@%s %s < %s"
            % (__file__, local_user, local_host, email_to, logfile_path)
        )

if __name__ == "__main__":
    # køres kun når scriptet kaldes fra kommandolinjen
    main()