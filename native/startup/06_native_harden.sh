#!/bin/bash
# AzuraCast-LXC: inside Docker, Centrifugo is only reachable on the container's private network.
# On a host its insecure admin/API port would be open to the LAN, so bind it to localhost
# (nginx proxies the public endpoints to 127.0.0.1:6020).
CONF=/var/azuracast/centrifugo/config.toml
if [ -f "$CONF" ] && ! grep -q '^address = "127.0.0.1"' "$CONF"; then
    sed -i '/^\[http_server\]/a address = "127.0.0.1"\ninternal_address = "127.0.0.1"' "$CONF"
fi
