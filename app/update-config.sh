#!/bin/sh
set -e
docker-gen /app/nginx-stream.tmpl /etc/nginx/nginx-stream.conf
nginx -s reload
