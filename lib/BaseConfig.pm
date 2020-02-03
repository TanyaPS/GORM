#!/usr/bin/perl
#
# BaseConfig.pm - Global common variables used throughout the scriipts.
#
# These defaults can be overridden in '/usr/local/etc/gorm.conf', which is loaded automatically during startup (if exists).
# The globals can then be overridden again by using BaseConfig::init($conffile) inside the main program.
#
# Soren Juul Moller, Nov 2019

package BaseConfig;

use strict;
use warnings;

use FindBin;

our $DBDSN    = "DBI:mysql:gps";
our $DBUSER   = 'gpsuser';
our $DBPASS   = 'gpsuser';

my $DATAROOT  = '/data';
our ($INCOMING, $WORKDIR, $SAVEDIR, $STALEDIR, $JOBQUEUE);

our $JOBINSTANCES = 4;		# Number of parallel job instances

our $ANUBIS   = '/usr/local/bin/anubis';
our $BNC      = '/usr/local/bin/bnc';
our $GFZRNX   = '/usr/local/bin/gfzrnx';
our $RNX2CRX  = '/usr/local/bin/rnx2crx';
our $CRX2RNX  = '/usr/local/bin/crx2rnx';
our $SBF2RIN  = '/usr/local/bin/sbf2rin';

our $SYSLOG_FACILITY = 'local1';

sub init($) {
  my $conf = shift;

  $DATAROOT = $ENV{'DATAROOT'} if defined $ENV{'DATAROOT'};

  if (-f $conf) {
    my %vars = (
	dbdsn => \$DBDSN,
	dbuser => \$DBUSER,
	dbpass => \$DBPASS,
	dataroot => \$DATAROOT,
	jobinstances => \$JOBINSTANCES,
	anubis => \$ANUBIS,
	bnc => \$BNC,
	gfzrnx => \$GFZRNX,
	rnx2crx => \$RNX2CRX,
	crx2rnx => \$CRX2RNX,
	sbf2bin => \$SBF2RIN,
	syslog_facility => \$SYSLOG_FACILITY
    );
    open(my $fd, '<', $conf);
    while (<$fd>) {
      next if /^\s*#|^\s*$/;
      chomp;
      if (/\s*(\w+)\s*=\s*([^\s]+)/) {
        if (exists $vars{lc($1)}) {
          my $ref = $vars{$1};
          $$ref = $2;
        }
      }
    }
    close($fd);
  }

  $INCOMING = "$DATAROOT/ftp";
  $WORKDIR  = "$DATAROOT/work";
  $SAVEDIR  = "$DATAROOT/saved";
  $STALEDIR = "$DATAROOT/stale";
  $JOBQUEUE = "$DATAROOT/queue";
}

# Executed just before main program starts.
INIT {
  my $conf = "$FindBin::Bin/../etc/gorm.conf";
  $conf = '/usr/local/etc/gorm.conf' unless -f $conf;
  init($conf);
}

# Executed at compile time.
our (@ISA, @EXPORT);
BEGIN {
  require Exporter;

  @ISA = qw(Exporter);
  @EXPORT = qw(
	$DBDSN $DBUSER $DBPASS
	$INCOMING $WORKDIR $SAVEDIR $STALEDIR $JOBQUEUE
	$JOBINSTANCES
	$ANUBIS $BNC $GFZRNX $RNX2CRX $CRX2RNX $SBF2RIN
	$SYSLOG_FACILITY
  );
}

1;
