# Changelog for GPSFTP5 scripts

## 2019-12-24	sjm	gpspickup unpack locking
- Ensure exclusive access when unpacking

## 2019-12-23	sjm	QC parameters
- Changed QC calculation parameters to match EUREF 2018 recommendations.
  See http://epncb.oma.be/_documentation/guidelines/guidelines_analysis_centres.pdf

## 2019-12-22	sjm	Regorganize $SAVEDIR
- Inbound files are now saved in $SAVEDIR/$site/$year/$doy.
- Implement reprocess entire DOY. Only works if files are present in $SAVEDIR.
- Issue warning on Leica split hour files. Do nothing on splitted hours.

## 2019-12-16	sjm	Removed StatusDB.pm
- Removed StatusDB.pm again. Use individual horly status files and status.0 in exclusive mode.
- jobengine: Read all jobfiles and enqueue internally before running jobs.
- jobengine: Use Parallel::Fork::BossWorkerAsync instead of Parallel::ForkManager. It is much faster,
  offers automatic reaping and most importantly, non-blocking enqueuing of jobs to do.
- gpspickup: Use select() instead of alarm() in main loop.

## 2019-12-15	sjm	Use threads in gpspickup
- Make gpspickup multi-threaded to parallelize the unpacking process
- Increased the wait time for multi-file incoming file sets.
- Improve RinexSet->checkfiles
- Job can now be instantiated using a RinexSet as argument
- Use select() instead of alarm() for timeout on Inotify poll

## 2019-12-14	sjm	Move DOY complete check to Job.pm
- Moved check of DOY complete to Job.pm to make it independent of process reaping interval.
- Handle sites with no antannes or receivers defined.
- Fix bug processing inbound daily files.

## 2019-12-11	sjm	Check if doy already processed on all inbound data.
- Renamed check_existing to dailysum_exists. Check only if day is complete.
- Added dailysum_check on Septentrio files as well.

## 2019-12-10	sjm	Added StatusDB.pm
- StatusDB package to handle manipulation of workdir/status.json file in exclusive mode.

## 2019-12-06	sjm	Enable sumfile in DB and access via status.cgi
- Enable load of gzipped sumfile into DB and view of sumfile in QC (click on sumfield)

## 2019-12-05	sjm	Use G-Nut/Anubis instead of BNC for QC
- G-Nut/Anubis is much faster compared to BNC and the QC is more like TEQC QC
- Use gfzrnx to do the decimate from 1s to 30s. It is much faster than BNC.

## 2019-12-03	sjm	Config parameter jobinstances added.
- Add config parameter jobinstances. Default is 4 instances.
- Optimized scan loop in gpspickup and jobengine.
- Add -c file.conf option to gpspickup, jobengine and ftpuploader to specify alternate configuration.

## 2019-12-02	sjm	Location position and marker number may be unspecified.
- If not specifying the location position, the APPROX POSITION header will be left untouched.
- If markernumber is null, set to site if Unknown else leave original.
  If markernumber is set, always redefine markernumber in file.

## 2019-12-01	sjm	Admin.cgi, commands and signals
- Jobengine now able to perform custom commands via queue
- Admin.cgi tells jobengine when to reload ftpuploader or force completion of a day.
- Admin.cgi refuses to enable a ftpuploader rule if directory does not exist
- Improved signal handling in ftpuploader
- Make it possible to override default global contants (BaseConfig.pm) using /usr/local/etc/gorm.conf
- Add edit of antennas and receivers to admin.cgi

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
