# BarmanS3
S3 archive scripts for Barman PostgreSQL Backup Server

## About BarmanS3

BarmanS3 consists of 2 separate processes - basebackup sync and WAL archive sync. It uses AWS CLI utility to perform S3 folder sync actions while using script wrappers for orchestration and automation. Currently it consists of 3 scripts, single shared config file and a cron file:

* /opt/barmans3/bin/barmans3-wal-sync: for syncing server WAL archive from Barman to S3 bucket
* /opt/barmans3/bin/barmans3-base-sync: for syncing server basebackup (ie full backup) from Barman to S3 bucket
* /opt/barmans3/bin/barmans3-full-sync: for doing full base & wals sync together with delete (ie cleanup)
* /opt/barmans3/bin/barmans3-queue-add: barman post-backup hook-script for creating  basebackup sync task in barmans3-base-sync queue
* /opt/barmans3/bin/barmans3-base-ls: listing basebackups from S3 bucket
* /opt/barmans3/barmans3.conf: shared config file holding S3 URIs amongst other things
* /etc/cron.d/barmans3: cron entries for automated barmans3-wal-sync and barmans3-base-sync execution

## Theory of Operation

1. barmans3-queue-add script is added to main-server barman configuration as post-backup hook script - where barman passes (full) backup run details - once barman backup is completed
2. barmans3-queue-add creates basebackup S3 sync task as: /var/run/barmans3/queue.d/<backup_id>.run
3. barmans3-base-sync is run from cron (once-per-day) looking for <backup_id>.run tasks to execute aws cli s3 sync for basebackup taken by barman
4. sync task is transferred into /var/run/barmans3/queue.d/<backup_id>.running state while executing
5. if sync task errors or task input params were incorrect (ie barman backup errored for example) - then task is trasferred into /var/run/barmans3/queue.d/<backup_id>.error state (and not processed any further)
6. if sync task completes with no errors on its awscli return status - then task is put into /var/run/barmans3/queue.d/<backup_id>.done state (and kept for history, no automated removal yet)
7. barmans3-wal-sync is run from cron every 15 minutes and requiring server name as an argument - syncing server WALs from Barman to S3 bucket
8. sync scripts outputs are directed to relevant log files under /var/log/barmans3 (redirection configured in /etc/cron.d/barmans3)

## Installation

We assume CentOS 7 Barman host here - althou BarmanS3 scripts should work also with other Linux OSes.

Requirements:
* AWS CLI utility
* GIT utility
* rsync utility

### Satisfying barmans3 dependencies

```bash
# EPEL7 repo is required to install awscli
yum -y install epel-release

# install awscli and other utilities
yum -y install awscli git screen rsync
```

### Deploying BarmanS3

```bash
# clone barmans3 git repo
git clone https://github.com/opennode/barmans3.git
cd barmans3
./install.sh
```

## Configuration

```bash
# review default /opt/barmans3/barmans3.conf contents for:
# S3_ENDPOINT_URI
# S3_BUCKET_URI
vi /opt/barmans3/barmans3.conf

# switch to barman user
su - barman
 
# create aws-cli config and S3 credential files
mkdir ~/.aws
chmod 700 ~/.aws

# review: all params 
cat << EOF > ~/.aws/config
[default]
output = text
s3 =
    max_concurrent_requests = 24
    multipart_threshold = 256MB
    multipart_chunksize = 128MB
EOF
chmod 600 ~/.aws/config
 
# change: aws_access_key_id
# change: aws_secret_access_key
cat << EOF > ~/.aws/credentials
[default]
aws_access_key_id = <aws_key_id>
aws_secret_access_key = <aws_access_key>
EOF
chmod 600 ~/.aws/credentials
```

## Usage

### Manual operation

```bash
# verifying aws-cli operation
# load configuration file variables
source /opt/barmans3/barmans3.conf

# list bucket contents (might be empty)
aws --endpoint-url $S3_ENDPOINT_URI s3 ls $S3_BUCKET_URI
# list bucket contents with debug enabled
aws --debug --endpoint-url $S3_ENDPOINT_URI s3 ls $S3_BUCKET_URI
 
# initial (manual) sync of base backups
# launch task inside screen
screen
time aws --endpoint-url $S3_ENDPOINT_URI s3 sync /var/data/barman/main-server/base/ s3://backup/barman/main-server/base/
 
# initial (manual) sync of WALs
screen
time aws --endpoint-url $S3_ENDPOINT_URI s3 sync /var/data/barman/main-server/wals/ s3://backup/barman/main-server/wals/
```

### Automation

``` bash 
# add post-backup hook script configuration for barman main-server config
echo "post_backup_script = /opt/barmans3/bin/barmans3-queue-add" >> /etc/barman.d/main-server.conf
 
# add cron entry for sync automation
# redirect output to logfiles
# and remove upload stats lines from log output
cat << 'EOF' > /etc/cron.d/barmans3
SHELL=/bin/bash
# m    h  dom mon dow   user     command
  */15 *    *   *   *   barman   /opt/barmans3/bin/barmans3-wal-sync main-server | sed 's/\o015/\n/g' | grep -v 'file(s) remaining' >> /var/log/barmans3/walsync.log 2>&1
  5    23   *   *   *   barman   /opt/barmans3/bin/barmans3-base-sync | sed 's/\o015/\n/g' | grep -v 'file(s) remaining' >> /var/log/barmans3/basesync.log 2>&1
  
EOF
 
# reload crond 
# NOT required if cron runs with inotify (like CentOS 7 crond.service does)
systemctl reload crond.service
systemctl status crond.service
```
