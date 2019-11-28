#!/usr/bin/perl

package BaseConfig;

use strict;
use warnings;

our $DBDSN    = "DBI:mysql:gps";
our $DBUSER   = 'gpsuser';
our $DBPASS   = 'gpsuser';

my $DATAROOT  = '/data';
our $INCOMING = "$DATAROOT/ftp";
our $WORKDIR  = "$DATAROOT/work";
our $SAVEDIR  = "$DATAROOT/saved";
our $STALEDIR = "$SAVEDIR/stale";
our $TMPDIR   = "$DATAROOT/tmp";
our $JOBQUEUE = "$DATAROOT/queue";

our $BNC      = '/usr/local/bin/bnc';
our $GFZRNX   = '/usr/local/bin/gfzrnx';
our $RNX2CRX  = '/usr/local/bin/rnx2crx';
our $CRX2RNX  = '/usr/local/bin/crx2rnx';
our $SBF2RIN  = '/usr/local/bin/sbf2rin';

our (@ISA, @EXPORT);
BEGIN {
  require Exporter;
  @ISA = qw(Exporter);
  @EXPORT = qw(
	$DBDSN $DBUSER $DBPASS
	$INCOMING $WORKDIR $SAVEDIR $STALEDIR $TMPDIR $JOBQUEUE
	$BNC $GFZRNX $RNX2CRX $CRX2RNX
  );
}

1;
