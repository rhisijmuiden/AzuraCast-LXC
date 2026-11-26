#!/bin/bash
# AzuraCast-LXC: runtime directories that the Docker image created at build time but that live on
# tmpfs (/run, often /tmp) on a normal host, so they must be recreated at every start.

mkdir -p /run/mysqld /run/redis
chown mysql:mysql /run/mysqld
chmod 777 /run/mysqld
id valkey >/dev/null 2>&1 && chown valkey:valkey /run/redis

mkdir -p /tmp/nginx_client /tmp/nginx_fastcgi /tmp/nginx_cache /tmp/sftpgo_temp /tmp/liquidsoap_cache
touch /tmp/nginx_client/.tmpreaper /tmp/nginx_fastcgi/.tmpreaper /tmp/nginx_cache/.tmpreaper /tmp/sftpgo_temp/.tmpreaper
chmod -R 777 /tmp/nginx_client /tmp/nginx_fastcgi /tmp/nginx_cache /tmp/sftpgo_temp
chown -R azuracast:azuracast /tmp/liquidsoap_cache

mkdir -p /var/azuracast/www_tmp
chown azuracast:azuracast /var/azuracast/www_tmp
chmod 777 /var/azuracast/www_tmp
