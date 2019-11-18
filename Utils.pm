#!/usr/bin/perl
#
# Common subroutines for the GPS monitor scripts. This module cannot be instantiated.
#
# sjm@snex.dk, August 2012.

package Utils;

use strict;
use warnings;

use POSIX qw(setsid);
use IO::File;
use File::stat;
use File::Path qw(make_path);
use Net::SMTP;
use Date::Manip::Base;
use JSON;

use lib '/home/gpsuser/';
use BaseConfig;
use Logger;

our $CRX2RNX = '/usr/local/bin/crx2rnx';
our $RNX2CRX = '/usr/local/bin/rnx2crx';
our $TEQC = '/usr/local/bin/teqc';
our $CONVERT = '/usr/local/bin/convert';
our $RUNPKR = '/usr/bin/runpkr00';

our $DMB;

# Export subs and symbols to other modules.
our (@ISA, @EXPORT);
BEGIN {
  require Exporter;
  @ISA = qw(Exporter);
  @EXPORT = qw(
	sysrun syscp sysmv make_workdir
	Day_of_Year Doy_to_Date Doy_to_Days Days_to_Date Date_to_Days
	sy2year year2sy letter2hour hour2letter
	basename dirname fileage dirlist daemonize create_pid_file
	getRinexInfo loadJSON storeJSON
	$CRX2RNX $RNX2CRX $TEQC $CONVERT $RUNPKR
  );
  $DMB = new Date::Manip::Base;
}


##########################################################################
# Perform shell command and log.
#
sub sysrun($) {
  my $cmd = shift;
  loginfo($cmd);
  system($cmd);
  if ($? == -1) {
    logerror("failed to execute: $!");
    return -1;
  }
  if ($? & 127) {
    logfmt("error", "child died with signal %d, %s coredump",
			   ($? & 127), ($? & 128 ? "with":"without"));
    return -1;
  }
  return $? >> 8;
}


##########################################################################
# Copy/Move file(s).
# Do NOT use File::Copy as it does not close handles. Inotify2 depend on it.
# Do NOT use rename/link/unlink. Inotify2 will not detect it properly.
#
sub _eval_cp_args($$$$) {
  my ($cmd, $srclist, $dst, $opts) = @_;

  $srclist = join(' ', @$srclist) if ref($srclist) eq "ARRAY";
  if (defined $opts) {
    loginfo("$cmd $srclist $dst") if $$opts{'log'};
    make_path($dst) if ! -d $dst && $$opts{'mkdir'};
  }
  return system("/bin/$cmd $srclist $dst");
}

sub syscp($$;$) {
  my ($srclist, $dst, $opts) = @_;
  return _eval_cp_args('cp', $srclist, $dst, $opts);
}

sub sysmv($$;$) {
  my ($srclist, $dst, $opts) = @_;
  return _eval_cp_args('mv', $srclist, $dst, $opts);
}


##########################################################################
# Move $files to $targetdir. Create $targetdir if necessary.
#
sub make_workdir($$$) {
  my ($site, $year, $doy) = @_;
  my $path = sprintf("%s/%s/%4d/%03d", $WORKDIR, $site, $year, $doy);
  make_path($path) unless -d $path;
  return $path;
}


##########################################################################
# Convert (year, mon, day) to DOY
#
sub Day_of_Year($$$) {
  my @ymd = @_;
  return $DMB->day_of_year(\@ymd);
}


##########################################################################
# Convert (year, day) to (year, mon, day)
#
sub Doy_to_Date($$) {
  my ($year, $doy) = @_;
  my $ymd = $DMB->day_of_year($year, $doy);
  return @$ymd;
}


##########################################################################
# Convert (year, day) to jday
#
sub Doy_to_Days($$) {
  my ($year, $doy) = @_;
  my $ymd = $DMB->day_of_year($year, $doy);
  return $DMB->days_since_1BC($ymd);
}


##########################################################################
# Convert jday to (year, mon, day, doy) 
# jday is number of days since 31 dec 1BC
#
sub Days_to_Date($) {
  my $jday = shift;

  my $ymd = $DMB->days_since_1BC($jday);
  my $doy = $DMB->day_of_year($ymd);
  return (@$ymd, $doy);
}


##########################################################################
# Convert (year, mon, day) to jday
#
sub Date_to_Days(@) {
  my @ymd = @_;
  return $DMB->days_since_1BC(\@ymd);
}


##########################################################################
# Returns YYYY version of YY
#
sub sy2year($) {
  my $sy = shift;
  return $sy + ($sy < 80 ? 2000 : 1900);
}


##########################################################################
# Returns YY version of YYYY
#
sub year2sy($) {
  my $year = shift;
  return $year % 100;
}


##########################################################################
# Returns the letter representation of an integer hour
#
sub hour2letter($) {
  my $hh = shift;
  return '0' if $hh == 0;
  return chr(ord('a')+$hh);
}


##########################################################################
# Returns the integer representation of a letter hour
#
sub letter2hour($) {
  my $letter = shift;
  return 0 if $letter eq '0';
  return ord(lc($letter))-97;
}


##########################################################################
# Returns basename of filename
#
sub basename($) {
  my $fn = shift;
  my $i = rindex($fn, '/');
  return ($i >= 0 ? substr($fn, $i+1) : $fn);
}


##########################################################################
# Returns dirname of filename
#
sub dirname($) {
  my $fn = shift;
  my $i = rindex($fn, '/');
  return "/" if $i == 0;
  return ($i >= 0 ? substr($fn, 0, $i) : ".");
}

##########################################################################
# Returns age of file in seconds.
# Returns 0 if file does not exists.
#
sub fileage($) {
  my $fn = shift;
  my $st = stat($fn);
  return (defined $st ? time() - $st->mtime : 0);
}


##########################################################################
# Returns array of plain files in list context or number of plain files in
# scalar context. Files are relative to specified directory.
#
sub dirlist($) {
  my $dir = shift;
  my @files = ();
  if (opendir(my $dh, $dir)) {
    @files = grep { -f $dir.'/'.$_ } readdir($dh);
    closedir($dh);
  }
  return (wantarray ? @files : scalar(@files));
}


##########################################################################
# Daemonize current process
#
sub daemonize($) {
  my $log = shift;

  chdir("/var/run");
  exit if fork();
  setsid();
  exit if fork();
  open(STDIN, "</dev/null");
  open(STDOUT, ">>$log");
  open(STDERR, ">&STDOUT");
  sleep 1 until getppid() == 1;
}


##########################################################################
# Create a file with the PID of this process in it
#
sub create_pid_file($) {
  my $pidfile = shift;
  $pidfile = "$ENV{HOME}/run/".basename($0).".pid" if !defined $pidfile || $pidfile eq "";
  my $fd = new IO::File ">$pidfile";
  print $fd "$$\n";
  return $pidfile;
}

##########################################################################################
#
sub getRinexInfo($) {
  my $obsfile = shift;
  my (%res, $firstobs, $interval, $tstr, $istr);

  open(my $fd, '<', $obsfile);
  while (<$fd>) {
    chop;
    last if /END OF HEADER\s*$/;
    $tstr = $_ if /TIME OF FIRST OBS\s*$/;
    $istr = $_ if /INTERVAL\s*/;
  }
  $tstr = <$fd> unless defined $tstr;
  close($fd);

  my @t = split(/\s+/, $tstr);
  $res{'firstobs'} = sprintf("%4d-%02d-%02d %02d:%02d:%02d", @t[1..6]);

  $res{'interval'} = 1;
  if ($istr =~ /^\s+(\d)\./) {
    $res{'interval'} = $1;
  }

  return \%res;
}


##########################################################################################
#
sub loadJSON($) {
  my $file = shift;
  local $/;  # enable slurp
  open(my $fh, '<', $file) || return undef;
  my $json = <$fh>;
  close($fh);
  return undef if length($json) == 0;
  return from_json($json);
}

sub storeJSON($$) {
  my ($file, $ref) = @_;
  open(my $fh, '>', $file) || die("cannot create $file: $!");
  print $fh to_json($ref, { utf8 => 1, pretty => 1, canonical => 0 });
  close($fh);
}

1;
