#!/bin/bash
# performs an automatic test
#
# Usage: test.sh <test.sql> [<core.sql>]
# run as database user (usually www-run or apache)

# read configuration
path=$( dirname $( readlink -f $( dirname $0 ) ) )
source $path/liquid_feedback_core/config

testsql="$1"
if [ ! -r "$testsql" ]
then
  echo "SQL test file not supplied or not found!"
  exit 1
fi

coresql="$2"
if [ -z "$coresql" ]
then
  coresql="core.sql"
fi

dropdb $dbname
createdb $dbname
createlang plpgsql $dbname
psql -v ON_ERROR_STOP=1 -q -f "$coresql" $dbname
psql -v ON_ERROR_STOP=1 -q -f "$testsql" $dbname
