#!/usr/bin/perl
#
# Logger package	Interface for Syslog messages.
#
# This packages provides functions for logging at 5 different levels: debug, info, warn, error and fatal.
# The functions sends the log data to syslog at local1 channel.
#
# sjm@snex.dk, September 2012
#

package Logger;

use strict;
use warnings;
use Carp;
use Sys::Syslog qw(openlog syslog closelog);
use BaseConfig;

my $Facility = $SYSLOG_FACILITY;
my $Program;

our (@ISA, @EXPORT);
BEGIN {
  require Exporter;
  @ISA = qw(Exporter);
  @EXPORT = qw(
	setprogram logchannel
	logdebug loginfo logwarn logerror logfatal errdie logfmt
  );
}

END {
  closelog();
}

sub setprogram($) {
  $Program = shift;
  my $i = index($Program, ' ');
  $Program = substr($Program, 0, $i) if $i > 0;
  $i = rindex($Program, '/');
  $Program = substr($Program, $i+1) if $i > 0;
  openlog($Program, "nofatal,ndelay", $Facility);
}

sub logchannel($) {
  $Facility = shift;
}

sub logdebug(@) { syslog("debug|$Facility", "%s", join(' ',@_));   }
sub loginfo(@)  { syslog("info|$Facility", "%s", join(' ',@_));    }
sub logwarn(@)  { syslog("warning|$Facility", "%s", join(' ',@_)); }
sub logerror(@) { syslog("err|$Facility", "%s", join(' ',@_));     }

sub logfatal(@) {
  syslog("err|$Facility", "%s", join(' ',@_));
  carp localtime().": ".join(' ', @_);
}

sub errdie(@) {
  syslog("err|$Facility", "%s", join(' ',@_));
  croak join(' ', @_);
}

sub logfmt(@) {
  my ($level, $fmt, @args) = @_;
  syslog("$level|$Facility", $fmt, @args);
}

1;
