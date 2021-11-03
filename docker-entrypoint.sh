#!/bin/bash
set -eou pipefail

# Set database config from Heroku DATABASE_URL
if [ "$DATABASE_URL" != "" ]; then
    echo "Found database configuration in DATABASE_URL=$DATABASE_URL"

    regex='^postgres://([a-zA-Z0-9_-]+):([a-zA-Z0-9]+)@([a-z0-9.-]+):([[:digit:]]+)/([a-zA-Z0-9_-]+)$'
    if [[ $DATABASE_URL =~ $regex ]]; then
        export DB_ADDR=${BASH_REMATCH[3]}
        export DB_PORT=${BASH_REMATCH[4]}
        export DB_DATABASE=${BASH_REMATCH[5]}
        export DB_USER=${BASH_REMATCH[1]}
        export DB_PASSWORD=${BASH_REMATCH[2]}

        echo "DB_ADDR=$DB_ADDR, DB_PORT=$DB_PORT, DB_DATABASE=$DB_DATABASE, DB_USER=$DB_USER, DB_PASSWORD=$DB_PASSWORD"
        export DB_VENDOR=postgres
    fi

fi

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local CONFIG_MARKER_FILE="${var}_FILE"
    local def="${2:-}"
    if [[ ${!var:-} && ${!CONFIG_MARKER_FILE:-} ]]; then
        echo >&2 "error: both $var and $CONFIG_MARKER_FILE are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [[ ${!var:-} ]]; then
        val="${!var}"
    elif [[ ${!CONFIG_MARKER_FILE:-} ]]; then
        val="$(< "${!CONFIG_MARKER_FILE}")"
    fi

    if [[ -n $val ]]; then
        export "$var"="$val"
    fi

    unset "$CONFIG_MARKER_FILE"
}

##############################
# Set admin user credentials #
##############################

file_env 'KEYCLOAK_ADMIN'
file_env 'KEYCLOAK_ADMIN_PASSWORD'

##################
# Start Keycloak #
##################

CONFIG_ARGS="-Dquarkus.http.proxy-address-forwarding=true --http-enabled=true --http-port=$PORT"
RUN_CONFIG_START=false
RUN_CONFIG=false
SERVER_OPTS=""

while [ "$#" -gt 0 ]
do
    case "$1" in
      --auto-config)
          RUN_CONFIG_START=true
          ;;
      config)
          RUN_CONFIG=true
          ;;
      *)
          if [[ $1 = --* || ! $1 =~ ^-.* ]]; then
            CONFIG_ARGS="$CONFIG_ARGS $1"
          else
            SERVER_OPTS="$SERVER_OPTS $1"
          fi
          ;;
    esac
    shift
done

if [[ "$RUN_CONFIG_START" == true ]]; then
  if [[ "$RUN_CONFIG" == true ]]; then
    echo "ERROR: You can not run 'config' when passing the '--auto-config' start option.Please, choose one or another."
    exit 2
  fi

  CONFIG_MARKER_FILE="/opt/jboss/keycloak/config_marker"

  if [[ -n $CONFIG_ARGS && ! -f "$CONFIG_MARKER_FILE" ]]; then
    exec /opt/jboss/keycloak/bin/kc.sh config $CONFIG_ARGS &
    wait $!
    touch $CONFIG_MARKER_FILE
  fi

  exec /opt/jboss/keycloak/bin/kc.sh $SERVER_OPTS
else
  exec /opt/jboss/keycloak/bin/kc.sh $SERVER_OPTS $CONFIG_ARGS
fi

exit $?