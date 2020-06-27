#!/bin/bash
set -e

# Warn if the DOCKER_HOST socket does not exist
if [[ $DOCKER_HOST = unix://* ]]; then
	socket_file=${DOCKER_HOST#unix://}
	if ! [ -S "$socket_file" ]; then
		cat >&2 <<-EOT
			ERROR: you need to share your Docker host socket with a volume at $socket_file
			Typically you should run your nginxproxy/nginx-proxy with: \`-v /var/run/docker.sock:$socket_file:ro\`
			See the documentation at http://git.io/vZaGJ
		EOT
		socketMissing=1
	fi
fi

# Generate dhparam file if required
/app/generate-dhparam.sh

# Generate default certificate if not present
if [[ ! -e /etc/nginx/certs/default.crt || ! -e /etc/nginx/certs/default.key ]]; then
    openssl req -x509 \
        -newkey rsa:4096 -sha256 -nodes -days 365 \
        -subj "/CN=nginx-proxy" \
        -keyout /etc/nginx/certs/default.key.new \
        -out /etc/nginx/certs/default.crt.new \
    && mv /etc/nginx/certs/default.key.new /etc/nginx/certs/default.key \
    && mv /etc/nginx/certs/default.crt.new /etc/nginx/certs/default.crt
    echo "Info: a default key and certificate have been created at /etc/nginx/certs/default.key and /etc/nginx/certs/default.crt."
fi

# Compute the DNS resolvers for use in the templates - if the IP contains ":", it's IPv6 and must be enclosed in []
RESOLVERS=$(awk '$1 == "nameserver" {print ($2 ~ ":")? "["$2"]": $2}' ORS=' ' /etc/resolv.conf | sed 's/ *$//g'); export RESOLVERS

SCOPED_IPV6_REGEX="\[fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}\]"

if [ "$RESOLVERS" = "" ]; then
	echo "Warning: unable to determine DNS resolvers for nginx" >&2
	unset RESOLVERS
elif [[ $RESOLVERS =~ $SCOPED_IPV6_REGEX ]]; then
	echo -n "Warning: Scoped IPv6 addresses removed from resolvers: " >&2
	echo "$RESOLVERS" | grep -Eo "$SCOPED_IPV6_REGEX" | paste -s -d ' ' >&2
	RESOLVERS=$(echo "$RESOLVERS" | sed -r "s/$SCOPED_IPV6_REGEX//g" | xargs echo -n); export RESOLVERS
fi

# If the user has run the default command and the socket doesn't exist, fail
if [ "$socketMissing" = 1 ] && [ "$1" = forego ] && [ "$2" = start ] && [ "$3" = '-r' ]; then
	exit 1
fi

# Force initial docker-gen run to prevent using a broken nginx configuration (e.g. in case of missing certificates)
echo "Info: initial docker-gen run"
docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf
docker-gen /app/nginx-stream.tmpl /etc/nginx/nginx-stream.conf

exec "$@"
