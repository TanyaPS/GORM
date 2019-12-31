#!/usr/bin/perl
###################################################################################
# Represents processing of one set of RINEXv3 file(s)
# The configuration of the processing is loaded from a jobfile, usually from $JOBQUEUE.
# The processeor is designed to run in parallel and is uniquely identified by
# site-year-doy-hour (ident).
#
# Soren Juul Moller, Nov 2019

package Job;

use strict;
use warnings;
use Carp qw(longmess);
use Data::Dumper;
use Time::Local;
use Fcntl qw(:DEFAULT :flock);
use File::Path qw(make_path);
use JSON;
use BaseConfig;
use Utils;
use Logger;
use RinexSet;
use GPSDB;

my $Debug = 0;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = { source => 'unknown' };

  if (exists $args{'jobfile'}) {
    my $href = loadJSON($args{'jobfile'});
    $self->{$_} = $$href{$_} foreach keys %$href;
  } elsif (exists $args{'json'}) {
    if (!defined $args{'json'} || $args{'json'} eq '') {
      logerror(longmess("invalid JSON string"));
      $self = {};
    } else {
      $self = from_json($args{'json'});
    }
  } elsif (exists $args{'rs'}) {
    my $rs = $args{'rs'};
    $self->{$_} = $rs->{$_} foreach qw(site year doy hour interval);
    $self->{'rsfile'} = $rs->getRsFile;
  } else {
    $self->{$_} = $args{$_} foreach keys %args;
  }
  bless($self, $class);
  return $self;
}

DESTROY {
  my $self = shift;
  close($self->{'_statefd'}) if defined $self->{'_statefd'};
}

sub verifyobj() {
  my $self = shift;
  my $ok = 1;
  foreach (qw(site year doy hour)) {
    if (!defined $self->{$_}) {
      logdebug(longmess("$_ undefined"));
      $ok = 0;
    }
  }
  return $ok;
}

sub getIdent() {
  my $self = shift;
  $self->verifyobj() if $Debug;
  return $self->{'site'}.'-'.$self->{'year'}.'-'.$self->{'doy'}.'-'.$self->{'hour'};
}

sub jobfile() {
  my $self = shift;
  $self->verifyobj() if $Debug;
  return "$JOBQUEUE/".$self->{'site'}.$self->{'year'}.$self->{'doy'}.$self->{'hour'};
}

sub getWorkdir() {
  my $self = shift;
  $self->verifyobj() if $Debug;
  return sprintf("%s/%s/%d/%03d", $WORKDIR, $self->{'site'}, $self->{'year'}, $self->{'doy'});
}

sub mkWorkdir() {
  my $self = shift;
  my $dir = $self->getWorkdir();
  make_path($dir, { user=>'gpsuser', group=>'gnss' }) unless -d $dir;
  chmod(0775, $dir);  # make_path bug work-around
  return $dir;
}

# Write this job in $JOBQUEUE
sub submitjob($) {
  my $self = shift;
  my $source = shift;
  $self->verifyobj() if $Debug;
  my %h = map { $_ => $self->{$_} } grep(!/^_/, keys %$self);
  $h{'source'} = $source;
  storeJSON($self->jobfile(), \%h);
  return $self;
}

# Delete this job from $JOBQUEUE
sub deletejob() {
  my $self = shift;
  unlink($self->jobfile());
  return $self;
}

###################################################################################
# Manipulate state file in exclusive mode. States can be:
#   none	Not yet started.
#   queued	In queue for processing.
#   running	Currently processing.
#   processed	Processed.
#   incomplete	All hours not yet present. Valid only for hour '0'.
#
sub lockstate() {
  my $self = shift;
  my $fd;
  $self->{'_statefile'} = $self->getWorkdir()."/state.".$self->{'hour'};
  sysopen($fd, $self->{'_statefile'}, O_RDWR|O_CREAT);
  flock($fd, LOCK_EX);
  $self->{'_statefd'} = $fd;
  return $self;
}

sub readstate() {
  my $self = shift;
  my $str;
  seek($self->{'_statefd'}, 0, 0);
  sysread($self->{'_statefd'}, $str, -s $self->{'_statefile'});
  $str = 'none' unless $str;	# 'none' if !defined or empty
  return $str;
}

sub writestate($) {
  my ($self,$str) = @_;
  seek($self->{'_statefd'}, 0, 0);
  truncate($self->{'_statefd'}, 0);
  syswrite($self->{'_statefd'}, $str);
  return $self;
}

sub unlockstate() {
  my $self = shift;
  close($self->{'_statefd'});
  delete $self->{'_statefd'};
  delete $self->{'_statefile'};
  return $self;
}

sub setstate($) {
  my ($self, $str) = @_;
  $self->lockstate()->writestate($str)->unlockstate();
  return $self;
}

###################################################################################
# Decimate observation from $src_interval to $dst_interval
#
sub _decimate($$$$$) {
  my ($obsinfile, $obsoutfile, $src_interval, $dst_interval, $logfile) = @_;

  if ($src_interval < $dst_interval) {
    my @bnccmd =
	($BNC, qw(--nw --conf /dev/null --key reqcAction Edit/Concatenate --key reqcRunBy SDFE),
	 qw(--key reqcObsFile), $obsinfile,
	 qw(--key reqcOutObsFile), $obsoutfile,
	 qw(--key reqcOutLogFile), $logfile,
	 qw(--key reqcRnxVersion 3),
	 qw(--key reqcSampling), $dst_interval);
    my @gfzcmd =
	($GFZRNX, '-finp', $obsinfile, '-fout', $obsoutfile,
		  '-smp', $dst_interval, qw(-f -q -kv -errlog), $logfile);
    loginfo("Decimate $obsinfile to $obsoutfile");
    sysrun(\@gfzcmd, { log => $Debug });
  }
}

###################################################################################
# Splice hourly observation file for the given interval
# TODO: Handle splitted hours
sub _splice($$$) {
  my ($rsday, $rslist, $interval) = @_;

  my $outfile = $rsday->getRinexFilename('MO.'.$interval);
  my $logfile = 'splice.'.$rsday->{'hour'};
  my @infiles = ();
  push(@infiles, $_->{'MO.'.$interval}) foreach @$rslist;
  my $conv = 'GFZ';	# gfzrnx is memory hungry, but twice as fast
  my @gfzcmd = ($GFZRNX, '-finp', @infiles, '-fout', $outfile, qw(-f -q -kv -splice_direct -errlog), $logfile);
  my @bnccmd = ($BNC, qw(--nw --conf /dev/null --key reqcAction Edit/Concatenate),
		qw(--key reqcRunBy SDFE --key reqcRnxVersion 3),
		qw(--key reqcObsFile), join(',',@infiles),
		qw(--key reqcOutObsFile), $outfile,
		qw(--key reqcOutLogFile), $logfile);
  loginfo("Creating $outfile");
  if ($conv eq 'GFZ') {
    if (sysrun(\@gfzcmd, { log => $Debug })) {
      logerror("Splice $outfile failed. Trying $BNC");
      sysrun(\@bnccmd, { log => $Debug });
    }
  } else {
    sysrun(\@bnccmd, { log => $Debug });
  }
  $rsday->{'MO.'.$interval} = $outfile;
  return $rsday;
}

###################################################################################
# Merge hourly zipfiles into daily zipfile
#
sub _mergezips($$) {
  my ($rsday, $rslist) = @_;

  my $outfile = $rsday->getFilenamePrefix().'.zip';
  loginfo("Creating $outfile");
  my @infiles = ();
  push(@infiles, $_->{'zipfile'}) foreach @$rslist;
  return if scalar(@infiles) == 0;
  sysrun(['/usr/bin/zipmerge', $outfile, @infiles], { log => $Debug });
  $rsday->{'zipfile'} = $outfile;
  return $rsday;
}

###################################################################################
# Fetch station info from database for the RINEX header
#
sub getStationInfo() {
  my ($self) = @_;
  my $dbh = $self->{'DB'}->{'DBH'};

  my @ymd = Doy_to_Date($self->{'year'}, $self->{'doy'});
  my $startdate = sprintf("%4d-%02d-%02d %02d:00:00", @ymd, letter2hour($self->{'hour'}));

  my $loc = $dbh->selectrow_hashref(q{
	select	markernumber, markertype, position, observer, agency
	from	locations
	where	site = ?
  }, undef, $self->{'site'});

  my $rec = $dbh->selectrow_hashref(q{
	select	recsn, rectype, firmware
	from	receivers
	where	site = ?
	  and	startdate < str_to_date(?, '%Y-%m-%d %T')
	order	by startdate desc
	limit	1
  }, undef, $self->{'site'}, $startdate);

  my $ant = $dbh->selectrow_hashref(q{
	select	antsn, anttype, antdelta
	from	antennas
	where	site = ?
	  and	startdate < str_to_date(?, '%Y-%m-%d %T')
	order	by startdate desc
	limit	1
  }, undef, $self->{'site'}, $startdate);

  $ant->{'anttype'} = sprintf("%-16s%4s", $1, $2) if defined $ant->{'anttype'} && $ant->{'anttype'} =~ /^(.+),(.+)$/;

  my $sta = { site => $self->{'site'} };
  $sta->{$_} = $loc->{$_} foreach keys %$loc;
  $sta->{$_} = $rec->{$_} foreach keys %$rec;
  $sta->{$_} = $ant->{$_} foreach keys %$ant;
  return $sta;
}

###################################################################################
# Rewrite RINEX headers with the values from the database.
#
sub rewriteheaders($) {
  my ($self, $obs) = @_;
  my $dbh = $self->{'DB'}->{'DBH'};
  my ($ifd, $ofd);

  my $sta = $self->getStationInfo();

  if (!open($ifd, '<', $obs)) {
    logerror("Open error: $!");
    return;
  }
  unlink("$obs.tmp");
  if (!open($ofd, '>', "$obs.tmp")) {
    logerror("1:Cannot open $obs.tmp for write: $!");
    return;
  }
  loginfo("Rewrite $obs headers");

  my @hdr = ();
  while ($_ = readline($ifd)) {
    if (/MARKER NAME\s*$/) {
      push(@hdr, sprintf "%-60sMARKER NAME\n", $sta->{'site'});
    }
    elsif (/MARKER NUMBER\s*$/) {
      if (!defined $sta->{'markernumber'} && /^Unknown/) {
        $sta->{'markernumber'} = substr($sta->{'site'}, 0, 4);
      }
      push(@hdr, (defined $sta->{'markernumber'} ? sprintf("%-60sMARKER NUMBER\n", $sta->{'markernumber'}) : $_));
    }
    elsif (/MARKER TYPE\s*$/) {
      push(@hdr, sprintf "%-60sMARKER TYPE\n", $sta->{'markertype'}) if defined $sta->{'markertype'};
    }
    elsif (/AGENCY\s*$/) {
      push(@hdr, sprintf "%-20s%-40sOBSERVER / AGENCY\n", $sta->{'observer'}, $sta->{'agency'});
    }
    elsif (/REC # \/ TYPE \/ VERS\s*$/ &&
	   defined $sta->{'recsn'} && defined $sta->{'rectype'} && defined $sta->{'firmware'}) {
      push(@hdr, sprintf "%-20s%-20s%-20sREC # / TYPE / VERS\n", $sta->{'recsn'}, $sta->{'rectype'}, $sta->{'firmware'});
    }
    elsif (/ANT # \/ TYPE\s*$/ &&
	   defined $sta->{'antsn'} && defined $sta->{'anttype'}) {
      push(@hdr, sprintf "%-20s%-40sANT # / TYPE\n", $sta->{'antsn'}, $sta->{'anttype'});
    }
    elsif (/APPROX POSITION XYZ\s*$/) {
      # if specified in DB, use that value
      if (defined $sta->{'position'} && $sta->{'position'} =~ /(\d+),(\d+),(\d+)/) {
        push(@hdr, sprintf "%14.4f%14.4f%14.4f%18sAPPROX POSITION XYZ\n",$1,$2,$3,' ');
      } else {
        push(@hdr, $_);		# else use original from file
      }
    }
    elsif (/DELTA H\/E\/N\s*$/ &&
	   defined $sta->{'antdelta'}) {
      my ($x, $y, $z) = split(/,/, $sta->{'antdelta'});
      push(@hdr, sprintf "%14.4f%14.4f%14.4f%18sANTENNA: DELTA H/E/N\n",$x,$y,$z,' ');
    }
    else {
      push(@hdr, $_);
    }
    last if /END OF HEADERS\s*$/;
  }

  # Add missing headers that is defined in DB
  if (defined $sta->{'markernumber'} && scalar(grep(/MARKER NUMBER\s*$/,@hdr)) == 0) {
    my @n = ();
    foreach my $h (@hdr) {
      push(@n, $h);
      push(@n, sprintf "%-60sMARKER NUMBER\n", $sta->{'markernumber'}) if $h =~ /MARKER NAME\s*$/;
    }
    @hdr = @n;
  }
  if (defined $sta->{'markertype'} && scalar(grep(/MARKER TYPE\s*$/,@hdr)) == 0) {
    my @n = ();
    foreach my $h (@hdr) {
      push(@n, $h);
      push(@n, sprintf "%-60sMARKER TYPE\n", $sta->{'markertype'}) if $h =~ /MARKER NAME\s*$/;
    }
    @hdr = @n;
  }

  # Write file
  print $ofd $_ foreach @hdr;
  while ($_ = readline($ifd)) {
    print $ofd $_;
  }

  close($ifd);
  close($ofd);
  unlink($obs);
  rename("$obs.tmp", $obs);
}

###################################################################################
# Find and register gaps in observation file
#
sub gapanalyze($) {
  my ($self, $obsfile) = @_;
  my ($firstobs, $lastobs, $interval);
  my ($firstyy, $firstmm, $firstdd);
  my $hour = $self->{'hour'};

  my $ifd;
  if (!open($ifd, '<', $obsfile)) {
    logerror("gapanalyze: open $obsfile error: $!");
    return 0;
  }

  while ($_ = readline($ifd)) {
    $interval = int($1) if /^\s+([\d\.]+)\s+INTERVAL\s*$/;
    last if /END OF HEADER\s*$/;
  }

  # Read the first observation header
  # > 2019 01 15 00 00  0.0000000  0 48
  # > 2019 01 15 00 00  1.0000000  0 48
  $_ = readline($ifd);
  if (index($_,'>') == 0) {
    my @a = split(/\s+/, $_);
    $firstobs = timegm(int($a[6]),$a[5],$a[4],$a[3],$a[2]-1,$a[1]);
    ($firstyy, $firstmm, $firstdd) = @a[1..3];
  } else {
    logerror "Expected first observation after headers. Aborting gapanalyze.";
    return 0;
  }

  my @gaplen = ();
  my @gapstart = ();
  my @gapend = ();
  my $ngaps = 0;

  # Calculate the theoretical first obs time.
  my $firsthh = timegm(0, 0, letter2hour($hour), $firstdd, $firstmm-1, $firstyy);

  # If firstobs does not match firsthh, then register gap from firsthh until firstobs
  if ($firstobs != $firsthh) {
    $gaplen[0] = $firstobs - $firsthh;
    $gapstart[0] = gm2str($firsthh);
    $gapend[0] = gm2str($firstobs);
    $ngaps++;
  }

  my $prevtime = $firstobs;
  my $nobs = 1;
  while ($_ = readline($ifd)) {
    next unless index($_, '>') == 0;
    my @a = split(/\s+/, $_);
    my ($yyyy, $mm, $dd, $hh, $mi, $ss) = @a[1..6];
    my $curtime = timegm(int($ss), $mi, $hh, $dd, $mm-1, $yyyy);
    if (!defined $interval) {
      $interval = $curtime - $firstobs;   # in case of missing INTERVAL header
    }
    if ($prevtime + $interval != $curtime) {
      my $prevstr = gm2str($prevtime+$interval);
      my $len = $interval;
      while ($prevtime + $len < $curtime) {
	$len += $interval;
      }
      $len -= $interval;
      if ($len > 0) {
	my $endstr = sprintf("%4d-%02d-%02d %02d:%02d:%02d", $yyyy, $mm, $dd, $hh, $mi, $ss);
	$gaplen[$ngaps] = $len;
	$gapstart[$ngaps] = $prevstr;
	$gapend[$ngaps] = $endstr;
	$ngaps++;
      }
    }
    $prevtime = $lastobs = $curtime;
    $nobs++;
  }

  my $endobs;
  if ($hour eq '0') {
    # Last observation should be (firsthh+1day)-interval
    $endobs = $firsthh + 86400 - $interval;
  } else {
    # assume 1 hour file
    $endobs = $firsthh + 3600 - $interval;
  }
  if ($lastobs != $endobs) {
    # gap from $prev to next midnight/end-of-hour
    $gaplen[$ngaps] = $endobs - $lastobs;
    $gapstart[$ngaps] = gm2str($lastobs + $interval);
    $gapend[$ngaps] = gm2str($endobs + $interval);
    $ngaps++;
  }

  close($ifd);

  # Delete any datagaps from previous run of this hour/day
  my $dbh = $self->{'DB'}->{'DBH'};
  $dbh->do(q{
	delete from datagaps where site=? and year=? and doy=? and hour=?
  }, undef, $self->{'site'}, $self->{'year'}, $self->{'doy'}, $self->{'hour'});

  loginfo("$obsfile nobs=$nobs, ngaps=$ngaps");
  return 0 if $ngaps == 0;

  # Gaps found. Register gaps in DB.
  for (my $i = 0; $i < $ngaps; $i++) {
    loginfo($self->getIdent().": gap #$i: len=$gaplen[$i] start=$gapstart[$i] end=$gapend[$i]");
  }
  my $sql = $dbh->prepare(q{
	insert into datagaps
	(site, year, doy, hour, jday, gapno, gapstart, gapend)
	values (?, ?, ?, ?, ?, ?, ?, ?)
  });
  my $jday = Doy_to_Days($self->{'year'}, $self->{'doy'});
  for (my $i = 0; $i < $ngaps; $i++) {
    $sql->execute($self->{'site'}, $self->{'year'}, $self->{'doy'}, $self->{'hour'},
		  $jday, $i+1, $gapstart[$i], $gapend[$i]);
  }

  return $ngaps;
}

###################################################################################
# Check if a hourly site day is complete.
# If so, splice hourly files into a day file and submit a new job
#
sub gendayfiles() {
  my $self = shift;
  my $dbh = $self->{'DB'}->{'DBH'};
  my ($site, $year, $doy) = ($self->{'site'}, $self->{'year'}, $self->{'doy'});
  my @rslist = ();

  my $rsday = new RinexSet(site => $site, year => $year, doy => $doy, hour => '0');

  foreach my $h ('a'..'x') {
    my $rs = new RinexSet(site => $site, year => $year, doy => $doy, hour => $h);
    if (-f $rs->getRsFile()) {
      $rs->load();
      next unless exists $rs->{'processed'};
      push(@rslist, $rs);
    }
  }
  if (scalar(@rslist) != 24 && !exists $self->{'force_complete'}) {
    logerror("2:Cannot splice incomplete day");
    return undef;
  }
  loginfo("$site-$year-$doy: finishing incomplete day.") if exists $self->{'force_complete'};

  loginfo("Generating daily files for $site-$year-$doy");
  # Splice navigation files
  # Order nav file lists by type
  my %navbytyp;
  foreach my $rs (@rslist) {
    foreach ($rs->getNavlist()) {
      if (/_([A-Z]N)\./) {
        my $navtyp = $1;
        $navbytyp{$navtyp} = [] unless exists $navbytyp{$navtyp};
        push(@{$navbytyp{$navtyp}}, $_);
      }
    }
  }
  # Foreach nav type, splice the list into one daily nav file
  foreach my $navtyp (keys %navbytyp) {
    my $navoutfile = $rsday->getRinexFilename($navtyp);
    my $aref = $navbytyp{$navtyp};
    loginfo("Creating $navoutfile");
    sysrun([$GFZRNX, '-finp', @$aref, '-fout', $navoutfile, qw(-f -kv -q)], { log => $Debug });
    $rsday->{$navtyp} = $navoutfile;
  }


  # Do we need 1s dayfile? If not, dont create.
  my $interval = 30;
  my $aref = $dbh->selectrow_arrayref(q{
	select count(*) from rinexdist
	where  site = ? and freq = 'D' and filetype = 'Obs' and obsint = 1 and active = 1
  }, undef, $site);
  if ($aref->[0] ne '0') {
    $interval = 1;
    _splice($rsday, \@rslist, 1);
  }
  $rsday->{'interval'} = $interval;

  # Always create 30s dayfile as we know we need it for QC
  _splice($rsday, \@rslist, 30);

  # Create daily zip if we need it
  $aref = $dbh->selectrow_arrayref(q{
	select	count(*) from rinexdist
	where	site = ? and freq = 'D' and filetype = 'Arc' and active = 1
  }, undef, $site);
  _mergezips($rsday, \@rslist) if $aref->[0] ne '0';

  $rsday->store();
  return $rsday;
}

###################################################################################
# decimate obs into intervals we need to distribute
#
sub createWantedIntervals($) {
  my ($self, $rs) = @_;
  my $dbh = $self->{'DB'}->{'DBH'};
  my ($site, $srcinterval) = ($self->{'site'}, $self->{'interval'});

  my $aref = $self->{'DB'}->{'DBH'}->selectall_arrayref(q{
	select distinct obsint from rinexdist where site = ? and filetype = 'Obs' and active = 1
  }, { Slice => {} }, $self->{'site'});
  my %intervals = map { $_->{'obsint'} => 1 } @$aref;
  $intervals{'30'} = 1;  # always need 30s files

  foreach my $interval (keys %intervals) {
    next if int($interval) == int($srcinterval) || exists $rs->{'MO.'.$interval};
    if ($interval < $srcinterval) {
      logerror("3:Cannot create ${interval}s RINEX based in ${srcinterval}s RINEX files");
      next;
    }
    # decimate this into requested interval
    my $obs = $rs->getRinexFilename('MO.'.$interval);
    _decimate($rs->{'MO.'.$srcinterval}, $obs, $srcinterval, $interval, "dec.$rs->{hour}.$interval.log");
    $rs->{'MO.'.$interval} = $obs;
  }
}

###################################################################################
# Retrive QC values from sum file. QC is defined as the average of QC's
# for all signal types. It is just an indicator of the data quality used for
# monitoring.
#
sub _QC($) {
  my $rs = shift;

  loginfo('Running QC on '.$rs->{'MO.30'});
  my $sumfile = $rs->getFilenamePrefix().'.sum';
  my $logfile = 'anubis.'.$rs->{'hour'}.'.log';
  # See http://epncb.oma.be/_documentation/guidelines/guidelines_analysis_centres.pdf
  my @cmd = ($ANUBIS,
	':inputs:rinexo', $rs->{'MO.30'},
 	':inputs:rinexn', scalar $rs->getNavlist,
	qw(:qc:int_gap=360 :qc:ele_cut=0 :qc:ele_pos=0 :qc:sec_sum=2 :qc:sec_bnd=2 :qc:sec_gap=2 :qc:mpx_nep=20 :qc:mpx_lim=3.0),
	qw(:outputs:verb=0 :outputs:xtr), $sumfile, ':outputs:log', $logfile);
  if ($rs->{'hour'} eq '0') {
    push(@cmd, qw(:gen:sys GPS :gen:int 180 :qc:int_stp=3600));
  } else {
    push(@cmd, qw(:gen:int 30 :qc:int_stp=900));
  }
  sysrun(\@cmd, { log => $Debug });

  # #TOTSUM First_Epoch________ Last_Epoch_________ Hours_ Sample MinEle #_Expt #_Have %Ratio o/slps woElev Exp>00 Hav>03 %Rt>03
  # =TOTSUM 2019-01-15 00:00:00 2019-01-15 23:59:30  24.00  30.00   0.00 144235 128435  89.05     35  50420 136654 128435  93.99
  my $qc = 0;
  open(my $fd, '<', $sumfile) || return 0;
  while (<$fd>) {
    chomp;
    if (/^=TOTSUM /) {
      my @a = split(/\s+/, $_);
      if ($a[15] =~ /([0-9\.]+)/) {
        $qc = round($1);
      }
      last;
    }
  }
  close($fd);

  sysrun(['/usr/bin/gzip', '-9fq', $sumfile], { log => $Debug });
  $rs->{'sumfile'} = $sumfile.'.gz';

  return round($qc);
}

###################################################################################
# Create zipfile in workking directory if distribution requires it and it
# does not exist already.
#
sub save_originals($) {
  my ($self, $rs) = @_;

  return if exists $rs->{'zipfile'};

  # Check if we need an Arc, either daily or hourly. If not, don't bother creating one.
  my $aref = $self->{'DB'}->{'DBH'}->selectrow_arrayref(q{
	select	count(*) from rinexdist
	where	site = ? and filetype = 'Arc' and active = 1
  }, undef, $rs->{'site'});
  return if $aref->[0] eq '0';

  my @files = ();
  if (exists $rs->{'rawfile'}) {
    push(@files, $rs->{'rawfile'});
  } else {
    push(@files, $rs->{$_}) foreach grep(/^(MO\.\d+|[A-Z]N)$/, keys %$rs);
  }
  if (scalar(@files) > 0) {
    my $fn = $rs->getFilenamePrefix;
    loginfo("Creating $fn.zip");
    sysrun(['zip','-9jq',"$fn.zip",@files], { log => $Debug });
    $rs->{'zipfile'} = "$fn.zip";
  }
}

###################################################################################
# Main processor. This is where the actual processing of RINEX files happen.
#
sub process() {
  my $self = shift;
  my ($site, $year, $doy, $hour) = ($self->{'site'}, $self->{'year'}, $self->{'doy'}, $self->{'hour'});
  my $hh24 = ($hour eq '0') ? 0 : letter2hour($hour);
  my $freq = $hour eq '0' ? 'D':'H';

  loginfo($self->getIdent()." starting");

  $self->{'DB'} = new GPSDB;
  my $dbh = $self->{'DB'}->{'DBH'};

  my $rs;
  if ($self->{'source'} eq 'hour2daily') {
    $rs = $self->gendayfiles();
    return 'error' unless defined $rs;
  } else {
    $rs = new RinexSet(rsfile => $self->{rsfile});
  }

  # Patch RINEX header
  if ($self->{'source'} eq 'ftp') {
    $self->save_originals($rs);
    $self->rewriteheaders($rs->{'MO.'.$self->{'interval'}});
  }

  # Produce wanted intervals.
  $self->createWantedIntervals($rs);

  # Find number of data gaps in source
  my $interval = $self->{'interval'};
  $interval = 30 unless defined $rs->{'MO.'.$interval};		# we may not have created 1s file
  my $ngaps = $self->gapanalyze($rs->{'MO.'.$interval});

  # QC on 30s file
  my $qc = _QC($rs);
  loginfo("$site-$year-$doy-$hour: QC: $qc");
  my $sumfileblob;  # NULL in DB allowed
  $sumfileblob = readfile($rs->{'sumfile'}) if defined $rs->{'sumfile'};

  $dbh->do(qq{
	delete from gpssums
	where	site = ?
	  and	year = ?
	  and	doy = ?
	  and	hour = ?
  }, undef, $site, $year, $doy, $hour);
  $dbh->do(qq{
	insert into gpssums
	(site, year, doy, hour, jday, quality, ngaps, sumfile)
	values (?, ?, ?, ?, ?, ?, ?, ?)
  }, undef, $site, $year, $doy, $hour, Doy_to_Days($year,$doy), $qc, $ngaps, $sumfileblob);

  $dbh->do(q{
	update	locations
	set	ts = current_timestamp()
	where	site = ?
  }, undef, $site);

  #################################
  # Distribute
  #
  my $aref = $dbh->selectall_arrayref(q{
        select  r.obsint, r.filetype, ld.path, ld.name
        from    rinexdist r, localdirs ld
        where   r.site = ?
          and   r.freq = ?
          and   r.active = 1
          and   r.localdir = ld.name
  }, { Slice => {} }, $site, $freq);

  foreach my $r (@$aref) {
    next if (-f "do-not-upload" && $r->{'name'} =~ /^ftp-/);

    my $destpath = $r->{'path'};
    $destpath =~ s/%site/$site/g;
    my $site4 = substr($site, 0, 4);
    $destpath =~ s/%site4/$site4/g;
    $destpath =~ s/%year/$year/g;
    $destpath =~ s/%doy/$doy/g;

    ######
    # Obs
    if ($r->{'filetype'} eq 'Obs') {
      my $filetosend = $rs->{'MO.'.$r->{'obsint'}};
      my $crxfile = $filetosend;
      $crxfile =~ s/\.rnx$/.crx.gz/;
      if (!-f $filetosend) {
        logerror("4:Cannot distribute $filetosend. Does not exist?!");
        next;
      }
      # Compress and upload
      if (! -f $crxfile) {
        loginfo("Compressing $filetosend");
        sysrun("$RNX2CRX $filetosend - | gzip -9q > $crxfile", { log => $Debug });
      }
      syscp([$crxfile], $destpath, { mkdir => 1, log => $Debug } );
    }

    ######
    # Nav
    elsif ($r->{'filetype'} eq 'Nav') {
      my @copylist = ();
      foreach my $navfile ($rs->getNavlist()) {
        my $gzfile = "$navfile.gz";
        if (! -f $gzfile) {
          loginfo("Compressing $navfile");
          sysrun("/usr/bin/gzip -9cq $navfile >$gzfile 2>/dev/null", { log => $Debug });
        }
        push(@copylist, $gzfile);
      }
      syscp(\@copylist, $destpath, { mkdir => 1, log => $Debug });
    }

    ######
    # Sum
    elsif ($r->{'filetype'} eq 'Sum') {
      syscp([$rs->{'sumfile'}], $destpath, { mkdir => 1, log => $Debug });
    }

    ######
    # Arc
    elsif ($r->{'filetype'} eq 'Arc') {
      syscp([$rs->{'zipfile'}], $destpath, { mkdir => 1, log => $Debug });
    }

  }

  delete $self->{'DB'};

  if (-f 'debug') {
    open(my $fd, ">jobdump.$hour");
    print $fd Dumper $self;
    close($fd);
  }

  $rs->{'processed'} = 1;
  $rs->store($self->{'rsfile'});

  #
  # If DOY is complete, erase workdir.
  # If not, mark this hour complete and check if DOY is complete.
  # If DOY complete, submit dayjob
  #
  if ($hour eq '0' && !-f 'debug') {
    # This is a dayfile and is now processed. We are done and delete the workdir.
    chdir("..");
    sysrun([qw(rm -rf), $self->getWorkdir()]);
  } else {
    $self->setstate('processed');

    # Check if doy is complete, and if it is, submit a day job
    # Manipulate state.0 in exclusive mode since all processes tries to update this.
    my $dayjob = new Job(site => $site, year => $year, doy => $doy, hour => '0', interval => $self->{'interval'});
    my $state = $dayjob->lockstate()->readstate();
    $state = 'incomplete' if $state eq 'none';
    if ($state eq 'incomplete') {
      my $complete = 1;
      foreach my $h ('a'..'x') {
	$complete = 0 unless -f "state.$h"  && readfile("state.$h") eq 'processed';
      }
      if ($complete) {
	loginfo("$site-$year-$doy: all hours present. Submitting hour2daily job.");
	$dayjob->submitjob('hour2daily');
        $state = 'queued';
      } else {
        $state = 'incomplete';
      }
      $dayjob->writestate($state);
    }
    $dayjob->unlockstate();
  }

  loginfo($self->getIdent()." finished");
  return 'processed';
}

1;
