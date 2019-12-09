#!/usr/bin/perl
#
# Test basic functions in RinexSet.pm
# Look for "NOT ok" on failed tests
#
# Soren Juul Moller, Dec 2019

use RinexSet;
#use Utils;

sub dotest() {
  my $rsfile = "/tmp/$$.json";

  # TA0200DNK_R_20190150000
  my $rs = new RinexSet(site => 'TA0200DNK', year => 2019, doy => 15, hour => '0', arr1 => [0,1,2] );
  $rs->store($rsfile);

  $rs = new RinexSet(rsfile => $rsfile);
  print "Test site ", ($rs->{site} eq "TA0200DNK") ? "ok" : "NOT ok", "\n";
  print "Test year: ", ($rs->{year} == 2019) ? "ok" : "NOT ok", "\n";
  my $ok = 1;
  for (my $i = 0; $i <= 2; $i++) {
    $ok &= (${$rs->{arr1}}[$i] == $i);
  }
  print "arr1: ", $ok ? "ok":"NOT ok", "\n";

  $rs->store($rsfile);
  $rs = new RinexSet;
  print "Test no site: ", ($rs->{site} eq "TA0200DNK") ? "NOT ok" : "ok", "\n";
  $rs->load($rsfile);
  print "Test site: ", ($rs->{site} eq "TA0200DNK") ? "ok" : "NOT ok", "\n";

  my $wdir = $rs->getWorkdir;
  print "Workdir $wdir: ", ($wdir eq "/data/work/TA0200DNK/2019/015") ? 'ok':'NOT ok', "\n";

  my $ofn = $rs->getRinexFilename('MO.1');
  print "obsFilename: $ofn: ", ($ofn eq "TA0200DNK_R_20190150000_01D_01S_MO.rnx") ? "ok":"NOT ok", "\n";

  $rs->{$_} = $rs->getRinexFilename($_) foreach qw(GN RN);
  my $navs = join(' ', $rs->getNavlist);
  print "Navlist GN, RN: ",
	(index($navs,'TA0200DNK_R_20190150000_01D_GN.rnx') >= 0 &&
	 index($navs,'TA0200DNK_R_20190150000_01D_RN.rnx') >= 0) ? 'ok':'NOT ok', "\n";

  unlink($rsfile);
}

dotest();
