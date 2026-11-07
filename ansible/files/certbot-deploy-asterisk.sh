#!/bin/sh
# Certbot runs this after a renewal. Asterisk can't read /etc/letsencrypt, so it gets its own copy.
# Restarting drops any call in progress. Certificates renew about every 60 days.
set -eu

install -o asterisk -g asterisk -m 0640 "$RENEWED_LINEAGE/fullchain.pem" /etc/asterisk/keys/asterisk.crt
install -o asterisk -g asterisk -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/asterisk/keys/asterisk.key
systemctl try-restart asterisk
