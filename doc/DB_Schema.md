# GPSFTP5 Database Schema

## Generel
Database variant: MariaDB
Database name: gps
User: gpsuser/gpsuser

## Tables

### antennas
This contains all antennas for all stations.
#### id
Internal id. Will automatically be filled if left blank. Must be unique.
#### site
9 letter sitename. Ex BUDD00DNK, ARGI00FRO, ...
#### anttype
Antenna product name. Ex "LEIAT504GG,LEIS".
The comma in the name will be replaced with blanks so the left word is left justified
and the right word is right justified in a 20ch value. Ex
LEIAT504GG,LEIS -> LEIAT504GG     LEIS
#### antsn
Antenna serial number.
#### antdelta
Antenna height, east and north eccentricity seperated by commas. Ex 0.244,0,0
#### startdate
The date and time of start of usage. Should match the previous enddate.
Ex: 2017-09-16 07:00:00
#### enddate
The date and time of end of usage or NULL if still in use.
Ex: 2017-09-16 07:00:00

### datagaps
Records of missing observations (gaps) in observation files. **No manual editing needed.**
Maintained by Job.pm.
#### id
Internal id. Will automatically be filled if left blank. Must be unique.
#### site
9 letter sitename. Ex BUDD00DNK, ARGI00FRO, ...
#### year
4 digit year of observation.
#### doy
Day of year
#### hour
Letter representation of the observation hour.
'a' is UTC hour 0, 'x' is UTC hour 23. '0' is the whole day.
#### jday
Julian day.
#### gapno
Gap sequence number within the hour/day.
#### gapstart
Date and time of start of the gap.
#### gapend
Date and time of end of the gap.

### gpssums

