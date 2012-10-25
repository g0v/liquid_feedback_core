#!/bin/bash
# calls ls_update and lf_notification once, for development purposes
# has to be executed as apache/www-data

# read configuration
path=$( dirname $( readlink -f $( dirname $0 ) ) )
source $path/liquid_feedback_core/config

# lf_update
$path/liquid_feedback_core/lf_update dbname=$dbname

# lf_notification
(
  cd $path/liquid_feedback_frontend/
  echo "Event:send_notifications()" | ../webmcp/bin/webmcp_shell myconfig
)