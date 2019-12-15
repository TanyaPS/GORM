#!/usr/bin/perl
#
# Maintains JSON file in exclusive mode.
# It is primarely used for maintaining the $workdir/status.json.
#
# Soren Juul Moller, Dec 2019

package StatusDB;

use strict;
use warnings;
use Carp;
use Fcntl qw(:DEFAULT :flock);
use Utils;

my $lockfile;
my $lockfd;
my $statusfile;

#
# Open and lock a status.json in exclusive mode
#
sub new {
  my ($class, $fn) = @_;
  $statusfile = $fn;
  $lockfile = "$fn.lck";
  carp("status file not specified") unless defined $statusfile;
  return undef if !open($lockfd, '>', $lockfile);
  return undef if !flock($lockfd, LOCK_EX);
  my $self = loadJSON($statusfile);
  $self = {} unless defined $self;
  bless $self, $class;
  return $self;
}

DESTROY {
  if (defined $lockfd) {
    flock($lockfd, LOCK_UN);
    close($lockfd);
    unlink($lockfile);
  }
}

#
# Lock file
#
sub lock() {
  my $self = shift;
  return 1 if defined $lockfd;
  return 0 unless open($lockfd, '>', $lockfile);
  return flock($lockfd, LOCK_EX);
}

#
# Unlock file
#
sub unlock() {
  my $self = shift;
  return 0 unless defined $lockfd;
  my $rc = flock($lockfd, LOCK_UN);
  close($lockfd);
  undef $lockfd;
  unlink($lockfile);
  undef $lockfile;
  return $rc;
}

#
# Read JSON into this object
#
sub load() {
  my $self = shift;
  $self->lock();
  $self = loadJSON($statusfile);
  $self = {} unless defined $self;
  return $self;
}

#
# Save this object into JSON file
#
sub save() {
  my $self = shift;
  my %json = map { $_ => $self->{$_} } keys %$self;
  storeJSON($statusfile, \%json);
  $self->unlock();
  return $self;
}

1;
