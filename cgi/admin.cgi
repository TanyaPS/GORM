#!/usr/bin/perl

use strict;
use warnings;
use CGI;
use DBI;

use lib '/usr/local/lib/gnss';
use BaseConfig;
use Utils;
use GPSDB;

my @GPSTYPES = qw(GEODETIC NON_GEODETIC NON_PHYSICAL SPACEBORNE GROUND_CRAFT WATER_CRAFT AIRBORNE FIXED_BUOY FLOATING_ICE GLACIER BALISTIC ANIMAL HUMAN);

my $cgi = new CGI;
print $cgi->header;

my $DB = new GPSDB;
my $dbh = $DB->DBH;
if (!defined $dbh) {
  print "MySQL connect error\n";
  exit(0);
}
sub showheader($) {
  my $title = shift;

  print "<!DOCTYPE html>\n";
  print "<html><head><title>$title</title></head>\n<body>\n";
  print "<h1>$title</h1>\n";
  # warningsToBrowser(1);
}

sub showbottom() {
  print "<br><br><a href=\"?cmd=menu\">Goto Main Menu</a>\n";
  print "</body></html>\n";
}

sub print_err($) {
  my $txt = shift;

  showheader("Error");
  print "<b>$txt</b>\n";
  showbottom();
}

sub gen_option_list($$) {
  my ($default, $vals) = @_;
  $default = "" unless defined $default;
  my $str = "";
  foreach my $p (@$vals) {
    $str .= "<option name=\"$p\"".($p eq $default ? " selected":"").">$p</option>";
  }
  return $str;
}

# Send a command to jobengine
sub sendcommand($) {
  my $cmd = shift;

  open(my $fd, '>', "$JOBQUEUE/command");
  print $fd "$cmd\n";
  close($fd);
}

##########################################################################
# New site
#
sub newsite() {
  showheader("New site");

  if (defined $cgi->param('submit')) {
    my %v = map { $_ => $cgi->param($_) } $cgi->param;
    my $site = $v{'site'};
    $v{'markernumber'} = undef if defined $v{'markernumber'} && $v{'markernumber'} =~ /^\s*$/;
    $v{'position'} = undef unless defined $v{'position'} && scalar(split(/,/,$v{'position'})) == 3;
    $v{'observer'} = 'SDFE' unless defined $v{'observer'} && $v{'observer'} !~ /^\s*$/;
    $v{'agency'} = 'SDFE' unless defined $v{'agency'} && $v{'agency'} !~ /^\s*$/;
    $v{'freq'} = 'D' unless defined $v{'freq'} && $v{'freq'} =~ /^[DH]$/;
    $v{'active'} = 0 unless defined $v{'active'};
    if (!defined $site || length($site) != 9) {
      print "<B style=\"color:red\">Site must be specified and must be 9 characters long (SSSS00DNK)</b><p>\n";
    } elsif (!defined $v{'obsint'} || $v{'obsint'} <= 0) {
      print "<B style=\"color:red\">Obsint must be specified and must be larger than 0</b><p>\n";
    } else {
      $site = uc($site);
      $v{'shortname'} = substr($site, 0, 4) unless defined $v{'shortname'} && $v{'shortname'} =~ /^[A-Z0-9]{4}$/;
      $v{'shortname'} = uc($v{'shortname'});
      my $res = $dbh->selectrow_arrayref("select 1 from locations where site=?", undef, $site);
      if (defined $res && $res->[0] eq '1') {
        print "<B style=\"color:red\">ERROR: $site already exists!</b><p>\n";
      } else {
        $dbh->do(q{
	  insert into locations
	  (site, shortname, freq, obsint, markernumber, markertype, position, observer, agency, active)
	  values (?,?,?,?,?,?,?,?,?,?)
        }, undef, $site, $v{'shortname'}, $v{'freq'}, $v{'obsint'}, $v{'markernumber'}, $v{'markertype'},
           $v{'position'}, $v{'observer'}, $v{'agency'}, $v{'active'});
        print "<B style=\"color:red\">Site $site created</B><P>\n";
      }
    }
  }

  print qq{
	<form name=newsite method=POST action="$ENV{'SCRIPT_NAME'}">
	<input type=hidden name=cmd value=newsite>
	<table border=1><tr><th>Parameter</th><th align=left>Value</th></tr>
	<tr><td>Sitename (9ch)</td><td><input type=text name=site size=9 maxlength=9></td></tr>
	<tr><td>Sitename (4ch)</td><td><input type=text name=shortname size=4 maxlength=4></td></tr>
	<tr><td>Markernumber</td><td><input type=text name=markernumber size=20 maxlength=20></td></tr>
	<tr><td>Markertype</td><td><select name=markertype>}.gen_option_list("",\@GPSTYPES).qq{</select></td></tr>
	<tr><td>Position (X,Y,Z)</td><td><input type=text name=position size=40 maxlength=40></td></tr>
	<tr><td>Observer</td><td><input type=text name=observer size=20 maxlength=20></td></tr>
	<tr><td>Agency</td><td><input type=text name=agency size=20 maxlength=20></td></tr>
	<tr><td>Freq</td><td><select name=freq>}.gen_option_list("Hourly",['Hourly','Daily']).qq{</select></td></tr>
	<tr><td>Interval</td><td><input type=number name=obsint value=1></td></tr>
	<tr><td>Active</td><td><input type=checkbox name=active value=1 checked></td></tr>
	<tr><td colspan=2><input type=submit name=submit value=Save></td></tr>
	</table></form>
	<p>
	If Marker Number is blank and Marker Number is Unknown in original file, set Marker Number to short sitename.<br>
	If Marker number is blank and Marker number is set in original file, do not change original.<br>
	if Marker number is, always redefine Marker number in file.<br>
	Position is only altered if specified.<br>
	Observer and Agency defaults to <i>SDFE</i>.<br>
  };
  showbottom();
}

##########################################################################
# Show sitelist
#
sub showsitelist() {
  showheader("Site list");

  my %h = ();
  my $aref = $dbh->selectall_arrayref("select site from locations where freq='H' order by site", { Slice => {} });
  my $i = 0;
  print "<b>Hourly sites</b><br>\n";
  foreach my $r (@$aref) {
    print "<br>\n" if $i++ % 10 == 0;
    print "<a href=\"?cmd=editsite&site=$r->{site}\">$r->{site}</a>\n";
  }
  print "<br>\n";

  $aref = $dbh->selectall_arrayref("select site from locations where freq='D' order by site", { Slice => {} });
  $i = 0;
  print "<p><B>Daily sites</B><br>\n";
  foreach my $r (@$aref) {
    print "<br>\n" if $i++ % 20 == 0;
    print "<a href=\"?cmd=editsite&site=$r->{site}\">$r->{site}</a>\n";
  }
  print "<br>\n";

  showbottom();
}

##########################################################################
# Edit antennas for site
#
sub editantennas() {
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  showheader("Edit ".$v{'site'}." antennas");

  if (defined $v{'submit'}) {
    sub checkantrow($$) {
      my ($r,$x) = @_;
      my $msg = "";
      if (index($$r{"anttype$x"},',') < 0) {
        $msg .= "Antenna type format: product,type<br>";
      } elsif ($$r{"antdelta$x"} !~ /\d+,\d+,\d+/) {
        $msg .= "Delta format: X,Y,Z<br>";
      } elsif ($$r{"startdate$x"} !~ /[0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}/) {
        $msg .= "Date format: YYYY-MM-DD HH:MI:SS";
      } elsif (defined $$r{"enddate$x"} &&
               $$r{"enddate$x"} !~ /[0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}/) {
        $msg .= "Date format: YYYY-MM-DD HH:MI:SS" if $$r{"enddate$x"} !~ /^\s*$/;
      }
      return $msg;
    }
    my $sql = $dbh->prepare(q{
	update antennas set anttype=?, antsn=?, antdelta=?, startdate=?, enddate=?
	where	id=?
    });
    for (my $i = 0; defined $v{"id$i"}; $i++) {
      $v{"enddate$i"} = undef if $v{"enddate$i"} =~ /^\s*$/;
      my $msg = checkantrow(\%v,$i);
      if (length($msg) > 0) {
        print qq{<b style="color:red">$msg</b>}."\n";
      } else {
        $sql->execute($v{"anttype$i"}, $v{"antsn$i"}, $v{"antdelta$i"}, $v{"startdate$i"}, $v{"enddate$i"}, $v{"id$i"});
      }
    }
    if (defined $v{'id'} && $v{'id'} eq 'new' && $v{'anttype'} !~ /^\s*$/) {
      $v{"enddate"} = undef if $v{"enddate"} =~ /^\s*$/;
      my $msg = checkantrow(\%v,"");
      if (length($msg) > 0) {
        print qq{<b style="color:red">$msg</b>}."\n";
      } else {
        $dbh->do(q{ insert into antennas (site, anttype, antsn, antdelta, startdate, enddate) values (?,?,?,?,?,?) },
                 undef, $v{'site'}, $v{'anttype'},$v{'antsn'},$v{'antdelta'},$v{'startdate'},$v{'enddate'});
        print q{<b style="color:blue">Values saved</b>}."\n";
      }
    }
  } else {
    for (my $i = 0; defined $v{"id$i"}; $i++) {
      next unless defined $v{"del$i"};
      $dbh->do(q{ delete from antennas where id=? }, undef, $v{"id$i"});
      last;
    }
  }

  my $aref = $dbh->selectall_arrayref(q{
	select	id, anttype, antsn, antdelta, startdate, enddate
	from	antennas
	where	site = ?
	order by site, startdate
  }, { Slice => {} }, $v{'site'});

  print qq{
	<form name=editantennas method=POST action=$ENV{'SCRIPT_NAME'}>
	<input name=cmd type=hidden value=editantennas>
	<input name=site type=hidden value=$v{site}>
	<table border=1>
	<tr><th align=left>Antenna type</th><th>Antenna S/N</th><th>Delta</th><th>Startdate</th><th>Enddate</th><th>Action</th></tr>
  };
  sub printantrow(;$$) {
    my ($r, $i) = @_;
    if (!defined $r) {
      $r = { id=>'new', anttype=>'', antsn=>'', antdelta=>'', startdate=>'', enddate=>'' };
      $i = "";
    } elsif (!defined $r->{'enddate'}) {
      $r->{'enddate'} = '';
    }
    print qq{
	<tr>
        <td><input type=hidden name=id$i value=$r->{id}>
	    <input type=text name=anttype$i value="$r->{anttype}" size=20></td>
	<td><input type=text name=antsn$i value="$r->{antsn}" size=20></td>
	<td><input type=text name=antdelta$i value="$r->{antdelta}" size=20></td>
	<td><input type=text name=startdate$i value="$r->{startdate}" size=20></td>
	<td><input type=text name=enddate$i value="$r->{enddate}" size=20></td>
    };
    print "<td><input type=submit name=del$i value=Delete></td>\n" if $r->{'anttype'} ne '';
    print "</tr>\n";
  }
  my $i = 0;
  printantrow($_, $i++) foreach @$aref;
  printantrow();
  print qq{
	</table>
	<input type=submit name=submit value=Save>
	&nbsp;&nbsp;&nbsp;<a href="?cmd=menu">Main menu</a>
	&nbsp;&nbsp;&nbsp;<a href="?cmd=editsite&site=$v{site}">Edit $v{site}</a>
	</form>
  };
}

##########################################################################
# Edit receivers for site
#
sub editreceivers() {
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  showheader("Edit ".$v{'site'}." receivers");

  if (defined $v{'submit'}) {
    sub checkrcvrow($$) {
      my ($r,$x) = @_;
      my $msg = "";
      if (!defined $$r{"recsn$x"} || $$r{"recsn$x"} =~ /^\s*$/) {
        $msg .= "Receiver S/N is mandatory";
      } elsif (!defined $$r{"rectype$x"} || $$r{"rectype$x"} =~ /^\s*$/) {
        $msg .= "Receiver type format: product,type<br>";
      } elsif (!defined $$r{"firmware$x"} || $$r{"firmware$x"} =~ /^\s*$/) {
        $msg .= "Receiver firmware is mandatory";
      } elsif ($$r{"startdate$x"} !~ /[0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}/) {
        $msg .= "Date format: YYYY-MM-DD HH:MI:SS";
      } elsif (defined $$r{"enddate$x"} &&
               $$r{"enddate$x"} !~ /[0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}/) {
        $msg .= "Date format: YYYY-MM-DD HH:MI:SS" if $$r{"enddate$x"} !~ /^\s*$/;
      }
      return $msg;
    }
    my $sql = $dbh->prepare(q{
	update receivers set recsn=?, rectype=?, firmware=?, startdate=?, enddate=?
	where	id=?
    });
    for (my $i = 0; defined $v{"id$i"}; $i++) {
      $v{"enddate$i"} = undef if $v{"enddate$i"} =~ /^\s*$/;
      my $msg = checkrcvrow(\%v,$i);
      if (length($msg) > 0) {
        print qq{<b style="color:red">$msg</b>}."\n";
      } else {
        $sql->execute($v{"recsn$i"}, $v{"rectype$i"}, $v{"firmware$i"}, $v{"startdate$i"}, $v{"enddate$i"}, $v{"id$i"});
      }
    }
    if (defined $v{'id'} && $v{'id'} eq 'new' && $v{'recsn'} !~ /^\s*$/) {
      $v{"enddate"} = undef if $v{"enddate"} =~ /^\s*$/;
      my $msg = checkrcvrow(\%v,"");
      if (length($msg) > 0) {
        print qq{<b style="color:red">$msg</b>}."\n";
      } else {
        $dbh->do(q{ insert into receivers (site, recsn, rectype, firmware, startdate, enddate) values (?,?,?,?,?,?) },
                 undef, $v{'site'}, $v{'recsn'},$v{'rectype'},$v{'firmware'},$v{'startdate'},$v{'enddate'});
        print q{<b style="color:blue">Values saved</b>}."\n";
      }
    }
  } else {
    for (my $i = 0; defined $v{"id$i"}; $i++) {
      next unless defined $v{"del$i"};
      $dbh->do(q{ delete from receivers where id=? }, undef, $v{"id$i"});
      last;
    }
  }

  my $aref = $dbh->selectall_arrayref(q{
	select	id, recsn, rectype, firmware, startdate, enddate
	from	receivers
	where	site = ?
	order by site, startdate
  }, { Slice => {} }, $v{'site'});

  print qq{
	<form name=editreceivers method=POST action=$ENV{'SCRIPT_NAME'}>
	<input name=cmd type=hidden value=editreceivers>
	<input name=site type=hidden value=$v{site}>
	<table border=1>
	<tr><th align=left>Receiver S/N</th><th>Receiver type</th><th>Firmware</th><th>Startdate</th><th>Enddate</th><th>Action</th></tr>
  };
  sub printrcvrow(;$$) {
    my ($r, $i) = @_;
    if (!defined $r) {
      $r = { id=>'new', recsn=>'', rectype=>'', firmware=>'', startdate=>'', enddate=>'' };
      $i = "";
    } elsif (!defined $r->{'enddate'}) {
      $r->{'enddate'} = '';
    }
    print qq{
	<tr>
        <td><input type=hidden name=id$i value=$r->{id}>
	    <input type=text name=recsn$i value="$r->{recsn}" size=20></td>
	<td><input type=text name=rectype$i value="$r->{rectype}" size=20></td>
	<td><input type=text name=firmware$i value="$r->{firmware}" size=20></td>
	<td><input type=text name=startdate$i value="$r->{startdate}" size=20></td>
	<td><input type=text name=enddate$i value="$r->{enddate}" size=20></td>
    };
    print "<td><input type=submit name=del$i value=Delete></td>\n" if $r->{'recsn'} ne '';
    print "</tr>\n";
  }
  my $i = 0;
  printrcvrow($_, $i++) foreach @$aref;
  printrcvrow();
  print qq{
	</table>
	<input type=submit name=submit value=Save>
	&nbsp;&nbsp;&nbsp;<a href="?cmd=menu">Main menu</a>
	&nbsp;&nbsp;&nbsp;<a href="?cmd=editsite&site=$v{site}">Edit $v{site}</a>
	</form>
  };
}

##########################################################################
# Edit site parameters.
#
sub editsite() {
  my $site = $cgi->param('site');

  showheader("Edit site $site");

  if (defined $cgi->param('submit')) {
    my %v = map { $_ => $cgi->param($_) } $cgi->param;
    $v{'shortname'} = substr($site, 0, 4) unless defined $v{'shortname'} && $v{'shortname'} =~ /^[A-Z0-9]{4}$/i;
    $v{'shortname'} = uc($v{'shortname'});
    $v{'active'} = 0 unless defined $v{'active'};
    $v{'markernumber'} = undef if defined $v{'markernumber'} && $v{'markernumber'} =~ /^\s*$/;
    $v{'position'} = undef unless defined $v{'position'} && scalar(split(/,/,$v{'position'})) == 3;
    $v{'observer'} = 'SDFE' unless defined $v{'observer'} && $v{'observer'} !~ /^\s*$/;
    $v{'agency'} = 'SDFE' unless defined $v{'agency'} && $v{'agency'} !~ /^\s*$/;
    $v{'freq'} = 'D' unless defined $v{'freq'} && $v{'freq'} =~ /^[DH]$/;
    if (!defined $v{'obsint'} || $v{'obsint'} <= 0) {
      print "<b>ERROR: Observation internval must be specified</b><p>\n";
    } else {
      $dbh->do(q{
	update	locations
	set	shortname=?, freq=?, obsint=?, markernumber=?, markertype=?, position=?, observer=?, agency=?, active=?
	where	site = ?
      }, undef, $v{'shortname'}, $v{'freq'}, $v{'obsint'}, $v{'markernumber'}, $v{'markertype'},
                $v{'position'}, $v{'observer'}, $v{'agency'}, $v{'active'}, $site);
      print "<b>Values saved!</b><br>\n";
    }
  }

  my $r = $dbh->selectrow_hashref(q{
	select	shortname, freq, obsint, markernumber, markertype, position, observer, agency, active
	from	locations
	where	site = ?
  }, undef, $site);

  if (!defined $r) {
    print "<b>ERROR: Site $site not found?!</b>\n";
    showbottom();
    return;
  }

  print qq{
	<form name=editsite method=POST action=$ENV{'SCRIPT_NAME'}>
	<input name=cmd type=hidden value=editsite>
	<input name=site type=hidden value=$site>
	<table border=1>
	<tr><th align=left>Parameter</th><th align=left>Value</th></tr>
	<tr><td>Site</td><td>$site</td></tr>
	<tr><td>Site 4ch</td>
	     <td><input name=shortname type=text value="$r->{shortname}"></td></tr>
	<tr><td title="Markernumer">Markernumber</td>
	     <td><input name=markernumber type=text value="$r->{markernumber}"></td></tr>
	<tr><td title="Markertype">Markertype</td>
	    <td><select name=markertype>
  };
  print gen_option_list($r->{'markertype'}, \@GPSTYPES);
  print "</select></td></tr>\n";
  print "<tr><td title=\"Daily for 24h files, Hourly for 1h-files\">Freq</td>";
  print "    <td><select name=freq>".
	"  <option value=D".($r->{'freq'} eq 'D' ? ' selected':'').">Daily</option>".
	"  <option value=H".($r->{'freq'} eq 'H' ? ' selected':'').">Hourly</option>".
	"</select></td></tr>\n";

  print "<tr><td title=\"Obs interval in source file\">Interval</td>";
  print "    <td><input name=obsint type=number value=$r->{'obsint'}></td></tr>\n";

  print qq{
    <tr><td title="Position (X,Y,Z)">Position (X,Y,Z)</td>
        <td><input name=position type=text size=40 maxlength=40 value="$r->{position}"></td></tr>
    <tr><td title="Observer">Observer</td>
        <td><input name=observer type=text size=20 maxlength=20 value="$r->{observer}"></td></tr>
    <tr><td title="Agency">Agency</td>
        <td><input name=agency type=text size=20 maxlength=20 value="$r->{agency}"></td></tr>
    <tr><td title="Check if site is active">Active</td>
        <td><input type=checkbox name=active value=1}.($r->{'active'} ? " checked":"").qq{></td></tr>
    </table>

    <br><input name=submit type=submit value=Save>
    &nbsp;&nbsp;&nbsp;<a href="?cmd=sitelist">Back to sitelist</a>
    &nbsp;&nbsp;&nbsp;<a href="?cmd=editrinexdests&site=$site">Edit destinations</a>
    &nbsp;&nbsp;&nbsp;<a href="?cmd=editantennas&site=$site">Edit antennas</a>
    &nbsp;&nbsp;&nbsp;<a href="?cmd=editreceivers&site=$site">Edit receivers</a>
    </form>
    <p>
    Site 4ch must match first 4 letters on incoming files.<br>
    If Marker Number is blank and Marker Number is Unknown in original file, set Marker Number to short sitename.<br>
    If Marker number is blank and Marker number is set in original file, do not change original.<br>
    if Marker number is, always redefine Marker number in file.<br>
    Position is only altered if specified.<br>
    Observer and Agency defaults to <i>SDFE</i>.<br>
  };

  showbottom();
}

##########################################################################
# Edit RINEX destinations
#
sub editrinexdests() {
  my $site = $cgi->param('site');
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  my @filetypes = qw(Obs Nav Raw Arc Sum);
  my $sql;

  showheader("RINEX distribution for $site");

  if (defined $cgi->param('submit')) {
    $sql = $dbh->prepare(q{
		update	rinexdist
		set	freq = ?, filetype = ?, obsint = ?, localdir = ?, active = ?
		where	id = ?
    });
    for (my $i = 1; defined $v{"id$i"}; $i++) {
      $v{"obsint$i"} = 0 unless defined $v{"obsint$i"};
      $v{"active$i"} = 0 unless defined $v{"active$i"};
      $sql->execute($v{"freq$i"}, $v{"filetype$i"}, $v{"obsint$i"}, $v{"localdir$i"}, $v{"active$i"}, $v{"id$i"});
    }
    $sql->finish();
    if (defined $v{'freq'} && $v{'freq'} ne "") {
      print "New value for $site!<br>\n";
      $v{'obsint'} = '1' unless (defined $v{'obsint'} && $v{'obsint'} =~ /^(1|30)$/);
      $v{'active'} = '0' unless (defined $v{'active'} && $v{'active'} =~ /^(0|1)$/);
      $dbh->do(q{
	insert into rinexdist (site, freq, filetype, obsint, localdir, active) values (?, ?, ?, ?, ?, ?)
      }, undef, $site, $v{'freq'}, $v{'filetype'}, $v{'obsint'}, $v{'localdir'}, $v{'active'});
    }
    print "<B style=\"color:red\">Values saved!</B><P>\n";
  } else {
    for (my $i = 1; defined $v{"id$i"}; $i++) {
      next unless defined $v{"del$i"};
      $dbh->do("delete from rinexdist where id=?", undef, $v{"id$i"});
      print "<B style=\"color:red\">Value id ".$v{"id$i"}." deleted!</B><P>\n";
    }
  }

  my $aref = $dbh->selectall_arrayref("select name from localdirs order by name", { Slice => {} });
  my @localdirs = map { $_->{'name'} } @$aref;

  $sql = $dbh->prepare(q{
	select	id, site, freq, filetype, obsint, localdir, active
	from	rinexdist
	where	site = ?
	order by freq, localdir
  });
  $sql->execute($site);
  print qq{
	<script type="text/javascript"><!--
	function chg(filetype,obsint) {
          if (filetype.value != 'Obs') { obsint.value = 0; obsint.disabled = true; } else obsint.disabled = false;
	}
	--></script>
	<table border=0 cellspacing=20>
	<tr valign=top><td>
	<form name="rinexdistform" method=POST action="$ENV{'SCRIPT_NAME'}">
	<input type=hidden name=cmd value=editrinexdests>
	<input type=hidden name=site value=$site>
	<table border=1>
	<tr><td>Freq<td>Filetype<td>Obsint<td>Localdir<td>Active<td>Action</tr>
  };
  my $i = 1;
  while (my $r = $sql->fetchrow_hashref()) {
    my $freqD = ($r->{'freq'} eq "D" ? "selected":"");
    my $freqH = ($r->{'freq'} eq "H" ? "selected":"");
    my $colcolor = ($r->{'active'} ? "#99E699":"#FFC0C0");
    my $disabled = ($r->{'filetype'} eq "Obs" ? "" : "disabled");
    print qq{
        <tr style="background-color:$colcolor;">
	  <input type=hidden name=id$i value=$r->{'id'}>
	  <td><select name=freq$i><option value=D $freqD>Daily<option value=H $freqH>Hourly</select>
	  <td><select name=filetype$i onchange=chg(this,obsint$i)>}.gen_option_list($r->{'filetype'},\@filetypes).qq{</select>
	  <td><input type=number size=5 name=obsint$i value=$r->{'obsint'} $disabled>
	  <td><select name=localdir$i>}.gen_option_list($r->{'localdir'},\@localdirs).qq{</select>
	  <td><input type=checkbox name=active$i value=1}.($r->{'active'} ? " checked":"").qq{>
	  <td><input type=submit name=del$i value=Delete>
	</tr>
    };
    $i++;
  }
  $sql->finish();
  print qq{
	<tr>
	  <td><select name=freq id=freq><option value=D>Daily<option value=H>Hourly</select>
	  <td><select name=filetype id=filetype onchange=chg(this,obsint)>}.gen_option_list("",\@filetypes).qq{</select>
	  <td><input type=number size=5 name=obsint disabled>
	  <td><select name=localdir id=localdir>}.gen_option_list("",\@localdirs).qq{</select>
	  <td><input type=checkbox name=active value=1>
	</tr>
	<tr>
	  <td colspan=5><input type=submit name=submit Value=Save>
	  &nbsp;&nbsp;<a href="?cmd=editrinexdests&site=$site">Refresh</a>
          &nbsp;&nbsp;<a href="?cmd=editsite&site=$site">Edit $site</a>
          &nbsp;&nbsp;<a href="?cmd=sitelist">Site list</a>
	</tr>
	</table></form>
	</td>
	<td valign=top>
	  <b>Freq</b> can eighter be <i>Daily</i> or <i>Hourly</i>.<br>
	  <b>Filetype</b> is one of:<br>
	  &nbsp;&nbsp;<i>Obs</i>: Observation file in Hatanaka packed compressed format.<br>
	  &nbsp;&nbsp;<i>Nav</i>: Navigation files in compressed format.<br>
	  &nbsp;&nbsp;<i>Raw</i>: Unmodified original file(s).<br>
	  &nbsp;&nbsp;<i>Arc</i>: ZIP file containing original unmodified file(s).<br>
	  &nbsp;&nbsp;<i>Sum</i>: Sum file in gzipped format<br>
          <b>Obsint</b>: Destination internval. If source is 1 sec interval, destination RINEX file
		  will be decimated to this interval. Only relevant for observation file rules.<br>
	  <b>Localdir</b>: Destination path. Must be pre-defined.<br>
	  <b>Active</b>: Wether or not this distribution rule is active.<br>
	  <b>Action</b>: Delete rule.
        </td></tr>
	</table>
	<script type="text/javascript"><!--
	  document.getElementById("freq").selectedIndex = -1;
	  document.getElementById("filetype").selectedIndex = -1;
	  document.getElementById("localdir").selectedIndex = -1;
        --></script>
  };

  showbottom();
}

##########################################################################
# Edit localdirs
#
sub editlocaldirs() {
  showheader("Localdirs");
  my %v = map { $_ => $cgi->param($_) } $cgi->param;

  if (defined $v{'submit'}) {
    # Updates
    my $href = $dbh->selectall_hashref(q{ select name, path from localdirs }, 'name');
    my $sql = $dbh->prepare("update localdirs set path = ? where name = ?");
    for (my $i = 0; defined $v{"name$i"}; $i++) {
      next if $href->{$v{"name$i"}}->{'path'} eq $v{"path$i"};
      $sql->execute($v{"path$i"}, $v{"name$i"});
      print "<B style=\"color:red\">WARNING! Localdir $v{path} not found!!</B><P>\n" unless -d $v{"path$i"};
    }
    # New value
    if (defined $v{'name'} && defined $v{'path'} && $v{'path'} !~ /^\s*$/) {
      $dbh->do("insert into localdirs (name,path) values (?,?)", undef, $v{'name'}, $v{'path'});
    }
  } else {
    # Check for deletes
    for (my $i = 0; defined $v{"name$i"}; $i++) {
      if (defined $v{"del$i"}) {
        my $n = $v{"name$i"};
        $dbh->do("delete from localdirs where name=?", undef, $n);
        $dbh->do("delete from rinexdist where localdir=?", undef, $n);
        $dbh->do("delete from uploaddest where localdir=?", undef, $n);
        print "<B style=\"color:red\">Localdir definition $n deleted!</B><P>\n";
        last;
      }
    }
  }

  print qq{
	<b style="color:blue">WARNING! Deleting a localdir definition will also delete all RINEX destinations and/or FTP upload definitions for that path!</b><br>
	<p>
	<form name=pathform method=POST action=$ENV{'SCRIPT_NAME'}>
	<input type=hidden name=cmd value=editlocaldirs>
	<table border=1>
	<tr><th>Name<th>Localdir<th>Action</tr>
  };
  my $aref = $dbh->selectall_arrayref("select name, path from localdirs order by name", { Slice => {} });
  my $i = 0;
  foreach my $r (@$aref) {
    print qq{
	<tr><td><input type=hidden name=name$i value="$r->{'name'}">$r->{'name'}</td>
	<td><input type=text name=path$i size=120 value="$r->{'path'}"></td>
	<td><input type=submit name=del$i value=Delete></td></tr>
    };
    $i++;
  }
  print q{
	<tr><td><input type=text size=20 name=name></td>
	<td><input type=text name=path size=120></td><td></td></tr>
	<tr><td colspan=3><input type=submit name=submit value=Save></td></tr>
	</table></form>
  };
  print "Localdir definitions are used in Rinex distribution rules and in Uploader rules.<br>\n";
  print "Localdir names for paths to used by Uploader <b>must</b> be prefixed with <i>ftp- or sftp-</i> and they <b>must</b> reside in /data/upload\n";
  showbottom();
}

##########################################################################
# Edit FTP upload destinations.
#
sub uploaddest() {
  showheader("FTP/SFTP Upload Destinations");
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  #print "<!-- "; print "v{$_}=$v{$_} " foreach keys %v; print "-->\n";

  print "Remember to create localdir before defining a FTP uploader.<p>\n";

  my @collist = qw(name protocol host user pass localdir remotedir active);
  my $sql;

  my $aref = $dbh->selectall_arrayref(q{
	select name from localdirs where name like 'ftp-%' or name like 'sftp-%' order by name
  }, { Slice => {} });
  my @uploadpaths = map { $_->{'name'} } @$aref;

  my $changed = 0;
  if (defined $cgi->param('submit')) {
    sub checkpath($$) {
      my ($name, $path) = @_;
      if (index($path, '/') != 0) {
        print "<b style=\"color:red\">Path ".$path." ($name) must start with an '/'. Deactivating rule.</b><p>\n";
        return 0;
      }
      return 1;
    }
    sub checklocaldir($) {	# Check if path exists. Disable rule if not.
      my $localdir = shift;
      my $href = $dbh->selectrow_hashref(q{ select path from localdirs where name = ? }, undef, $localdir);
      unless (defined $href && -d $href->{'path'}) {
        print "<b style=\"color:red\">Localdir ".$href->{'path'}." ($localdir) does not exist. Deactivating rule.</b><p>\n";
        return 0;
      }
      return checkpath($localdir, $href->{'path'});
    }
    my $msg = "";
    $sql = $dbh->prepare(q{
	update	uploaddest
	set	name=?, protocol=?, host=?, user=?, pass=?, localdir=?, remotedir=?, active=?
	where	id=?
    });
    for (my $i = 1; defined $v{"id$i"}; $i++) {
      my @vals = ();
      $v{"active$i"} = 0 unless defined $v{"active$i"};
      $v{"active$i"} = checklocaldir($v{"localdir$i"}) if $v{"active$i"};
      $v{"active$i"} = checkpath('remotedir', $v{"remotedir$i"}) if $v{"active$i"};
      push(@vals, $v{"$_$i"}) foreach @collist;
      $sql->execute(@vals, $v{"id$i"});
    }
    $sql->finish();
    if (defined $v{'name'} && $v{'name'} !~ /^\s*$/) {
      $v{'active'} = 0 unless defined $v{'active'};
      $v{'active'} = checklocaldir($v{'localdir'}) if $v{'active'};
      $v{'active'} = checkpath('remotedir', $v{"remotedir"}) if $v{'active'};
      my @vals = ();
      push(@vals, $v{$_}) foreach @collist;
      $dbh->do("insert into uploaddest (".join(',',@collist).") values (?,?,?,?,?,?,?,?)", undef, @vals);
    }
    print "<B style=\"color:red\">Values saved!</B><P>\n";
    $changed = 1;
  } else {
    for (my $i = 1; defined $v{"id$i"}; $i++) {
      if (defined $v{"del$i"}) {
        $dbh->do("delete from uploaddest where id = ?", undef, $v{"id$i"});
        print "<B style=\"color:red\">Dest id ".$v{"id$i"}." deleted!</B><P>\n";
        $changed = 1;
        last;
      }
    }
  }
  sendcommand("reload ftpuploader") if $changed;

  $aref = $dbh->selectall_arrayref(q{
	select id,name,protocol,host,user,pass,localdir,remotedir,active from uploaddest order by name
  }, { Slice=>{} });
  print qq{
	<form name=uploaddestform method=POST action="$ENV{'SCRIPT_NAME'}">
	<input type=hidden name=cmd value=uploaddest>
	<table border=1>\n<tr><td>Name<td>Protocol<td>Host<td>User<td>Pass<td>Localdir<td>Remotedir<td>Active</tr>
  };
  my $i = 1;
  foreach my $r (@$aref) {
    my $colcolor = ($r->{'active'} ? "#99E699":"#FFC0C0");
    print qq{
	<tr style="background-color:$colcolor;">
	<input type=hidden name=id$i value=$r->{'id'}>
	<td><input type=text name=name$i value="$r->{'name'}">
	<td><input type=text name=protocol$i value="$r->{'protocol'}">
	<td><input type=text name=host$i value="$r->{'host'}">
	<td><input type=text name=user$i value="$r->{'user'}">
	<td><input type=text name=pass$i value="$r->{'pass'}">
        <td><select name=localdir$i>}.gen_option_list($r->{'localdir'},\@uploadpaths).qq{</select>
	<td><input type=text name=remotedir$i value="$r->{'remotedir'}">
	<td><input type=checkbox name=active$i value=1}.($r->{'active'} ? " checked":"").qq{>
	<td><input type=submit name=del$i value=Delete></tr>
    };
    $i++;
  }
  print q{
	<tr><td><input type=text name=name>
	<td><input type=text name=protocol>
	<td><input type=text name=host>
	<td><input type=text name=user>
	<td><input type=text name=pass>
	<td><select id=localdir name=localdir>}.gen_option_list("",\@uploadpaths).q{</select>
	<td><input type=text name=remotedir>
	<td><input type=checkbox name=active value=1>
	<tr colspan=8><td><input type=submit name=submit value=Save>
	<a href="?cmd=uploaddest">Reset</a>
	</table>
	</form>
	<script>
          document.getElementById("localdir").selectedIndex = -1;
          document.getElementById("active").selectedIndex = -1;
        </script>
  };
  showbottom();
}

##########################################################################
# Forget DOYs.
# Delete sums and datagaps for a given range of DOY's for a given SITE.
#
sub forget() {
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  showheader("Forget DOYs");

  if (defined $v{'submit'}) {
    my ($site, $year, $fromdoy, $todoy) = ($v{'site'}, $v{'year'}, $v{'fromdoy'}, $v{'todoy'});
    if (defined $site && defined $year && defined $fromdoy) {
      $site = uc($site);
      $year = sy2year($year) if $year < 100;
      $todoy = $fromdoy unless defined $todoy;
      $todoy = $fromdoy if $todoy < $fromdoy;
      print "Forgetting sums for $site/$year/$fromdoy-$todoy.<p>\n";
      $dbh->do(q{ delete from gpssums where site=? and year=? and doy>=? and doy<=? }, undef, $site, $year, $fromdoy, $todoy);
      $dbh->do(q{ delete from datagaps where site=? and year=? and doy>=? and doy<=? }, undef, $site, $year, $fromdoy, $todoy);
    } else {
      print "<b style=\"color:red\">Please specify all values</b><p>\n";
    }
  }

  print qq{
	<form name="forgetform" method=POST action="$ENV{'SCRIPT_NAME'}">
	<input type=hidden name=cmd value=forget>
	<table border=1>
	<tr><td title="ssss00ccc"><b>Site:</b><td><input type=text name=site size=9></tr>
	<tr><td title="yyyy"><b>Year:</b><td><input type=number name=year size=4></tr>
	<tr><td title="ddd"><b>From DOY:</b><td><input type=number name=fromdoy size=3></tr>
	<tr><td title="ddd"><b>To DOY:</b><td><input type=number name=todoy size=3></tr>
	<tr><td colspan=2><input type=submit name=submit value=Forget></tr>
	</table>
	</form>
	<p>
	Forgetting a DOY will delete all QC's, Gaps and Sums for the given site from the database.<br>
	It will NOT delete any files. You will need to reprocess data again.<br>
  };

  showbottom();
}

##########################################################################
# Set 'force-complete' flag for selected site/year/doy's to force
# jobengine to complete the day even if there are missing hours.
#
sub incompletes() {
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  showheader("Incomplete days");

  my @now = gmtime(time());
  my $year = 1900 + $now[5];
  my $doy = Day_of_Year($year, $now[4]+1, $now[3]);

  my $subcmd = $v{'c'};
  if (defined $subcmd && $subcmd eq "complete") {
    my $site = $v{'site'};
    return unless defined $site;
    $site = uc($site);
    my $yd = $v{'yd'};
    return unless defined $yd;
    my ($year, $doy) = split(/:/, $yd);
    sendcommand("force complete $site $year $doy");
  }

  my $nfound = 0;
  my %sites = ();
  open(my $pd, "-|", qq(/bin/find $WORKDIR -type f -print));
  while (<$pd>) {
    chomp();
    $_ = substr($_, length($WORKDIR)+1);
    my @a = split(/\//, $_);
    next if ($a[1] == $year && $a[2] == $doy);	# Ignore today
    my $site = $a[0];
    next unless (-d "$WORKDIR/$site" && $site =~ /^[A-Z0-9]{9}$/i);
    if (defined $sites{$site}) {
      next if index($sites{$site}, "$a[1]:$a[2]") >= 0;
      $sites{$site} .= ",";
    } else {
      $sites{$site} = "";
    }
    $sites{$site} .= "$a[1]:$a[2]";
    $nfound++;
  }
  close($pd);

  if (defined $subcmd && $subcmd eq "all") {
    foreach my $site (sort keys %sites) {
      my @yds = split(/,/, $sites{$site});
      foreach my $yd (sort @yds) {
        my ($year, $doy) = split(/:/, $yd);
        sendcommand("force complete $site $year $doy");
      }
    }
    $cgi->redirect("http://".$cgi->server_name().$cgi->script_name()."?cmd=incompletes");
  }

  print "<a href=\"?cmd=incompletes\">Refresh</a>";
  print "&nbsp; <a href=\"?cmd=incompletes&c=all\">Complete All</a>";
  print "<p>\n";
  if ($nfound == 0) {
    print "No outstanding files found.<br>\n";
  } else {
    print "<table border=1>\n<tr><th>SITE<th>YEAR:DOY<th>Action</tr>\n";
    foreach my $site (sort keys %sites) {
      my @yds = split(/,/, $sites{$site});
      foreach my $yd (sort @yds) {
        print "<tr>\n";
        print " <td>$site\n";
        print " <td>$yd\n";
        print " <td><a href=\"?cmd=incompletes&site=$site&yd=$yd&c=complete\">Complete</a>\n";
        print "</tr>\n";
      }
    }
    print "</table>\n";
  }

  showbottom();
}

##########################################################################
# Reprocess all hours for given site/year/doy's.
#
sub reprocess() {
  my %v = map { $_ => $cgi->param($_) } $cgi->param;
  showheader("Reprocess entire day");

  if (defined $v{'submit'}) {
    my ($site, $year, $fromdoy, $todoy, $uploading) = ($v{'site'}, $v{'year'}, $v{'fromdoy'}, $v{'todoy'});
    if (defined $site && $site ne "" && length($site) == 9 &&
        defined $year && $year ne "" &&
        defined $fromdoy && $fromdoy ne "") {
      $site = uc($site);
      $year = sy2year($year) if $year < 100;
      $todoy = $fromdoy unless defined $todoy && $todoy ne "";
      $fromdoy = $todoy if $fromdoy > $todoy;
      $todoy = $fromdoy if $todoy < $fromdoy;
      my $ok = 1;
      for (my $doy = $fromdoy; $doy <= $todoy; $doy++) {
        my $savedir = sprintf("%s/%s/%4d/%03d", $SAVEDIR, $site, $year, $doy);
        if (! -d $savedir) {
          print "<b style=\"color:red\">$site-$year-$doy not in SAVEDIR.</b> You need to manually forget and re-upload files.<br>";
          $ok = 0;
        }
      }
      if ($ok) {
        print "Submitting reprocess request for $site/$year/$fromdoy-$todoy.<p>\n";
        $dbh->do(q{ delete from gpssums where site=? and year=? and doy>=? and doy<=? }, undef, $site, $year, $fromdoy, $todoy);
        $dbh->do(q{ delete from datagaps where site=? and year=? and doy>=? and doy<=? }, undef, $site, $year, $fromdoy, $todoy);
        sendcommand("reprocess $site $year $fromdoy-$todoy");
      }
    } else {
      print "<b style=\"color:red\">Please specify all values</b><p>\n";
    }
  }

  print qq{
    <form name="reprocessform" method=POST action="$ENV{'SCRIPT_NAME'}">
    <input type=hidden name=cmd value=reprocess>
    <table border=1>
    <tr><td title="Site identifier (xxxx##ccc)">
        <b>Site:</b><td><input type=text name=site size=9></tr>
    <tr><td title="Specify year as YYYY">
        <b>Year:</b><td><input type=number name=year size=4></tr>
    <tr><td title="From DOY">
        <b>From DOY:</b><td><input type=number name=fromdoy size=3></tr>
    <tr><td title="To DOY">
        <b>To DOY:</b><td><input type=number name=todoy size=3></tr>
    <tr><td colspan=2><input type=submit name=submit value=Submit></tr>
    </table>
    <br>
    This will make the system forget and reprocess the specified range of DOY's.
    The source is the zip files in the archive.<br>
    All RINEX files for the specified range will be re-distributed according to RINEX
    distribution scheme.
    </form>
  };

  showbottom();
}

##########################################################################
# Main menu
#
sub menu() {
  showheader("GPSFTP5 Administration");
  print q{
    <a href="?cmd=newsite">New site</a><br>
    <a href="?cmd=sitelist">Edit sites</a><br>
    <a href="?cmd=uploaddest">Edit FTP Upload Destinations</a><br>
    <a href="?cmd=editlocaldirs">Edit Localdirs</a><br>
    <a href="?cmd=forget">Forget DOYs</a><br>
    <a href="?cmd=incompletes">Finish Incomplete DOYs</a><br>
    <a href="?cmd=reprocess">Reprocess DOY's</a><br>
<!--
    <a href="?cmd=editaliases">Edit Aliases</a><br>
    <a href="?cmd=syslog">System log</a><br>
    <a href="?cmd=reproccurr">Reprocess current DOY for one site</a><br>
    <a href="?cmd=mkincomplete">Make one DOY incomplete for one site</a><br>
    <a href="?cmd=qcreport">Show Uptime report for hourly sites</a><br>
-->
    </body></html>
  };
}

##########################################################################
#  *** MAIN ***
#

my $cmd = $cgi->param('cmd');
if (!defined $cmd || $cmd eq "menu") {
  menu();
} elsif ($cmd eq "sitelist") {
  showsitelist();
} elsif ($cmd eq "newsite") {
  newsite();
} elsif ($cmd eq "editsite") {
  editsite();
} elsif ($cmd eq "editlocaldirs") {
  editlocaldirs();
} elsif ($cmd eq "editrinexdests") {
  editrinexdests();
} elsif ($cmd eq "uploaddest") {
  uploaddest();
} elsif ($cmd eq "forget") {
  forget();
} elsif ($cmd eq "incompletes") {
  incompletes();
} elsif ($cmd eq "editantennas") {
  editantennas();
} elsif ($cmd eq "editreceivers") {
  editreceivers();
} elsif ($cmd eq "reprocess") {
  reprocess();
}
