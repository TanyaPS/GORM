#!/usr/bin/perl

package BaseConfig;

use strict;
use warnings;

our $HOME = '/home/gpsuser';

our $DBDSN = "DBI:mysql:gps";
our $DBUSER = 'gpsuser';
our $DBPASS = 'gpsuser';

our $INCOMING = '/data/ftp';
our $WORKDIR = '/data/work';
our $SAVEDIR = '/data/saved';
our $STALEDIR = $SAVEDIR.'/stale';
our $TMPDIR = '/data/tmp';
our $UPLOAD = '/data/upload';
our $JOBQUEUE = '/data/queue';

our $FTPUPLOAD_PID = '/home/gpsuser/run/ftpuploader.pid';

our $BNC = '/usr/local/bin/bnc';
our $GFZRNX = '/usr/local/bin/gfzrnx';
our $RNX2CRX = '/usr/local/bin/rnx2crx';
our $CRX2RNX = '/usr/local/bin/crx2rnx';

our (@ISA, @EXPORT);
BEGIN {
  require Exporter;
  @ISA = qw(Exporter);
  @EXPORT = qw(
	$HOME
	$DBDSN $DBUSER $DBPASS
	$INCOMING $WORKDIR $SAVEDIR $STALEDIR $TMPDIR
	$UPLOAD $JOBQUEUE
	$FTPUPLOAD_PID
	$BNC $GFZRNX $RNX2CRX $CRX2RNX
  );
}

1;
