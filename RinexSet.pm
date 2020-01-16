#!/usr/bin/perl
#
# Class representing a set of RINEXv3 files belonging together.
# 
# Soren Juul Moller, Nov 2019

package RinexSet;

use Carp;
use JSON;
use BaseConfig;
use Utils;
use Logger;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = {};

  if (exists $args{rsfile}) {
    $self = loadJSON($args{rsfile});
    if (!defined $self) {
      carp("load error $args{rsfile}");
      $self = {};
    }
  } else {
    $self->{$_} = $args{$_} foreach keys %args;
  }
  $self->{'origs'} = [] unless defined $self->{'origs'};
  bless $self, $class;
}

# Unique RinexSet id
sub getIdent() {
  my $self = shift;
  return "$self->{site}-$self->{year}-$self->{doy}-$self->{hour}";
}

# Access methods
sub site() { shift->{'site'}; }
sub year() { shift->{'year'}; }
sub doy()  { shift->{'doy'};  }
sub hour() { shift->{'hour'}; }
sub arg() { my $s = shift; ( site => $s->{site}, year => $s->{year}, doy => $s->{doy}, hour => $s->{hour} ); }

#################################
# Get working dir of this RINEX set
#
sub getWorkdir() {
  my $self = shift;
  return sprintf "%s/%s/%d/%03d", $WORKDIR, $self->{site}, $self->{year}, $self->{doy};
}

#################################
# Get the object file name
#
sub getRsFile() {
  my $self = shift;
  return $self->getWorkdir().'/rs.'.$self->{hour}.'.json';
}

#
#TEJH00DNK_R_20171890000_01D_30S_MO.rnx
#TEJH00DNK_R_20171890000_01D_EN.rnx
#TEJH00DNK_R_20171890000_01D_GN.rnx
#TEJH00DNK_R_20171890000_01D_RN.rnx
#TEJH00DNK_R_20171890000_01H_01S_MO.rnx
#TEJH00DNK_R_20171891600_01H_01S_MO.rnx
#
#################################
# Get common filename prefix
#
sub getFilenamePrefix(;$) {
  my ($self, $mi) = @_;
  $mi = 0 unless defined $mi;
  return sprintf "%s_R_%d%03d%02d%02d_01%s",
	$self->{site}, $self->{year}, $self->{doy}, letter2hour($self->{hour}), $mi, $self->{hour} eq '0' ? 'D':'H';
}

#################################
# Get RINEXv3 filename of specified type
# Type: MO.# or aN
#
sub getRinexFilename($;$) {
  my ($self, $ftyp, $mi) = @_;
  $mi = 0 unless defined $mi;
  if ($ftyp =~ /^MO\.(\d+)/) {
    my $interval = $1;
    return sprintf("%s_%02dS_MO.rnx", $self->getFilenamePrefix($mi), $interval);
  }
  return $self->getFilenamePrefix($mi)."_".$ftyp.".rnx";
}

#################################
# Returns array or string of nav files 
#
sub getNavlist() {
  my $self = shift;
  my @fa = ();
  foreach my $k (keys %$self) {
    push(@fa, $self->{$k}) if $k =~ /[A-Z]N/;
  }
  return wantarray ? @fa : join(' ',@fa);
}

#################################
# Search all files in $dir with this filename prefix
# and sets MO.# and xN in $self
#
sub checkfiles($) {
  my ($self, $dir) = @_;
  my $prefix = $self->getFilenamePrefix;
  foreach (<"${dir}/${prefix}*.rnx">) {
    if (/_([0-9]{2})S_MO\.rnx$/) {
      # observation file
      $self->{'MO.'.int($1)} = basename($_);
    } elsif (/_([A-X]N)\.rnx$/) {
      # navigation file
      $self->{$1} = basename($_);
    }
  }
  return $self;
}

#################################
# Load rs JSON file into self
#
sub load(;$) {
  my ($self, $file) = @_;
  $file = $self->getRsFile() unless defined $file;
  my $json = loadJSON($file);
  $self->{$_} = $json->{$_} foreach keys %$json;
  return $self;
}

#################################
# Store self into rs JSON file
# Ignore attributes where name starts with '_'
#
sub store(;$) {
  my ($self, $file) = @_;
  $file = $self->getRsFile() unless defined $file;
  my %h = map { $_ => $self->{$_} } grep(!/^_/, keys %$self);
  storeJSON($file, \%h);
  return $self;
}
 
1;
