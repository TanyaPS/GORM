#!/usr/bin/perl
#
# Test all functions in Utils.pm
# Shows 'FAILED' on failed tests or nothing if no error.
#
# Soren Juul Moller, Dec 2019

use strict;
use warnings;
use Utils;

## sysrun
sub test_sysrun_ok() {
  return sysrun("/bin/test -f $0") == 0;
}

sub test_sysrun_fail() {
  return sysrun("/bin/test ! -f $0") == 1;
}

### syscp
sub test_syscp() {
  syscp($0, '/tmp');
  my $rc = system("cmp -s $0 /tmp/$0");
  unlink("/tmp/$0");
  return $rc == 0;
}

sub test_syscp_array() {
  my $tmp1 = "/tmp/cp1.$$";
  mkdir $tmp1;
  system("cp $0 $tmp1/cp1");
  system("cp $0 $tmp1/cp2");
  my $tmp2 = "/tmp/cp2.$$";
  syscp(["$tmp1/cp1","$tmp1/cp2"], $tmp2, { mkdir => 1, log => 1 });
  my $files1 = `ls $tmp1`;
  my $files2 = `ls $tmp2`;
  system("rm -r $tmp1 $tmp2");
  return $files1 eq $files2;
}

### sysmv
sub test_sysmv() {
  system("cp $0 /tmp");
  sysmv("/tmp/$0", "/tmp/$0.mv");
  my $files = `ls /tmp/$0.mv`;
  unlink("/tmp/$0.mv");
  return $files eq "/tmp/$0.mv\n";
}

sub test_sysmv_array() {
  my $sdir = "/tmp/mv.$$";
  mkdir $sdir;
  system("cp $0 $sdir/cp1");
  system("cp $0 $sdir/cp2");
  my $tdir = "/tmp/target.$$";
  sysmv(["$sdir/cp1","$sdir/cp2"], $tdir, { mkdir => 1, log => 1 });
  my $files = `ls $tdir`;
  system("rm -rf $sdir $tdir");
  return $files eq "cp1\ncp2\n";
}

### readfile and writefile
sub test_readwritefile() {
  my $testfile = "/tmp/testfile.$$";
  my $data = 'testdata';
  my $ok = 0;
  if (writefile($testfile, $data) == 8) {
    $ok = 1 if readfile($testfile) eq $data;
  }
  unlink($testfile);
  return $ok;
}

### Day_of_Year
sub test_Day_of_Year() {
  my $doy = Day_of_Year(2019,11,22);
  return $doy == 326;
}

### Day_of_Date
sub test_Doy_to_Date() {
  my ($y,$m,$d) = Doy_to_Date(2019, 326);
  return $y == 2019 && $m == 11 && $d == 22;
}

### Doy_to_Days
sub test_Doy_to_Days() {
  my $jday = Doy_to_Days(2019, 326);
  return $jday == 737385;
}

### Days_to_Date
sub test_Days_to_Date() {
  my ($y,$m,$d,$doy) = Days_to_Date(737385);
  return $y == 2019 && $m == 11 && $d == 22 && $doy == 326;
}

### Date_to_Days
sub test_Date_to_Days() {
  my $jday = Date_to_Days(2019,11,22);
  return $jday == 737385;
}

### sy2year
sub test_sy2year() {
  return sy2year(19) == 2019 && sy2year(99) == 1999;
}

### year2sy
sub test_year2sy() {
  return year2sy(2019) == 19 && year2sy(1999) == 99;
}

### hour2letter
sub test_hour2letter() {
  return hour2letter(0) eq 'a' && hour2letter(23) eq 'x';
}

### letter2hour
sub test_letter2hour() {
  return letter2hour('a') == 0 && letter2hour('X') == 23 && letter2hour('0') == 0;
}

### gm2str
sub test_gm2str() {
  return gm2str(1572508926) eq "2019-10-31 08:02:06";
}

### basename
sub test_basename() {
  return basename('/tmp/base') eq 'base' && basename('base') eq 'base';
}

### dirname
sub test_dirname() {
  return dirname('/tmp/base') eq '/tmp' && dirname('base') eq '.';
}

### fileage
sub test_fileage() {
  system("cp $0 /tmp/$0.$$; touch /tmp/$0.$$");
  my $age0 = fileage("/tmp/$0.$$");
  sleep(1);
  my $age1 = fileage("/tmp/$0.$$");
  unlink("/tmp/$0.$$");
  return $age1-$age0 == 1;
}

### dirlist
sub test_dirlist() {
  my $tdir = "/tmp/dl.$$";
  mkdir $tdir;
  system("cp $0 $tdir/cp1; cp $0 $tdir/cp2");
  my @files = dirlist($tdir);
  system("rm -r $tdir");
  return $files[0] eq 'cp1' && $files[1] eq 'cp2';
}

### round
sub test_round() {
  return round(3.14) == 3 && round(3.51) == 4 && round(3.16,1) == 3.2;
}

### loadJSON
sub test_loadJSON() {
  open(my $fd, '>', "/tmp/$$.json");
  print $fd q(
    {
       "var1" : "val1",
       "var2" : "val2"
    }
  );
  close($fd);
  my $h = loadJSON("/tmp/$$.json");
  unlink("/tmp/$$.json");
  return $h->{'var1'} eq 'val1' && $h->{'var2'} eq 'val2';
}

### storeJSON
sub test_storeJSON() {
  my %h = qw(var1 val1 var2 val2);
  my $fn = "/tmp/$$.json";
  storeJSON($fn, \%h);
  open(my $fd, '<', $fn);
  my $str; read($fd, $str, -s $fn);
  close($fd);
  unlink($fn);
  my $expt = q({
   "var1" : "val1",
   "var2" : "val2"
}
);
  return $str eq $expt;
}

### site42site
sub test_site42site() {
  return site42site('ARGI') eq 'ARGI00FRO' && site42site('budd') eq 'BUDD00DNK';
}

########################

die("$0: must be runned from same directory using 'perl utils.tst'") if (index($0,'/') >= 0);

test_sysrun_ok() || print "test_sysrun_ok FAILED\n";
test_sysrun_fail() || print "test_synrun_fail FAILED\n";
test_syscp() || print "test_syscp FAILED\n";
test_syscp_array() || print "test_syscp_array FAILED\n";
test_sysmv() || print "test_sysmv FAILED\n";
test_sysmv_array() || print "test_sysmv_array FAILED\n";
test_readwritefile() || print "test_readwritefile FAILED\n";
test_Day_of_Year() || print "test_Day_of_Year FAILED\n";
test_Doy_to_Date() || print "test_Doy_to_Date FAILED\n";
test_Doy_to_Days() || print "test_Doy_to_Days FAILED\n";
test_Days_to_Date() || print "test_Days_to_Date FAILED\n";
test_Date_to_Days() || print "test_Date_to_Days FAILED\n";
test_sy2year() || print "test_sy2year FAILED\n";
test_year2sy() || print "test_year2sy FAILED\n";
test_hour2letter() || print "test_hour2letter FAILED\n";
test_letter2hour() || print "test_letter2hour FAILED\n";
test_gm2str() || print "test_gm2str FAILED\n";
test_basename() || print "test_basename FAILED\n";
test_dirname() || print "test_dirname FAILED\n";
test_fileage() || print "test_fileage FAILED\n";
test_dirlist() || print "test_dirlist FAILED\n";
test_round() || print "test_round FAILED\n";
test_loadJSON() || print "test_loadJSON FAILED\n";
test_storeJSON() || print "test_storeJSON FAILED\n";
test_site42site() || print "test_site42site FAILED\n";
