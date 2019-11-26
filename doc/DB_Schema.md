# GPSFTP5 Database Schema

## Generel
Database variant: MariaDB
Database name: gps
User: gpsuser/gpsuser

## Recurring fields
### id
Internal id. Will automatically be filled if left blank. Must be unique.
### site
9 letter sitename. Ex BUDD00DNK, ARGI00FRO, ...
### year
4 digit year of observation.
### doy
Day of year
### hour
Letter representation of the observation hour.
'a' is UTC hour 0, 'x' is UTC hour 23. '0' is the whole day.
### jday
Julian day.

## antennas
This contains all antennas for all stations.
### id, site
See recurring fields.
### anttype
Antenna product name. Ex "LEIAT504GG,LEIS".
The comma in the name will be replaced with blanks so the left word is left justified
and the right word is right justified in a 20ch value. Ex
LEIAT504GG,LEIS -> LEIAT504GG     LEIS
### antsn
Antenna serial number.
### antdelta
Antenna height, east and north eccentricity seperated by commas. Ex 0.244,0,0
### startdate
The date and time of start of usage. Should match the previous enddate.
Ex: 2017-09-16 07:00:00
### enddate
The date and time of end of usage or NULL if still in use.
Ex: 2017-09-16 07:00:00

## datagaps
Records of missing observations (gaps) in observation files. **No manual editing needed.**
Maintained by Job.pm.
### id, site, year, doy, hour, jday
See recurring fields.
### gapno
Gap sequence number within the hour/day.
### gapstart
Date and time of start of the gap.
### gapend
Date and time of end of the gap.

## gpssums
QC results for each observation file.
Also used for checking if the file is processed already. If reprocessing needed, then
the records for that particular day and hours must be deleted before reprocessing.
### id, site, year, doy, hour, jday
### quality
The QC result.
### ngaps
Number of gaps in the hourly/daily observation file.
### ts
Timestamp of the record. Used for QC status viewer to detect when a site is late
on reporting in.

## localdirs
The name and physical location of an directory containing files to be uploaded.
### name
The label name for this directory.
This is a foreign key in ''uploaddest'' (localdir) and ''rinexdist'' (localdir).
### path
The full path for the directory.

## locations
All the sites.
### site
See recurring fields.
### freq
How often the site sends data. Either ''H'' (hourly) or ''D'' (daily).
### obsint
The observation interval. Usually 1 or 30.
### markernumber
Markenumber to put in the RINEX header. Ex: 
### markertype
The marker type. Usually GEODETIC.
### position
The approximate position of the site as X,Y,Z.
### observer
Name of observer.
### agency
Name of agency.
### ts
Date and time of last received data from that site.
### active
0 for inactive, 1 for active. If set to 0, it will be regarded as non-existing.

## receivers
Current and previous receivers.
### id, site
See recurrent fields.
### recsn
Receiver serial number.
### rectype
Receiver product name.
### firmware
Receiver firmware version.
### startdate
The date and time of start of usage. Should match the previous enddate.
Ex: 2017-09-16 07:00:00
### enddate
The date and time of end of usage or NULL if still in use.
Ex: 2017-09-16 07:00:00

## rinexdist
Distribution rules for observation files, navigation files and original data.
### id, site
See recurrent fields.
### freq
The frequency this applies to. Either 'D' (daily files) or 'H' (hourly files).
### filetype
The file type is applies to. Can be one of the following:
- Obs: Observation files.
- Nav: Navigation files.
- Sum: The sum file from the QC.
- Arc: The original unmodified files in a zip file.
### obsint
The observation interval this applies to. Must be either the same as the original observation interval
or 30. 30s is always available.
### localdir
Where to copy the file. This is the key in ''localdirs''.
### active
Wether or not this rule is active. Either ''0'' (inactive) or ''1'' (active).

## uploaddest
### id
See recurrent fields.
### name
The name of the destination.
### protocol
Protocol used to transfer the file. Either ''ftp'' or ''sftp''.
### host
Fully qualified DNS name of the host. Must be resolvable.
### user
Username to login with.
### pass
Password to use if using ''ftp''.
### privatekey
Full pathname for the SSH private key to use if using ''sftp''.
### localdir
The name of the local directory (localdirs.name).
### remotedir
Path on the remote server to store files in. Following variables available:
- %year%: Will be replaced with the file year.
- %doy%: Day of year of the file.
- %site%: Sitename
- %site4%: 4-letter sitename.
- %hour%: 1 letter hour (a-x, 0). 0 is a dayfile.
- %hh24%: 2 letter hour (00-23, 24). 24 is is a dayfile.
- %interval%: Interval in seconds. Usually 1 or 30.
Variables can only be used on files named ssss##ccc_R_yyyydddhhss_01f_iiS* (ex: TEJH00DNK_R_20171890000_01D_30S_MO.crx.gz).
### active
Wether or not thils destination is active. Either ''0'' (inactive) or ''1'' (active).