# Changelog for GPSFTP5 scripts

## 2019-11-29	sjm	gpspickup pending job logic updated.
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
