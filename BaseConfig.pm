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

our $SYSLOG_FACILITY = 'local1';

INIT {
  # Check for default overrides
  if (-f '/usr/local/etc/gorm.conf') {
    my %vars = (
	dbdsn => \$DBDSN,
	dbuser => \$DBUSER,
	dbpass => \$DBPASS,
	dataroot => \$DATAROOT,
	incoming => \$INCOMING,
	workdir => \$WORKDIR,
	savedir => \$SAVEDIR,
	staledir => \$STALEDIR,
	tmpdir => \$TMPDIR,
	jobqueue => \$JOBQUEUE,
	bnc => \$BNC,
	gfzrnx => \$GFZRNX,
	rnx2crx => \$RNX2CRX,
	crx2rnx => \$CRX2RNX,
	sbf2bin => \$SBF2RIN,
	syslog_facility => \$SYSLOG_FACILITY
    );
    open(my $fd, '<', '/usr/local/etc/gorm.conf');
    while (<$fd>) {
      next if /^\s*#|^\s*$/;
      chomp;
      if (/\s*(\w+)\s*=\s*([^\s]+)/) {
        if (exists $vars{$1}) {
          my $ref = $vars{$1};
          $$ref = $2;
        }
      }
    }
    close($fd);
  }
}

our (@ISA, @EXPORT);
BEGIN {
  require Exporter;

  @ISA = qw(Exporter);
  @EXPORT = qw(
	$DBDSN $DBUSER $DBPASS
	$INCOMING $WORKDIR $SAVEDIR $STALEDIR $TMPDIR $JOBQUEUE
	$BNC $GFZRNX $RNX2CRX $CRX2RNX $SBF2RIN
	$SYSLOG_FACILITY
  );
}

1;
