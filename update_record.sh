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
CONFFILE=${1:-./ddns-route53.conf}

if [ ! -r "$CONFFILE" ]; then
    echo "$CONFFILE does not exist or unreadable." 1>&2
    exit 1
fi

source $CONFFILE

# This function makes XML and POST it.
#
# When "update" argument is given,
# Add processing to delete the existing A record.
# Otherwise, please give "create" argument.
# But the argument is not checked.
function postxml ()
{
    local XMLFILE=$(mktemp /tmp/r53-XXXXXX.xml)
    cat > $XMLFILE <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
  <ChangeBatch>
    <Changes>
EOF
    if [ $1 = "update" ]; then
        $LOGGER "delete existing A record."
        cat >> $XMLFILE <<EOF
      <Change>
        <Action>DELETE</Action>
        <ResourceRecordSet>
          <Name>${NAME}</Name>
          <Type>A</Type>
          <TTL>${TTL}</TTL>
          <ResourceRecords>
            <ResourceRecord>
              <Value>${OLD_RR_VALUE}</Value>
            </ResourceRecord>
          </ResourceRecords>
        </ResourceRecordSet>
      </Change>
EOF
    fi
    $LOGGER "create A record."
    cat >> $XMLFILE <<EOF
      <Change>
        <Action>CREATE</Action>
        <ResourceRecordSet>
          <Name>${NAME}</Name>
          <Type>A</Type>
          <TTL>${TTL}</TTL>
          <ResourceRecords>
            <ResourceRecord>
              <Value>${NEW_RR_VALUE}</Value>
            </ResourceRecord>
          </ResourceRecords>
        </ResourceRecordSet>
      </Change>
    </Changes>
  </ChangeBatch>
</ChangeResourceRecordSetsRequest>
EOF
    $DNSCURL --keyname $KEYNAME -- -H "Content-Type: text/xml; charset=UTF-8" -X POST --upload-file $XMLFILE $HOSTEDZONE/$ZONEID/rrset
    rm $XMLFILE
}

HXSELECT=${HXSELECT:-$(which hxselect)}
if [ ! -x "$HXSELECT" ]; then
    echo "hxselect not exist." 1>&2
    echo "Please install html-xml-utils package." 1>&2
    exit 1
fi

RESPONSE=$($DNSCURL --keyname $KEYNAME -- -H "Content-Type: text/xml; charset=UTF-8" -X GET "$HOSTEDZONE/$ZONEID/rrset?name=$NAME&type=A&maxitems=1" 2>/dev/null | tail -n1)

if [ "$(echo $RESPONSE | $HXSELECT -c Name)" = "$NAME" ]; then

    # When CNAME of $NAME already exists.
    # This script finished without doing anything.
    # Because CNAME record is not allowed to coexist with any other data (RFC1912).
    if [ "$(echo $RESPONSE | $HXSELECT -c Type)" = "CNAME" ]; then
        $LOGGER "CNAME already exists."
        exit
    fi

    # When $NAME exists on Route 53.
    #
    # When A record already exists. -> Update the IP address.
    # A record does not exist. -> Create A record.
    if [ "$(echo $RESPONSE | $HXSELECT -c Type)" = "A" ]; then
        OLD_RR_VALUE=$(echo $RESPONSE | $HXSELECT -c Value)

        # If record on Route53 is the same as the current IP address.
        # Skip an update process.
        if [ "$NEW_RR_VALUE" = "$OLD_RR_VALUE" ]; then
            $LOGGER "IP address did not change."
        else
            postxml "update"
        fi
    else
        # Create new record.
        $LOGGER "$NAME already exists. but A record does not exist."
        postxml "create"
    fi
else
    # When a record of "$NAME" does not exist on Route 53.
    # Create new record.
    postxml "create"
fi
