#!/bin/sh

D=`dirname $0`
cd $D/..
D=`pwd`

function errexit() {
  echo "$0: $1" >&2
  exit 2
}

test `id -u` = 0 || errexit "You must be root to run this. Try 'sudo $0'."

while read rpm; do
  rpm -q $rpm >/dev/null || errexit "$rpm not installed. Install using 'rpm install $rpm'"
done <<%EOD
perl-Net-SFTP-Foreign
perl-Linux-Inotify2
perl-Parallel-ForkManager
perl-Time-Local
perl-JSON
perl-JSON-XS
perl-DBI
perl-IO-Compress
perl-Compress-Raw-Zlib
perl-Archive-Zip
perl-Date-Manip
perl-File-Path
httpd
vsftpd
zip
unzip
mariadb
mariadb-server
%EOD

echo "Installing binaries in /usr/local/bin"
unzip -q setup/binaries.zip -d tmp.$$
for i in bin/* tmp.$$/*; do
  install -o root -g bin -m 755 $i /usr/local/bin
done
rm -r tmp.$$

echo "Installing GNSS perl library in /usr/local/lib/gnss"
test -d /usr/local/lib/gnss || mkdir -m 755 /usr/local/lib/gnss
for pm in BaseConfig.pm GPSDB.pm Job.pm Logger.pm RinexSet.pm Utils.pm; do
  install -o root -g root -m 644 $pm /usr/local/lib/gnss
done

echo "Installing CGI programs in /var/www/gnss-cgi"
test -d /var/www/gnss-cgi || mkdir -m 755 /var/www/gnss-cgi
install -o root -g root cgi/status.cgi /var/www/gnss-cgi
install -o root -g root setup/gnss-cgi.conf /etc/httpd/conf.d
apachectl restart

echo "Installing daemons in /usr/local/sbin"
for i in gpspickup jobengine ftpuploader; do
  install -o root -g daemon -m 755 $i /usr/local/sbin
  install -o root -g sys -m 644 setup/$i.service /etc/systemd/system
done

echo "Restarting daemons"
systemctl daemon-reload
systemctl restart gpspickup jobengine ftpuploader

echo "Done"
