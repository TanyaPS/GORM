#!/usr/bin/perl
#
# Common subroutines for the GPS monitor scripts. This module cannot be instantiated.
#
# Soren Juul Moller, August 2012.
# Soren Juul Moller, Nov 2019

package Utils;

use strict;
use warnings;

use POSIX qw(strftime);
use File::stat;
use File::Path qw(make_path);
use Fcntl qw(:DEFAULT);
use Net::SMTP;
use Date::Manip::Base;
use JSON;
use Logger;

our $DMB;

# Export subs and symbols to other modules.
our (@ISA, @EXPORT);
BEGIN {
  require Exporter;
  @ISA = qw(Exporter);
  @EXPORT = qw(
	sysrun syscp sysmv readfile writefile
	Day_of_Year Doy_to_Date Doy_to_Days Days_to_Date Date_to_Days
	sy2year year2sy letter2hour hour2letter gm2str
	basename dirname fileage dirlist round
	daemonize create_pid_file
	loadJSON storeJSON site42site
  );
}

INIT {
  $DMB = new Date::Manip::Base;
}


##########################################################################
# Perform shell command and log.
#
sub sysrun($;$) {
  my ($cmd, $opts) = @_;
  $opts = {} unless defined $opts;
  loginfo($cmd) if $$opts{'log'};
  system($cmd);
  if ($? == -1) {
    logerror("failed to execute: $!");
    return -1;
  }
  if ($? & 127) {
    logfmt("err", "child died with signal %d, %s coredump",
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
  loginfo("$cmd $srclist $dst") if $$opts{'log'};
  if ($$opts{'mkdir'} && ! -d $dst) {
    make_path($dst, { user=>'gpsuser', group=>'gnss' } );
    chmod(0775, $dst);
  }
  return system("/bin/$cmd $srclist $dst");
}

sub syscp($$;$) {
  my ($srclist, $dst, $opts) = @_;
  $opts = {} unless defined $opts;
  return _eval_cp_args('cp', $srclist, $dst, $opts);
}

sub sysmv($$;$) {
  my ($srclist, $dst, $opts) = @_;
  $opts = {} unless defined $opts;
  return _eval_cp_args('mv', $srclist, $dst, $opts);
}


##########################################################################
# Read entire file. Returns data read or empty string.
#
sub readfile($) {
  my ($fn) = @_;
  sysopen(my $fd, $fn, O_RDONLY) || return '';
  sysread($fd, my $data, -s $fn);
  close($fd);
  return $data ? $data : '';
}

##########################################################################
# Write data to file. Creates/truncates exiting file.
# Returns number of bytes written or -1 on fail.
#
sub writefile($$) {
  my ($fn, $data) = @_;
  sysopen(my $fd, $fn, O_WRONLY|O_CREAT|O_TRUNC) || return -1;
  my $n = syswrite($fd, $data);
  close($fd);
  return $n;
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
# Format GM time
#
sub gm2str($) {
  my $gm = shift;
  return strftime("%Y-%m-%d %H:%M:%S", gmtime($gm));
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


##########################################################################################
# Returns rounded float.
# round(3.1415)=3, round(3.5666,2)=3.57.
#
sub round($;$) {
  my ($dbl,$dig) = @_;
  my $fmt = "%.f";
  $fmt = '%.'.$dig.'f' if defined $dig;
  return sprintf($fmt, $dbl);
}


##########################################################################################
# Load a JSON file into a hash reference
#
sub loadJSON($) {
  my $file = shift;
  my $json = readfile($file);
  return undef if !defined $json || length($json) == 0;
  return from_json($json);
}


##########################################################################################
# Store a hash reference in the named file
#
sub storeJSON($$) {
  my ($file, $ref) = @_;
  open(my $fh, '>', $file) || die("cannot create $file: $!");
  writefile($file, to_json($ref, { utf8 => 1, pretty => 1, canonical => 0 }));
}


##########################################################################################
# Returns 9-letter sitename of a 4-letter site
#
sub site42site($) {
  my $site4 = shift;
  $site4 = uc($site4);
  return $site4 eq 'ARGI' ? $site4.'00FRO' : $site4.'00DNK';
}


##########################################################################
# Daemonize current process
#
sub daemonize(;$) {
  my $log = shift;

  chdir("/var/run");
  exit if fork();
  setsid();
  exit if fork();
  open(STDIN, "</dev/null");
  open(STDOUT, ">>$log") if defined $log;
  open(STDERR, ">&STDOUT");
  sleep 1 until getppid() == 1;
}


##########################################################################
# Create a file with the PID of this process in it
#
sub create_pid_file(;$) {
  my $pidfile = shift;
  my $path;
  if (!defined $pidfile || $pidfile eq '') {
    $path = '/var/run/'.basename($0);
    $pidfile = "$path/".basename($0);
  } else {
    $path = dirname($pidfile);
  }
  make_path($path) unless -d $path;
  writefile($pidfile, "$$\n");
  return $pidfile;
}

1;
