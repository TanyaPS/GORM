#!/usr/bin/perl
#
# Class representing a set of RINEXv3 files belonging together.
# 
# Soren Juul Moller, Nov 2019

package RinexSet;

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
  } else {
    $self->{$_} = $args{$_} foreach keys %args;
  }
  bless $self, $class;
}

sub getWorkdir() {
  my $self = shift;
  return sprintf "%s/%s/%d/%03d", $WORKDIR, $self->{site}, $self->{year}, $self->{doy};
}

sub getRsFile() {
  my $self = shift;
  return $self->getWorkdir().'/rs.'.$self->{hour}.'.json';
}

#
#TEJH00DNK_R_20171890000_01D_30S_MO.rnx
#TEJH00DNK_R_20171890000_01D_CN.rnx
#TEJH00DNK_R_20171890000_01D_EN.rnx
#TEJH00DNK_R_20171890000_01D_GN.rnx
#TEJH00DNK_R_20171890000_01D_JN.rnx
#TEJH00DNK_R_20171890000_01D_RN.rnx
#TEJH00DNK_R_20171890000_01H_01S_MO.rnx
#TEJH189a.17o.zip
#TEJH00DNK_R_20171891600_01H_01S_MO.rnx
#
sub getFilenamePrefix() {
  my $self = shift;
  return sprintf "%s_R_%d%03d%02d00_01%s",
	$self->{site}, $self->{year}, $self->{doy}, letter2hour($self->{hour}), $self->{hour} eq '0' ? 'D':'H';
}

sub getRinexFilename($) {
  my ($self, $ftyp) = @_;
  if ($ftyp =~ /^MO\.(\d+)/) {
    my $interval = $1;
    return sprintf("%s_%02dS_MO.rnx", $self->getFilenamePrefix, $interval);
  }
  return $self->getFilenamePrefix."_".$ftyp.".rnx";
}

sub getNavlist() {
  my $self = shift;
  my @fa = ();
  foreach my $k (keys %$self) {
    push(@fa, $self->{$k}) if $k =~ /[A-Z]N/;
  }
  return \@fa;
}

# Defines $obj->{ftyp} if file exists.
# ftyp is MO, CN, EN, GN, JN, RN or MN.
#
sub checkfiles() {
  my $self = shift;
  my $w = $self->getWorkdir;
  foreach my $ftyp (qw(MO.1 MO.15 MO.30 CN EN GN JN RN MN)) {
    delete $self->{$ftyp};
    my $fn = $self->getRinexFilename($ftyp);
    $self->{$ftyp} = $fn if -f "$w/$fn";
  }
}

#
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
  my @navfiles = ();
  foreach my $zm ($zip->members()) {
    my $zmfn = $zm->fileName();
    my $ofn;
    unlink("$workdir/$zmfn");
    $zm->extractToFileNamed("$workdir/$zmfn");
    if ($zmfn =~ /\.\d\dd$/) {
      $ofn = $zmfn;
      $ofn =~ s/d$/o/;
      system("$CRX2RNX - < $workdir/$zmfn > $workdir/$ofn");
      unlink("$workdir/$zmfn");
      $zmfn = $ofn;
    }
    elsif ($zmfn =~ /\.crx$/) {
      $ofn = $zmfn;
      $ofn =~ s/\.crx$/.rnx/;
      system("$CRX2RNX - < $workdir/$zmfn > $workdir/$ofn");
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

sub load(;$) {
  my ($self, $file) = @_;
  $file = $self->getRsFile() unless defined $file;
  my $json = loadJSON($file);
  $self->{$_} = $json->{$_} foreach keys %$json;
}

sub store(;$) {
  my ($self, $file) = @_;
  $file = $self->getRsFile() unless defined $file;
  my %h = map { $_ => $self->{$_} } keys %$self;
  storeJSON($file, \%h);
}

package testRinexSet;

use Utils;

sub dotest() {
  my $rs = new RinexSet(site => 'TEJH00DNK', year => 2017, doy => 189, hour => 'q', arr1 => [0,1,2] );
  $rs->store("/tmp/rs.json");

  $rs = new RinexSet(rsfile => "/tmp/rs.json");
  print "Test site ", ($rs->{site} eq "TEJH00DNK") ? "ok" : "NOT ok", "\n";
  print "Test year: ", ($rs->{year} == 2017) ? "ok" : "NOT ok", "\n";
  my $ok = 1;
  for (my $i = 0; $i <= 2; $i++) {
    $ok &= (${$rs->{arr1}}[$i] == $i);
  }
  print "arr1: ", $ok ? "ok":"NOT ok", "\n";

  $rs->store("/tmp/rs.json");
  $rs = new RinexSet;
  print "Test no site: ", ($rs->{site} eq "TEJH00DNK") ? "NOT ok" : "ok", "\n";
  $rs->load("/tmp/rs.json");
  print "Test site: ", ($rs->{site} eq "TEJH00DNK") ? "ok" : "NOT ok", "\n";

  print "workdir: ", $rs->getWorkdir, "\n";
  my $ofn = $rs->getRinexFilename('MO.1');
  print "obsFilename: $ofn: ", ($ofn eq "TEJH00DNK_R_20171891600_01H_01S_MO.rnx") ? "ok":"NOT ok", "\n";

  $rs->checkfiles;
  $rs->store("/tmp/rs.json");

  my $a = $rs->getNavlist;
  foreach (@$a) { print "$_\n"; }
  print "GN navfn: ", $rs->getRinexFilename('GN'), "\n";
}

# dotest();
 
1;
