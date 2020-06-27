#!/bin/bash
set -e

# Warn if the DOCKER_HOST socket does not exist
if [[ $DOCKER_HOST = unix://* ]]; then
	socket_file=${DOCKER_HOST#unix://}
	if ! [ -S $socket_file ]; then
		cat >&2 <<-EOT
			ERROR: you need to share your Docker host socket with a volume at $socket_file
			Typically you should run your nginxproxy/nginx-proxy with: \`-v /var/run/docker.sock:$socket_file:ro\`
			See the documentation at http://git.io/vZaGJ
		EOT
		socketMissing=1
	fi
fi

# Generate dhparam file if required
# Note: if $DHPARAM_BITS is not defined, generate-dhparam.sh will use 4096 as a default
# Note2: if $DHPARAM_GENERATION is set to false in environment variable, dh param generator will skip completely
/app/generate-dhparam.sh $DHPARAM_BITS $DHPARAM_GENERATION

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
export RESOLVERS=$(awk '$1 == "nameserver" {print ($2 ~ ":")? "["$2"]": $2}' ORS=' ' /etc/resolv.conf | sed 's/ *$//g')
if [ "x$RESOLVERS" = "x" ]; then
    echo "Warning: unable to determine DNS resolvers for nginx" >&2
    unset RESOLVERS
fi

# If the user has run the default command and the socket doesn't exist, fail
if [ "$socketMissing" = 1 -a "$1" = forego -a "$2" = start -a "$3" = '-r' ]; then
	exit 1
fi

# Force initial docker-gen run to prevent using a broken nginx configuration (e.g. in case of missing certificates)
echo "Info: initial docker-gen run"
docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf
docker-gen /app/nginx-stream.tmpl /etc/nginx/nginx-stream.conf

exec "$@"
