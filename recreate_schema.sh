#!/bin/bash
# recreate the database schema
#
# Usage: recreate_schema.sh [<data.sql>]
# if data.sql is supplied, it will replace the existing database content
# run as root

# exit on error
set -e

# read configuration
path=$( dirname $( readlink -f $( dirname $0 ) ) )
source $path/liquid_feedback_core/config

tmpsql="../db_dump/tmp_recreate_schema_$( date +%Y-%m-%d_%H-%I-%S ).sql"

datasql=$1
if [ -z "$datasql" ]
then
  datasql=$tmpsql
elif [ ! -r "$datasql" ]
then
  echo "Supplied data file not found or not readable!"
  exit 1
fi

# show commands
set -x

su $dbuser  -c " pg_dump --disable-triggers --data-only $dbname > $tmpsql "
su $dbuser  -c " dropdb $dbname "
su $dbuser  -c " createdb $dbname "
su $dbuser  -c " createlang plpgsql $dbname || true "
su $dbuser  -c " psql -v ON_ERROR_STOP=1 -q -f core.sql $dbname "

su postgres -c " psql -v ON_ERROR_STOP=1 -q -f $datasql $dbname "
