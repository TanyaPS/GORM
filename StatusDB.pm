#!/usr/bin/perl
#
# Maintains status.json file in exclusive mode.
#
# Soren Juul Moller, Dec 2019

package StatusDB;

use strict;
use warnings;
use Carp;
use Fcntl qw(:DEFAULT :flock);
use Utils;

my $lockfd;
my $statusfile;

sub new {
  my ($class, $_statusfile) = @_;
  $statusfile = $_statusfile;
  confess("status file not specified") unless defined $statusfile;
  return undef unless sysopen($lockfd, $statusfile, O_CREAT|O_RDWR);
  flock($lockfd, LOCK_EX);
  my $self = loadJSON($statusfile);
  $self = {} unless defined $self;
  bless $self, $class;
  return $self;
}

DESTROY {
  if (defined $lockfd) {
    flock($lockfd, LOCK_UN);
    close($lockfd);
    undef $lockfd;
  }
}

sub lock() {
  my $self = shift;
  return if defined $lockfd;
  return 0 unless sysopen($lockfd, $statusfile, O_CREAT|O_RDWR);
  flock($lockfd, LOCK_EX);
  return $self;
}

sub unlock() {
  my $self = shift;
  return 0 unless defined $lockfd;
  flock($lockfd, LOCK_UN);
  close($lockfd);
  undef $lockfd;
  return $self;
}

sub load() {
  my $self = shift;
  $self->lock() if $lockfd == 0;
  $self = loadJSON($statusfile);
  $self = {} unless defined $self;
  return $self;
}

sub save() {
  my $self = shift;
  my %json = map { $_ => $self->{$_} } keys %$self;
  storeJSON($statusfile, \%json);
  $self->unlock();
  return $self;
}

1;
