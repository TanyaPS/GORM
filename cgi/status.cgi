#!/usr/bin/perl
#
# QC Status CGI
#
# sjm@snex.dk, August 2012
# sjm@addpro.dk, Januar 2014 - Added support for FEH1-4
# soren@moellers.dk November 2019 - Modified for gpsftp5 (RINEX3)
#

use strict;
use warnings;
use DBI;
use CGI;
use IO::Uncompress::Gunzip qw(gunzip);

my $LONGSLEEP = 2;	# Reload delay in minutes

my %QC_Color = (
        80      =>      '#FC0000',
        81      =>      '#FF2900',
        82      =>      '#FF5D00',
        83      =>      '#FF7700',
        84      =>      '#FF9200',
        85      =>      '#FFA800',
        86      =>      '#FFB900',
        87      =>      '#FFC900',
        88      =>      '#FFDF00',
        89      =>      '#FFEE00',
        90      =>      '#FFFF00',      
        91      =>      '#ECFF00',
        92      =>      '#D9FF00',
        93      =>      '#B8FF00',
        94      =>      '#B8FF00',
        95      =>      '#9DFF00',
        96      =>      '#83FF00',
        97      =>      '#6FFF00',
        98      =>      '#23EA23',
        99      =>      '#1DD732',
        100     =>      '#19C819',
);      


package Cell;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = {};

  if (defined $args{'row'}) {
    my $row = $args{'row'};
    foreach (qw(site year doy hour quality ngaps)) {
      $self->{$_} = $row->{$_};
    }
  }
  foreach my $k (qw(txt ts deltats url)) {
    $self->{$k} = $args{$k} if defined $args{$k};
  }
  if (defined $self->{'quality'}) {
    $self->{'color'} = (defined $QC_Color{$self->{'quality'}} ? $QC_Color{$self->{'quality'}} : $QC_Color{"80"});
    $self->{'fontcolor'} = "white" if $self->{'quality'} < 84;
  }
  if (defined $args{'ts'} && defined $args{'deltats'}) {
    $self->{'celltip'} = "Last receive: $args{'ts'}";
  }

  bless($self, $class);
  return $self;
}

sub tostring() {
  my $c = shift;	# $c == $self

  my $str = "<td width=2% class=";
  if ($c->{'ngaps'} > 0) {
    $str .= (defined $c->{'gaplen'} && $c->{'gaplen'} < 600 ? "smallgaps":"gaps");
  } else {
    $str .= "nogaps";
  }
  my $style = "";
  $style .= "color:$c->{fontcolor};" if defined $c->{'fontcolor'};
  $style .= "background-color:$c->{color};" if defined $c->{'color'};
  $str .= " style=\"$style\"" if $style ne "";
  $str .= " title=\"$c->{'celltip'}\"" if defined $c->{'celltip'};
  $str .= " onclick=\"s('$c->{'site'}',$c->{'year'},$c->{'doy'},'$c->{'hour'}')\"";
  $str .= ">$c->{'quality'}</td>\n";
  return $str;
}

package main;

use Date::Manip::Base;

my $DMB = new Date::Manip::Base;

sub Day2Date($) {
  my $jday = shift;

  my $ymd = $DMB->days_since_1BC($jday);
  my $doy = $DMB->day_of_year($ymd);
  return (@$ymd, $doy);
}

sub Date2Day($$$) {
  my @ymd = @_;
  return $DMB->days_since_1BC(\@ymd);
}

sub Doy2Date($$) {
  my ($year, $doy) = @_;
  my $ymd = $DMB->day_of_year($year, $doy);
  return @$ymd;
}

my @GMTnow = gmtime(time);
my $DAYnow = Date2Day(1900+$GMTnow[5], $GMTnow[4]+1, $GMTnow[3]);

sub showheader {
  my $showclock = shift;

#  print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\">\n";
  print "<!DOCTYPE HTML>\n";
  print "<html><head>\n";
  print "<title>Dynamic Visual QC-status</title>\n";
  print <<EOD;
	<script language="Javascript">
	<!--
	function s(site,year,doy,hour) {
	  window.open('$ENV{'SCRIPT_NAME'}?fnc=showsum&site='+site+'&year='+year+'&doy='+doy+'&hour='+hour);
	}
	//-->
	</script>
	<style type=text/css>
	body { color: black; background: white; margin-left: 1%; margin-right: 1%; }
  	A:hover { text-decoration: none; color: #008000; background: #CDCDCD; }
	A:visited { text-decoration: none; }
	A:active { text-decoration: none; }
	A:link { text-decoration: none; }
	table.gpstab {
		text-align: center;
		font-family: "Courier New";
		font-size: 10px;
		font-weight: bold;
		color: #000000;
		border-width: 2px 0px;
		border-style: solid;
		border-color: white;
		border-spacing: 1px;
	}
	.doy { background-color: #A3FFFF; }
	.cap { background-color: #87B3E9; white-space: nowrap; height: 13px; }
	.cap a { text-decoration: none; color: #000000; }
	.capwarn { background-color: #FFFF66; }
	.capwarn a { text-decoration: none; color: #000000; }
	.missing { background-color: #E4B4B1; }
	.nogaps { color: #000000; }
	.nogaps:hover { color: #808080; }
	.gaps { font-size: 9px; padding: 0px; border-width: 2px; border-style: solid; border-color: #005CE6; }
	.gaps:hover { color: #808080; }
	.smallgaps { font-size: 9px; padding: 0px; border-width: 2px; border-style: dotted; border-color: #005CE6; }
	.smallgaps:hover { color: #808080; }
	</style>
EOD
  print "</head>\n";
  print "<body bgcolor=#FFFFFF TEXT=#000000 LINK=#0000FF VLINK=#0000FF ALINK=#FF0000>\n";
  if ($showclock) {
    my @gm = gmtime();
    my $reloadspeed = ($gm[1] > 5 && $gm[1] < 57 ? $LONGSLEEP : 1);
    my $millisecs = $reloadspeed * 60 * 1000;
    print qq{
      <TABLE align="center" cellspacing="0" cellpadding="2">
      <TR align="center">
        <TD><FONT SIZE=2>
        <script language="JavaScript">
	<!--
	var time = new Date();
	var hours = time.getUTCHours();
	var minutes = time.getUTCMinutes();
	var seconds = time.getUTCSeconds();
	if (hours <= 9) { hours = "0"+hours; }
	if (minutes <= 9) { minutes = "0"+minutes; }
	if (seconds <= 9) { seconds = "0"+seconds; }
	document.write("<b>Last page load at: "+hours+":"+minutes+":"+seconds+" (UTC)");
	//-->
	</script>
	</FONT></TD>
	<TD><FONT SIZE="2">
	  <B><script language="javascript" src="/liveclock.js"></script></B>
	</FONT></TD>
	<TD><FONT SIZE="2">
	  <B>Page reloads every $reloadspeed min.</B>
	</FONT></TD>
      </TR>
      </TABLE>
      <script language="Javascript">
      <!--
      function reload() { location = "$ENV{'SCRIPT_NAME'}"; }
      setTimeout("reload()", $millisecs);
      //-->
      </script>
    };
  }
}

sub showbottom($$$$) {
  my ($is24hview, $site, $year, $doy) = @_;

  my $url = $ENV{'SCRIPT_NAME'};
  my $other_url = $url;
  if ($is24hview) {
    $url .= "?fnc=24h";
    $other_url .= "?site=$site\&year=$year\&doy=$doy" if defined $site && defined $year && defined $doy;
  } else {
    $other_url .= "?fnc=24h";
    $other_url .= "\&site=$site\&year=$year\&doy=$doy" if defined $site && defined $year && defined $doy;
  }
  my $other_txt = ($is24hview ? "1 hour view":"24 hour view");
  print "<p>\n";
  print "<form method=GET>\n";
  print "<a href=\"$url\">Main Page</a>&nbsp;&nbsp;\n";
  print "Doy: <input type=text name=doy>";
  my $yyyy = (gmtime(time))[5]+1900;
  print " Year: <input type=text name=year value=$yyyy> ";
  print " <input type=submit>\n";
  print "&nbsp;&nbsp;&nbsp;<a href=\"$other_url\">$other_txt</a>\n";
  print "</form>\n<br>\n";
  print "</body></html>\n";
}

sub add_gaplist($$$) {
  my ($dbh, $c, $r) = @_;

  my $gapsql = $dbh->prepare_cached(q{
	select	gapno, time(gapstart) gapstart, time(gapend) gapend, timestampdiff(second,gapstart,gapend) gaplen
	from	datagaps
	where	site = ?
	  and	year = ?
	  and	doy = ?
	  and	hour = ?
	order by gapno
  });
  $gapsql->execute($r->{'site'}, $r->{'year'}, $r->{'doy'}, $r->{'hour'});
  my $gaplen = 0;
  my $celltip = ", gaps: $r->{'ngaps'}";
  foreach my $g (@{ $gapsql->fetchall_arrayref({}) }) {
    $celltip .= "\n #".$g->{'gapno'}.": ".$g->{'gapstart'}." -> ".$g->{'gapend'}." (".$g->{'gaplen'}."s)";
    $gaplen += int($g->{'gaplen'});
  }
  $gapsql->finish();
  $celltip .= "\n $gaplen secs in total" if $r->{'ngaps'} > 1;
  $c->{'celltip'} .= $celltip;
  $c->{'gaplen'} = $gaplen;
}

sub showdoy($$$$$) {
  my ($dbh, $dayReqd, $prevDay, $nextDay, $showNav) = @_;
  my ($year, $mon, $dd, $doy) = Day2Date($dayReqd);

  my $aref = $dbh->selectall_arrayref(q{
      select s.site, s.ts as sitets, unix_timestamp(now())-unix_timestamp(s.ts) as deltats,
             g.year, g.doy, g.hour, g.quality, g.ngaps, g.ts
      from   locations s, gpssums g
      where  s.freq = 'H'
        and  s.active = 1
        and  g.site = s.site
        and  g.jday = ?
  }, { Slice => {} }, $dayReqd);

  # Build matrix with x=hour and y=site
  my %H = ();
  foreach my $r (@$aref) {
    my $site = $r->{'site'};
    if (!exists $H{$site}) {
      $H{$site}{'_row'} = new Cell(txt => $site, ts => $r->{'sitets'}, deltats => $r->{'deltats'},
                                   url => "?site=$site\&year=$r->{year}\&doy=$r->{doy}");
    }
    my $c = new Cell(row => $r);
    $c->{'celltip'} = "$site/$r->{doy}: $r->{ts}";
    add_gaplist($dbh, $c, $r) if $r->{'ngaps'} > 0;
    $H{$site}{$r->{'hour'}} = $c;
  }

  # Create an empty row for each active site with no sums
  $aref = $dbh->selectall_arrayref(q{
      select site, ts, unix_timestamp(now())-unix_timestamp(ts) as deltats
      from   locations
      where  freq = 'H'
        and  active = 1
  }, { Slice => {} });
  foreach my $r (@$aref) {
    my $site = $r->{'site'};
    if (!exists $H{$site}) {
      $H{$site}{'_row'} = new Cell(txt => $site, ts => $r->{'ts'}, deltats => $r->{'deltats'},
                                   url => "?site=$site\&year=$year\&doy=$doy");
    }
  }

  my $str = qq{
    <table class="gpstab">
    <tr><td title="$year-$mon-$dd" class=doy width=2%>$doy</td>
  };
  my $i = 1;
  foreach my $x ('A'..'X') {
    $str .= "<td class=cap width=2%>$i $x</td>";
    $i++;
  }
  $str .= "<td class=cap width=2%>0 0</td>";
  $str .= "</tr>\n";

  foreach my $site (sort keys %H) {
    my $c = $H{$site}{'_row'};
    my $cl = (defined $c->{'deltats'} && $c->{'deltats'} > 4*3600 ? "capwarn":"cap");
    $str .= "<tr><td class=$cl width=2%";
    $str .= " title=\"$c->{'celltip'}\"" if defined $c->{'celltip'};
    $str .= ">";
    $str .= "<a href=\"$c->{'url'}\">" if defined $c->{'url'}; 
    $str .= $c->{'txt'};
    $str .= "</a>" if defined $c->{'url'};
    $str .= "</td>\n";
    foreach my $h ('a'..'x','0') {
      $c = $H{$site}{$h};
      $str .= (defined $c ? $c->tostring() : "<td width=2% class=missing></td>\n");
    }
    $str .= "</tr>\n";
  }
  $str .= "</table>\n";

  if ($showNav) {
    ($year, $mon, $dd, $doy) = Day2Date($prevDay);
    $str .= "<a href=\"?year=$year&doy=$doy\">Prev ($doy)</a>\n";
    if ($nextDay) {
      ($year, $mon, $dd, $doy) = Day2Date($nextDay);
      $str .= "&nbsp;<a href=\"?year=$year&doy=$doy\">Next ($doy)</a>\n";
    }
  }

  print $str;
}

sub showsum($$$$$) {
  my ($dbh, $site, $year, $doy, $hour) = @_;

  my $aref = $dbh->selectrow_arrayref(q{
	select ts, sumfile from gpssums where site=? and year=? and doy=? and hour=?
  }, undef, $site, $year, $doy, $hour);
  my ($ts, $blob) = ($$aref[0], $$aref[1]);

  my $txt = "";
  if (defined $blob && length($blob) > 0) {
    gunzip \$blob => \$txt;
  }

  print "<html><head><title>Sumfile $site $year:$doy:$hour</title></head><body>\n";
  print "<h1>Sumfile for $site $year/$doy/$hour</h1>\n";
  print "Date processed: $ts<br>\n";
  print "<pre>$txt</pre>\n";

  print "</body></html>\n";
}

sub show24h($$) {
  my ($dbh, $dayReqd) = @_;
  my ($year, $mon, $dd, $doy) = Day2Date($dayReqd);

  my $aref = $dbh->selectall_arrayref(q{
      select g.site, s.ts as sitets, unix_timestamp(now())-unix_timestamp(s.ts) as deltats,
             g.year, g.doy, g.hour, g.jday, g.quality, g.ngaps, g.ts
      from   locations s, gpssums g
      where  g.site = s.site
        and  s.active = 1
        and  g.hour = '0'
        and  g.jday >= ?
        and  g.jday <= ?
  }, { Slice => {} }, $dayReqd-25, $dayReqd);

  my %H = ();
  my (%sites1, %sites2, %sites3, %sites4);
  foreach my $r (@$aref) {
    my $site = $r->{'site'};
    if ($site =~ /^TA\d\d/) { $sites2{$site} = 1; }	# Group by site importance in %sites[1-4]
    else                    { $sites1{$site} = 1 }
    if (!exists($H{$site}{'_row'})) {
      $H{$site}{'_row'} = new Cell(txt => $site, ts => $r->{'sitets'}, deltats => $r->{'deltats'},
                                   url => "?fnc=24h\&site=$site\&doy=$doy");
    }
    my $c = new Cell(row => $r);
    $c->{'celltip'} = "$r->{site}/$r->{doy}: $r->{ts}";
    add_gaplist($dbh, $c, $r) if $r->{'ngaps'} > 0;
    $H{$site}{$r->{'jday'}} = $c;
  }

  my $str = q{
    <table class=gpstab>
    <tr><td class=doy width=2%>SITE</td>
  };
  for (my $i = $dayReqd-25; $i < $dayReqd; $i++) {
    my ($y, $m, $d, $doy) = Day2Date($i);
    $str .= qq{<td class=cap width=2% title="$y-$m-$d">$doy</td>};
  }
  $str .= "</tr>\n";

  my @sites = sort keys %sites1;
  push(@sites, sort keys %sites2);
  push(@sites, sort keys %sites3);
  push(@sites, sort keys %sites4);
  foreach my $site (@sites) {
    my $c = $H{$site}{'_row'};
    $str .= "<tr><td class=cap width=2%";
    $str .= " title=\"Last receive: $c->{'ts'}\"" if defined $c->{'ts'};
    $str .= ">";
    $str .= "<a href=\"$c->{'url'}\">" if defined $c->{'url'}; 
    $str .= $c->{'txt'};
    $str .= "</a>" if defined $c->{'url'};
    $str .= "</td>\n";
    for (my $i = $dayReqd-25; $i < $dayReqd; $i++) {
      $c = $H{$site}{$i};
      if (defined $c) {
        $str .= $c->tostring();
      } else {
        $str .= "<td width=2% class=missing></td>\n";
      }
    }
    $str .= "</tr>\n";
  }
  $str .= "</table>\n";

  ($year, $mon, $dd, $doy) = Day2Date($dayReqd-25);
  $str .= "<a href=\"?fnc=24h\&year=$year\&doy=$doy\">Back ($doy)</a>\n";
  if ($DAYnow > $dayReqd) {
    ($year, $mon, $dd, $doy) = Day2Date($dayReqd+25);
    my $href = ($DAYnow-$dayReqd > 1) ? "?fnc=24h\&year=$year&doy=$doy" : $ENV{'SCRIPT_NAME'};
    $str .= "&nbsp;<a href=\"$href\">Forward ($doy)</a>\n";
  }

  print $str;
}

sub showsite_1h($$$) {
  my ($dbh, $site, $dayReqd) = @_;
  my ($year, $mon, $dd, $doy) = Day2Date($dayReqd);
  my $doyReqd = $doy;

  my $aref = $dbh->selectall_arrayref(q{
	select	site, year, doy, jday, hour, quality, ngaps, ts
	from	gpssums
	where	site = ?
	  and	jday >= ?
	  and	jday <= ?
  }, { Slice => {} }, $site, $dayReqd-35, $dayReqd);

  my %H = ();
  foreach my $r (@$aref) {
    my $jday = $r->{'jday'};
    if (!exists($H{$jday}{'_row'})) {
      ($year, $mon, $dd, $doy) = Day2Date($jday);
      my $txt = sprintf("%4d-%02d-%02d: %d",$year,$mon,$dd,$doy);
      $H{$jday}{'_row'} = new Cell(txt => $txt, url => "?year=$year&doy=$doy");
      $H{$jday}{'_row'}->{'celltip'} = $jday;
    }
    my $c = new Cell(row => $r);
    $c->{'celltip'} = "$r->{ts}";
    add_gaplist($dbh, $c, $r) if $r->{'ngaps'} > 0;
    $H{$jday}{$r->{'hour'}} = $c;
  }

  my $str = "<table class=gpstab>\n";
  $str .= "<tr><td class=doy width=2%>$site hourly</td>";
  my $i = 1;
  foreach my $x ('A'..'X') {
    $str .= "<td class=cap width=2%>$i $x</td>\n";
    $i++;
  }
  $str .= "<td class=cap width=2%>0 0</td>\n";
  $str .= "</tr>\n";
  for (my $jday = $dayReqd; $jday >= $dayReqd-35; $jday--) {
    my $c = $H{$jday}{'_row'};
    $str .= "<tr><td class=cap width=4%";
    $str .= " title=\"$c->{'celltip'}\"" if defined $c->{'celltip'};
    $str .= "><a href=\"$c->{'url'}\">" if defined $c->{'url'}; 
    $str .= $c->{'txt'} if defined $c->{'txt'};
    $str .= "</a>" if defined $c->{'url'};
    $str .= "</td>\n";
    foreach my $h ('a'..'x','0') {
      $c = $H{$jday}{$h};
      if (defined $c) {
        $str .= $c->tostring();
      } else {
        $str .= "<td width=2% class=missing></td>\n";
      }
    }
    $str .= "</tr>\n";
  }
  $str .= "</table>\n";

  ($year, $mon, $dd, $doy) = Day2Date($dayReqd-36);
  $str .= "<a href=\"?site=$site\&year=$year\&doy=$doy\">Prev ($doy)</a>\n";
  if ($dayReqd != $DAYnow) {
    ($year, $mon, $dd, $doy) = Day2Date($dayReqd+36);
    $str .= "&nbsp;<a href=\"?site=$site\&year=$year\&doy=$doy\">Next ($doy)</a>\n";
  }

  print $str;
}

sub showsite_24h($$$) {
  my ($dbh, $site, $dayReqd) = @_;
  my ($year, $mon, $dd, $doy) = Day2Date($dayReqd);
  my $doyReqd = $doy;

  my $aref = $dbh->selectall_arrayref(q{
	select	site, year, doy, jday, hour, quality, ngaps, ts
	from	gpssums
	where	site = ?
	  and	jday > ?
	  and	jday <= ?
	  and	hour = '0'
	order by jday desc
  }, { Slice => {} }, $site, $dayReqd-1000, $dayReqd);

  my %jdays = map { $_->{'jday'} => $_ } @$aref;

  my $o = "<table class=gpstab>\n";
  $o .= "<tr><td class=doy width=2%>$site daily</td><tr>\n";
  for (my $jday = $dayReqd, my $j = 0; $jday > $dayReqd-1000; $jday--, $j++) {
    ($year, $mon, $dd, $doy) = Day2Date($jday);
    if ($j % 25 == 0) {
      $o .= "</tr>\n" if $j > 0;
      my $txt = sprintf("%4d-%02d-%02d: %3d",$year,$mon,$dd,$doy);
      $o .= qq{<tr><td class=cap width=4% title="$jday"><a href="?fnc=24h&site=$site&doy=$doy">$txt</a></td>};
    }
    my $r = $jdays{$jday};
    if (defined $r) {
      my $c = new Cell(row => $r);
      $c->{'celltip'} = sprintf("%d/%d: $r->{ts}", $year, $doy);
      add_gaplist($dbh, $c, $r) if $r->{'ngaps'} > 0;
      $o .= $c->tostring();
    } else {
      $o .= "<td class=missing></td>\n";
    }
  }
  $o .= "</tr>\n</table>\n";

  ($year, $mon, $dd, $doy) = Day2Date($dayReqd-1000);
  $o .= "<a href=\"?fnc=24h\&site=$site\&year=$year\&doy=$doy\">Prev ($doy)</a>\n";
  if ($dayReqd != $DAYnow) {
    ($year, $mon, $dd, $doy) = Day2Date($dayReqd+1000);
    $o .= "&nbsp;<a href=\"?fnc=24h\&site=$site\&year=$year\&doy=$doy\">Next ($doy)</a>\n";
  }
  print $o;
}

### MAIN ###

my $cgi = new CGI;
print $cgi->header;

my $dbh = DBI->connect("DBI:mysql:gps","gpsuser","gpsuser");
if (!defined $dbh) {
  print qq{
    <html><body>
    <script language="Javascript">
    <!--
    function reload() { location = "$ENV{'SCRIPT_NAME'}" }
    setTimeout("reload()", 15000);
    //-->
    </script>
    Problem connecting to MySQL backend. Page will reload in 15 seconds.
    </body></html>
  };
  exit(0);
}

my $fnc = $cgi->param('fnc');
$fnc = "1h" unless defined $fnc;
my $site = $cgi->param('site');
my $year = $cgi->param('year');
my $doy = $cgi->param('doy');
my $hour = $cgi->param('hour');

my $dayReqd = $DAYnow;
if (defined $year && $year ne "" && defined $doy && $doy ne "") {
  my ($y, $m, $d) = Doy2Date($year, $doy);
  $dayReqd = Date2Day($y, $m, $d);
}
my $nextDay = ($dayReqd == $DAYnow ? 0 : $dayReqd + 1);

if ($fnc eq "showsum" && defined $site && defined $year && defined $doy && defined $hour) {
  showsum($dbh, $site, $year, $doy, $hour);
}
elsif ($fnc eq "24h" && defined $site) {
  showheader(0);
  showsite_24h($dbh, $site, $dayReqd);
  showbottom(1, $site, $year, $doy);
}
elsif ($fnc eq "24h") {
  showheader(0);
  show24h($dbh, $dayReqd);
  showbottom(1, undef, $year, $doy);
}
elsif ($fnc eq "1h" && defined $site && defined $year && defined $doy) {
  showheader(0);
  showsite_1h($dbh, $site, $dayReqd);
  showbottom(0, $site, $year, $doy);
}
elsif (($fnc eq "1h" && !defined $year && !defined $doy) || $dayReqd == $DAYnow) {
  showheader(1);
  showdoy($dbh, $dayReqd, $dayReqd-1, $nextDay, 0);
  showdoy($dbh, $dayReqd-1, $dayReqd-2, $dayReqd, 1);
  showbottom(0, undef, $year, $doy);
}
elsif ($fnc eq "1h" && defined $year && defined $doy) {
  showheader(0);
  showdoy($dbh, $dayReqd, $dayReqd-1, $nextDay, 1);
  showbottom(0, undef, $year, $doy);
}

$dbh->disconnect();
exit(0);
