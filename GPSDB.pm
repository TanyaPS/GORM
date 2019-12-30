#!/usr/bin/perl
#
# GPS MySQL database module
#
# sjm@snex.dk, August 2012.

package GPSDB;

use strict;
use warnings;
use DBI;
use BaseConfig;
use Logger;

sub _connectDB();

sub new {
  my $class = shift;
  my %args = @_;
  my $self = {};

  $self->{'DBH'} = _connectDB();

  bless($self, $class);
  return $self;
}

sub DESTROY {
  my $self = shift;
  if (defined $self->{'DBH'}) {
    $self->{'DBH'}->disconnect();
    undef $self->{'DBH'};
  }
}

sub DBH() {
  my $self = shift;
  return $self->{'DBH'};
}

##############################################################
# Connect to MySQL DB. Keep trying every 60 sec.
#
sub _connectDB() {
  my $dbh;
  while (1) {
    last if $dbh = DBI->connect($DBDSN, $DBUSER, $DBPASS,
		{ RaiseError => 0, PrintError => 1, AutoCommit => 1 });
    logerror("Cannot connect to MySQL: $DBI::errstr");
    sleep(60);
  }
  $dbh->{'mysql_auto_reconnect'} = 1;
  return $dbh;
}

##############################################################
# Ping database and re-initialize connection if lost
#
sub ping() {
  my $self = shift;

  if (!$self->{'DBH'}->ping()) {
    $self->{'DBH'}->disconnect();
    $self->{'DBH'} = _connectDB();
  }
}

1;
