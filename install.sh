#!/bin/bash

RSYNC=$( which rsync )
if [ -z "$RSYNC" ]; then
	echo "ERROR: rsync utility not installed! Aborting,"
fi

echo "INFO: Installing BarmanS3 ..."
echo "INFO: Deploying scripts into /opt/barmans3/bin"
mkdir -p /opt/barmans3/bin
$RSYNC -aq src/opt/barmans3/bin/ /opt/barmans3/bin/
chmod +x /opt/barmans3/bin/*

if [ ! -f /opt/barmans3/barmans3.conf ]; then
	echo "INFO: Initializing default config file /opt/barmans3/barmans3.conf" 
	$RSYNC -aq  src/opt/barmans3/barmans3.conf /opt/barmans3/barmans3.conf
fi

echo "INFO: Initializing log files under /var/log/barmans3"
mkdir -p /var/log/barmans3
chmod 750 /var/log/barmans3
touch /var/log/barmans3/walsync.log
touch /var/log/barmans3/basesync.log
chmod 640 /var/log/barmans3/*.log
chown -R barman:barman /var/log/barmans3

echo "INFO: Initializing task queue in /var/run/barmans3/queue.d"
mkdir -p /var/run/barmans3/queue.d
chown -R barman:barman /var/run/barmans3
chmod -R 750 /var/run/barmans3

echo "INFO: All done."
echo
echo "INFO: Please review /opt/barmans3/barmans3.conf"
exit 0
