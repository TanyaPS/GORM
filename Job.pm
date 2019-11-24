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
use Time::Local;
use JSON;
use Fcntl qw(:DEFAULT :flock);
use BaseConfig;
use Utils;
use Logger;
use RinexSet;
use GPSDB;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = { source => 'unknown' };

  if (exists $args{'jobfile'}) {
    my $href = loadJSON($args{'jobfile'});
    $self->{$_} = $$href{$_} foreach keys %$href;
  } else {
    $self->{$_} = $args{$_} foreach keys %args;
  }
  bless($self, $class);
  return $self;
}

sub getIdent() {
  my $self = shift;
  return $self->{'site'}.'-'.$self->{'year'}.'-'.$self->{'doy'}.'-'.$self->{'hour'};
}

sub jobfile() {
  my $self = shift;
  return "$JOBQUEUE/".$self->{'site'}.$self->{'year'}.$self->{'doy'}.$self->{'hour'};
}

sub getWorkdir() {
  my $self = shift;
  return sprintf("%s/%s/%d/%03d", $WORKDIR, $self->{'site'}, $self->{'year'}, $self->{'doy'});
}

sub mkWorkdir() {
  my $self = shift;
  my $dir = $self->getWorkdir();
  system("/bin/mkdir -p -m 777 $dir") unless -d $dir;
  return $dir;
}

# Write this job in $JOBQUEUE
sub submitjob($) {
  my $self = shift;
  my $source = shift;
  my %h = map { $_ => $self->{$_} } keys %$self;
  $h{'source'} = $source;
  storeJSON($self->jobfile(), \%h);
}

# Delete this job from $JOBQUEUE
sub deletejob() {
  my $self = shift;
  unlink($self->jobfile());
}

###################################################################################
# Decimate observation from $src_interval to $dst_interval
#
sub _decimate($$$$$) {
  my ($obsinfile, $obsoutfile, $src_interval, $dst_interval, $logfile) = @_;

  if ($src_interval < $dst_interval) {
    my $cmd =
	"$BNC -nw -conf /dev/null --key reqcAction Edit/Concatenate ".
	"--key reqcRunBy SDFE ".
	"--key reqcObsFile $obsinfile ".
	"--key reqcOutObsFile $obsoutfile ".
	"--key reqcOutLogFile $logfile ".
	"--key reqcRnxVersion 3 ".
	"--key reqcSampling $dst_interval";
    loginfo("Decimate $obsinfile to $obsoutfile");
    sysrun($cmd);
  }
}

###################################################################################
# Splice hourly observation file for the given interval
# TODO: Handle splitted hours
sub _splice($$$) {
  my ($rsday, $rslist, $interval) = @_;

  my $outfile = $rsday->getRinexFilename('MO.'.$interval);
  my @infiles = ();
  push(@infiles, $_->{'MO.'.$interval}) foreach @$rslist;
  my $conv = 'GFZ';	# gfzrnx is memory hungry, but twice as fast
  my $bnccmd =
	"$BNC -nw --conf /dev/null --key reqcAction Edit/Concatenate ".
	"--key reqcRunBy SDFE ".
	"--key reqcRnxVersion 3 ".
	"--key reqcObsFile \"".join(',',@infiles)."\" ".
	"--key reqcOutObsFile $outfile";
  my $gfzcmd =
	"$GFZRNX -f -q -finp ".join(' ',@infiles)." -fout $outfile -kv -splice_direct";
  loginfo("Creating $outfile");
  if ($conv eq 'GFZ') {
    if (sysrun($gfzcmd)) {
      logerror("Splice $outfile failed. Trying $BNC");
      system($bnccmd);
    }
  } else {
    system($bnccmd);
  }
  $rsday->{'MO.'.$interval} = $outfile;
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

  $ant->{'anttype'} = sprintf("%-16s%4s", $1, $2) if $ant->{'anttype'} =~ /^(.+),(.+)$/;

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
    logerror("Cannot open $obs.tmp for write: $!");
    return;
  }
  loginfo("Rewrite $obs headers");

  my @hdr = ();
  while ($_ = readline($ifd)) {
    if (/MARKER NAME\s*$/) {
      push(@hdr, sprintf "%-60sMARKER NAME\n", $sta->{'site'});
    }
    elsif (/MARKER NUMBER\s*$/) {
      push(@hdr, sprintf "%-60sMARKER NUMBER\n", $sta->{'markernumber'}) if defined $sta->{'markernumber'};
    }
    elsif (/MARKER TYPE\s*$/) {
      push(@hdr, sprintf "%-60sMARKER TYPE\n", $sta->{'markertype'}) if defined $sta->{'markertype'};
    }
    elsif (/AGENCY\s*$/) {
      push(@hdr, sprintf "%-20s%-40sOBSERVER / AGENCY\n", $sta->{'observer'}, $sta->{'agency'});
    }
    elsif (/REC # \/ TYPE \/ VERS\s*$/) {
      push(@hdr, sprintf "%-20s%-20s%-20sREC # / TYPE / VERS\n", $sta->{'recsn'}, $sta->{'rectype'}, $sta->{'firmware'});
    }
    elsif (/ANT # \/ TYPE\s*$/) {
      push(@hdr, sprintf "%-20s%-40sANT # / TYPE\n", $sta->{'antsn'}, $sta->{'anttype'});
    }
    elsif (/APPROX POSITION XYZ\s*$/) {
      my ($x, $y, $z) = split(/,/, $sta->{'position'});
      push(@hdr, sprintf "%14.4f%14.4f%14.4f%18sAPPROX POSITION XYZ\n",$x,$y,$z,' ');
    }
    elsif (/DELTA H\/E\/N\s*$/) {
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
    logerror("gapanalyze: open error: $!");
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
      $rs->checkfiles();
      push(@rslist, $rs);
    }
  }
  if (scalar(@rslist) != 24 && !exists $self->{'incomplete'}) {
    logerror("Cannot splice incomplete day");
    return;
  }
  loginfo("$site-$year-$doy: ".(exists $self->{'incomplete'} ? 'processing incomplete day':'all hours present'));

  loginfo("Generating daily files for $site-$year-$doy");
  # Splice navigation files
  my %navbytyp;
  foreach my $rs (@rslist) {
    my $navlist = $rs->getNavlist;
    foreach (@$navlist) {
      if (/_([A-Z]N)\./) {
        my $navtyp = $1;
        $navbytyp{$navtyp} = [] unless exists $navbytyp{$navtyp};
        push(@{$navbytyp{$navtyp}}, $_);
      }
    }
  }
  foreach my $navtyp (keys %navbytyp) {
    my $navoutfile = $rsday->getRinexFilename($navtyp);
    my $aref = $navbytyp{$navtyp};
    loginfo("Creating $navoutfile");
    my $cmd = "$GFZRNX -f -kv -q -finp ".join(' ',@$aref)." -fout $navoutfile -no_nav_stk >/dev/null 2>&1";
    sysrun($cmd);
    $rsday->{$navtyp} = $navoutfile;
  }


  # Do we need 1s dayfile?
  my $interval = 30;
  my $aref = $dbh->selectrow_arrayref(q{
	select count(*) from rinexdist
	where  site = ? and freq = 'D' and filetype = 'Obs' and obsint = 1
  }, undef, $site);
  if ($aref->[0] ne '0') {
    $interval = 1;
    _splice($rsday, \@rslist, 1);
  }
  $rsday->{'interval'} = $interval;

  # create 30s dayfile as we know we need it for QC
  _splice($rsday, \@rslist, 30);

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
	select distinct obsint from rinexdist where site = ? and active = 1
  }, { Slice => {} }, $self->{'site'});
  my %intervals = map { $_->{'obsint'} => 1 } @$aref;
  $intervals{'30'} = 1;  # always need 30s files

  foreach my $interval (keys %intervals) {
    next if $interval == $srcinterval || exists $rs->{'MO.'.$interval};
    if ($interval < $srcinterval) {
      logerror("Cannot create ${interval}s RINEX based in ${srcinterval}s RINEX files");
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
sub _getQC($) {
  my $sumfile = shift;
  my ($qc, $obs, $have, $gaps) = (0, 0, 0, 0);
  
  open(my $fd, '<', $sumfile) || return { qc => 0, gaps => 0 };
  my @qcs = ();
  my %got;
  while (<$fd>) {
    chomp;
    # G:   1?: Observations      :  33065 (   34634)    95.47 %
    # G:   1?: Gaps              :       55
    if (/^\s+([A-Z]):\s+\d[A-Z\?]: Observations.*\s([\d\.]+) %$/) {
      next if $1 eq 'S' || exists $got{$1};
      $got{$1} = 1;
      push(@qcs, $2 > 100 ? 100 : $2);
    }
  }
  close($fd);
  if (scalar(@qcs) > 0) {
    $qc += $_ foreach @qcs;
    $qc /= scalar(@qcs);
  }
  return $qc;
}

###################################################################################
# Main processor. This is where the actual processing of RINEX files happen.
#
sub process() {
  my $self = shift;

  return unless sysopen(LOCK, $self->{'hour'}.'.lock', O_CREAT|O_EXCL);  # safety lock
  close(LOCK);

  $self->{DB} = new GPSDB;
  my $dbh = $self->{DB}->{DBH};

  my $rs;
  if ($self->{'source'} eq 'hour2daily') {
    $rs = $self->gendayfiles();
  } else {
    $rs = new RinexSet(rsfile => $self->{rsfile});
  }

  my ($site, $year, $doy, $hour) = ($self->{'site'}, $self->{'year'}, $self->{'doy'}, $self->{'hour'});
  my $hh24 = ($hour eq '0') ? 0 : letter2hour($hour);
  my $freq = $hour eq '0' ? 'D':'H';

  # Patch RINEX header
  if ($self->{'source'} eq 'ftp') {
    $self->rewriteheaders($rs->{'MO.'.$self->{'interval'}});
  }

  # Produce wanted intervals.
  $self->createWantedIntervals($rs);

  # Find number of data gaps in source
  my $ngaps = $self->gapanalyze($rs->{'MO.'.$self->{'interval'}});

  # QC on 30s file
  my $sumfile = $rs->getFilenamePrefix().'.sum';
  my $navfiles = $rs->getNavlist();
  my $cmd =
	"$BNC --nw --conf /dev/null --key reqcAction Analyze ".
	"--key reqcObsFile ".$rs->{'MO.30'}." ".
	"--key reqcNavFile \"".join(',',@$navfiles)."\" ".
	"--key reqcLogSummaryOnly 2 ".
	"--key reqcOutLogFile $sumfile"
  ;
  loginfo("Running QC on ".$rs->{'MO.30'});
  sysrun($cmd);
  my $qc = _getQC($sumfile);
  loginfo("$site-$year-$doy-$hour: QC: $qc");
  sysrun("gzip -f $sumfile");
  $sumfile .= ".gz";

  $dbh->do(qq{
	delete from gpssums
	where	site = ?
	  and	year = ?
	  and	doy = ?
	  and	hour = ?
  }, undef, $site, $year, $doy, $hour);
  $dbh->do(qq{
	insert into gpssums
	(site, year, doy, hour, jday, quality, ngaps)
	values (?, ?, ?, ?, ?, ?, ?)
  }, undef, $site, $year, $doy, $hour, Doy_to_Days($year,$doy), $qc, $ngaps);

  #################################
  # Distribute
  #
  my $sql = $dbh->prepare(q{
        select  r.obsint, r.filetype, ld.path, ld.name
        from    rinexdist r, localdirs ld
        where   r.site = ?
          and   r.freq = ?
          and   r.active = 1
          and   r.localdir = ld.name
  });
  $sql->execute($site, $freq);
  my $aref = $sql->fetchall_arrayref({});

  foreach my $r (@$aref) {
    next if (-f "do-not-upload" && $r->{'name'} =~ /^ftp-/);

    my $destpath = $r->{'path'};
    $destpath =~ s/%year/$year/g;
    $destpath =~ s/%doy/$doy/g;

    ######
    # Obs
    if ($r->{'filetype'} eq 'Obs') {
      my $filetosend = $rs->{'MO.'.$r->{'obsint'}};
      if (!-f $filetosend) {
        logerror("Cannot distribute $filetosend. Does not exist?!");
        next;
      }
      # Compress and upload
      my $crxfile = $filetosend;
      $crxfile =~ s/\.rnx$/.crx.gz/;
      if (! -f $crxfile || fileage($filetosend) > fileage($crxfile)) {
        loginfo("Compressing $filetosend");
        sysrun("$RNX2CRX - < $filetosend | gzip > $crxfile");
      }
      syscp($crxfile, $destpath, { mkdir => 1, log => 1 } );
    }

    ######
    # Nav
    elsif ($r->{'filetype'} eq 'Nav') {
      my @copylist = ();
      foreach my $navfile (@$navfiles) {
        my $gzfile = "$navfile.gz";
        if (! -f $gzfile || fileage($navfile) > fileage($gzfile)) {
          loginfo("Compressing $navfile");
          system("gzip < $navfile > $gzfile");
        }
        push(@copylist, $gzfile);
      }
      syscp(\@copylist, $destpath, { mkdir => 1, log => 1 });
    }

    ######
    # Sum
    elsif ($r->{'filetype'} eq 'Sum') {
      syscp($sumfile, $destpath, { mkdir => 1, log => 1 });
    }

    ######
    # Arc
    elsif ($r->{'filetype'} eq 'Arc') {
      syscp($rs->{'zipfile'}, $destpath, { mkdir => 1, log => 1 });
    }

  }

  unlink("$hour.lock");

  if ($hour eq '0' && !-f 'debug') {
    # This is a dayfile and is now processed. We are done and delete the workdir.
    chdir("..");
    system("rm -rf ".$self->getWorkdir);
  } else {
    $rs->{'processed'} = 1;
    $rs->store($self->{rsfile});
  }

  return 0;
}

1;
