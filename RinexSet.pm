#!/usr/bin/perl
#
# Class representing a set of RINEXv3 files belonging together.
# 
# Soren Juul Moller, Nov 2019

package RinexSet;

use Carp;
use JSON;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
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
  bless $self, $class;
}

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
sub getFilenamePrefix() {
  my $self = shift;
  return sprintf "%s_R_%d%03d%02d00_01%s",
	$self->{site}, $self->{year}, $self->{doy}, letter2hour($self->{hour}), $self->{hour} eq '0' ? 'D':'H';
}

#################################
# Get RINEXv3 filename of specified type
# Type: MO.# or aN
#
sub getRinexFilename($) {
  my ($self, $ftyp) = @_;
  if ($ftyp =~ /^MO\.(\d+)/) {
    my $interval = $1;
    return sprintf("%s_%02dS_MO.rnx", $self->getFilenamePrefix, $interval);
  }
  return $self->getFilenamePrefix."_".$ftyp.".rnx";
}

#################################
# Returns array of nav files
#
sub getNavlist() {
  my $self = shift;
  my @fa = ();
  foreach my $k (keys %$self) {
    push(@fa, $self->{$k}) if $k =~ /[A-Z]N/;
  }
  return @fa;
}

#################################
# Search all files in $workdir with this filename prefix
# and sets MO.# and xN in $self
#
sub checkfiles() {
  my $self = shift;
  my $w = $self->getWorkdir;
  my $prefix = $self->getFilenamePrefix;
  foreach (<"${w}/${prefix}*.rnx">) {
    if (/_([0-9]{2})S_MO\.rnx$/) {
      # observation file
      $self->{'MO.'.int($1)} = basename($_);
    } elsif (/_([A-X]N)\.rnx$/) {
      # navigation file
      $self->{$1} = basename($_);
    }
  }
}

#################################
# Unzip into $self->getWorkdir using RINEXv3 filenames
#
sub unzip($$) {
  my ($self, $zipfile, $interval) = @_;
  my $workdir = $self->getWorkdir;
  my %v3typemap = ( 'o' => 'MO', 'n' => 'GN', 'g' => 'RN', 'l' => 'EN', 'f' => 'CN', 'q' => 'JN' );

  my $zip = Archive::Zip->new;
  if ($zip->read($zipfile) != AZ_OK) {
    logwarn("unable to read zipfile $zipfile");
    return undef;
  }
  foreach my $zm ($zip->members()) {
    my $zmfn = $zm->fileName();
    my $ofn;
    unlink("$workdir/$zmfn");
    $zm->extractToFileNamed("$workdir/$zmfn");
    if ($zmfn =~ /\.\d\dd$/) {
      $ofn = $zmfn;
      $ofn =~ s/d$/o/;
      system("$CRX2RNX $workdir/$zmfn - > $workdir/$ofn");
      unlink("$workdir/$zmfn");
      $zmfn = $ofn;
    }
    elsif ($zmfn =~ /\.crx$/) {
      $ofn = $zmfn;
      $ofn =~ s/\.crx$/.rnx/;
      system("$CRX2RNX $workdir/$zmfn - > $workdir/$ofn");
      unlink("$workdir/$zmfn");
      $zmfn = $ofn;
    }
    my $ftyp = "UU";
    if ($zmfn =~ /\.\d\d([onglfq])$/) {
      $ftyp = $v3typemap{$1};
    } elsif ($zmfn =~ /_(MO|[A-Z]N)\.rnx$/) {
      $ftyp = $1;
    }
    $ftyp .= '.'.$interval if $ftyp eq 'MO';
    $ofn = $self->getRinexFilename($ftyp);
    if ($ofn ne $zmfn) {
      unlink("$workdir/$ofn");
      link("$workdir/$zmfn", "$workdir/$ofn");
      unlink("$workdir/$zmfn");
    }
    $self->{$ftyp} = $ofn;
  }
  $self->{zipfile} = $zipfile;
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
}

#################################
# Store self into rs JSON file
#
sub store(;$) {
  my ($self, $file) = @_;
  $file = $self->getRsFile() unless defined $file;
  my %h = map { $_ => $self->{$_} } keys %$self;
  storeJSON($file, \%h);
}
 
1;
