#!/bin/bash
#
# This script deliver dynamic DNS in Amazon Route 53.
#
# Copyright (c) 2014 Hajime MIZUNO <mizuno-as@ubuntu.com>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the COPYING file for more details.
#

# Please edit the following config file for your environment.
CONFFILE=${1:-~/.ddns-route53.conf}

if [ ! -r "$CONFFILE" ]; then
    echo "$CONFFILE does not exist or unreadable." 1>&2
    exit 1
fi

source $CONFFILE

# Check required commands.
AWSCLI=${AWSCLI:-$(which aws)}
if [ ! -x "$AWSCLI" ]; then
    $LOGGER "aws command not exist." 1>&2
    $LOGGER "Please install awscli package." 1>&2
    exit 1
fi

JSHON=${JSHON:-$(which jshon)}
if [ ! -x "$JSHON" ]; then
    $LOGGER "jshon command not exist." 1>&2
    $LOGGER "Please install jshon package." 1>&2
    exit 1
fi

JSONFILE=$(mktemp /tmp/r53-XXXXXX.json)
cat > $JSONFILE <<EOF
{
    "Comment": "update a A record for the zone.",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${NAME}",
                "Type": "A",
                "TTL": ${TTL},
                "ResourceRecords": [
                    {
                        "Value": "${NEW_RR_VALUE}"
                    }
                ]
            }
        }
    ]
}
EOF

${AWSCLI} --profile ${KEYNAME} route53 change-resource-record-sets --hosted-zone-id ${ZONEID} --change-batch file://${JSONFILE}
rm $JSONFILE
