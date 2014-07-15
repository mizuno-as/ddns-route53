#!/bin/bash
#
# This script deliver dynamic DNS in Amazon Route 53.
#
# Some code is licensed under a WTFPL license to the following
# copyright holders:
#
# Copyright (c) 2014 Hajime MIZUNO <mizuno-as@ubuntu.com>
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
# Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.

# Please set the following variables to your environment.
DNSCURL=./dnscurl.pl           # path of dnscurl.pl
KEYNAME=your-key-name          # your key name in .aws-secrets
TTL=300                        # TTL of this record
ARECORD=www.example.com.       # Target A record
ZONEID=YOURZONEID              # your zone ID
HOSTEDZONE=https://route53.amazonaws.com/2013-04-01/hostedzone

# Please check and set your global IP address by any method.
# (e.g. http://www.myglobalip.com/)
NEWIP=YOURGLOBALIP

# This function makes XML and POST it.
#
# When "update" argument is given,
# Add processing to delete the existing A record.
# Otherwise, please give "create" argument.
# But the argument is not checked.
function postxml ()
{
    XMLFILE=$(mktemp /tmp/r53-XXXXXX.xml)
    cat > $XMLFILE <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
  <ChangeBatch>
    <Changes>
EOF
    if [ $1 = "update" ]; then
        echo "delete existing A record."
        cat >> $XMLFILE <<EOF
      <Change>
        <Action>DELETE</Action>
        <ResourceRecordSet>
          <Name>${ARECORD}</Name>
          <Type>A</Type>
          <TTL>${TTL}</TTL>
          <ResourceRecords>
            <ResourceRecord>
              <Value>${CURRENTIP}</Value>
            </ResourceRecord>
          </ResourceRecords>
        </ResourceRecordSet>
      </Change>
EOF
    fi
    echo "create A record."
    cat >> $XMLFILE <<EOF
      <Change>
        <Action>CREATE</Action>
        <ResourceRecordSet>
          <Name>${ARECORD}</Name>
          <Type>A</Type>
          <TTL>${TTL}</TTL>
          <ResourceRecords>
            <ResourceRecord>
              <Value>${NEWIP}</Value>
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

if [ ! -x /usr/bin/hxselect ]; then
    echo "hxselect not exist."
    echo "Please install html-xml-utils package."
    exit 1
fi

RESPONSE=$($DNSCURL --keyname $KEYNAME -- -H "Content-Type: text/xml; charset=UTF-8" -X GET "$HOSTEDZONE/$ZONEID/rrset?name=$ARECORD&type=A&maxitems=1" 2>/dev/null | tail -n1)

if [ $(echo $RESPONSE | hxselect -c Name) = $ARECORD ]; then

    # When CNAME of $ARECORD already exists.
    # This script finished without doing anything.
    # Because CNAME record is not allowed to coexist with any other data (RFC1912).
    if [ $(echo $RESPONSE | hxselect -c Type) = "CNAME" ]; then
        echo "CNAME already exists."
        exit
    fi

    # When $ARECORD exists on Route 53.
    #
    # When A record already exists. -> Update the IP address.
    # A record does not exist. -> Create A record.
    if [ $(echo $RESPONSE | hxselect -c Type) = "A" ]; then
        CURRENTIP=$(echo $RESPONSE | hxselect -c Value)

        # If record on Route53 is the same as the current IP address.
        # Skip an update process.
        if [ $NEWIP = $CURRENTIP ]; then
            echo "IP address did not change."
        else
            postxml "update"
        fi
    else
        # Create new record.
        echo "$ARECORD already exists. but A record does not exist."
        postxml "create"
    fi
else
    # When a record of "$ARECORD" does not exist on Route 53.
    # Create new record.
    postxml "create"
fi
