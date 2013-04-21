#!/bin/bash
# backup the data in the database
#
# Usage: backup_data.sh
# run as root

# read configuration
path=$( dirname $( readlink -f $( dirname $0 ) ) )
source $path/liquid_feedback_core/config

backupsql="../db_dump/tmp_backup_data_$( date +%Y-%m-%d_%H-%I-%S ).sql"

# show commands
set -x

su $dbuser  -c " pg_dump --disable-triggers --data-only $dbname > $backupsql "
