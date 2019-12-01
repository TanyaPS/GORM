# Changelog for GPSFTP5 scripts

## 2019-12-01	sjm	Admin.cgi, commands and signals
- Jobengine now able to perform custom commands via queue
- Admin.cgi tells jobengine when to reload ftpuploader or force completion of a day.
- Admin.cgi refuses to enable a ftpuploader rule if directory does not exist
- Improved signal handling in ftpuploader
- Make it possible to override default global contants (BaseConfig.pm) using /usr/local/etc/gorm.conf

## 2019-11-30	sjm	Added partial port of admin.cgi
- admin.cgi handles create/edit sites, destinations, localdirs. Also forget DOY and finish imcompletes.

## 2019-11-29	sjm	Make ftpuploader compatible with gpsftp4
- Backport of ftpuploader to gpsftp4.

## 2019-11-29	sjm	Added support for Septentrio raw files
- Added support for Septentrio raw files (SBF format). This is now the preferred
  format from Septentrio receivers.

## 2019-11-27	sjm	gpspickup pending job logic updated.
- Make sure timer is updated for each new file in a multi file upload.
  Also Check that no files belonging to a pending job are being uploaded before submitting.

## 2019-11-26	sjm	Database scheda documentation added.
- Commenting and documentation.
- util/forget and util/loadsitelog utility added.

## 2019-11-25	sjm	Initial release.
- First release includes processing of Leica, Trimble and Septentrio RINEX3
  files. Processing is RINEX header rewrite, decimate 1s->30s, pack
  and distribute to recipients. Also includes QC status viewer (status.cgi).
