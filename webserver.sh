#!/bin/sh

# webserver.sh - Script to run betterspeedtest.sh on demand.
# All arguments passed here are passed to betterspeedtest.sh when invoked.
# The default port is 4000, unless PORT is set.

PORT="${PORT:-4000}"
echo "Listening on port $PORT..."
while true; do
  # shellcheck disable=SC2068
  printf "HTTP/1.1 200 OK\n\n%s\n" "$(./betterspeedtest.sh $@)" | nc -l -p "$PORT"
done
