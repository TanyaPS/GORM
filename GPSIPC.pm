#!/usr/bin/perl

package GPSIPC;

use strict;
use warnings;
use IO::Socket::UNIX;

use BaseConfig;

my %SOCK_PATHS = (
	'ftpuploader' => "$HOME/run/ftpuploader.sock",
);

my $socket;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = {};

  $self->{'name'} = $args{'name'};

  my $sockpath = $SOCK_PATHS{$args{'name'}};
  return unless defined $sockpath;
  $self->{'sockpath'} = $sockpath;

  system("mkdir -p $HOME/run") unless -d "$HOME/run";

  if (defined $args{'server'}) {
    $socket = IO::Socket::UNIX->new(
	Type => SOCK_STREAM,
	Local => $sockpath,
	Listen => 1,
    );
    $self->{'server'} = 1;
  } else {
    $socket = IO::Socket::UNIX->new(
	Type => SOCK_STREAM,
	Local => $SOCK_PATHS{$args{'name'}},
    );
    $self->{'server'} = 0;
  }
  $self->{'socket'} = $socket;

  bless($self, $class);
  return $self;
}


sub DESTROY {
  my $self = shift;

  close($socket);
  unlink($self->{'sockpath'}) if $self->{'server'};
}


sub getline() {
  my $self = shift;

  if (my $fd = $socket->accept()) {
    return $fd->getline();
  }
  return undef;
}


sub print() {
  my $self = shift;

  $socket->print(@_);
}

1;
