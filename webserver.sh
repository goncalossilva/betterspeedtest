#!/bin/sh

# webserver.sh - Script to run betterspeedtest.sh on demand.
# All arguments passed here are passed to betterspeedtest.sh when invoked.
# The default port is 4000, unless PORT is set.

PORT="${PORT:-4000}"
echo "Listening on port $PORT..."

mkfifo /tmp/pipe
while true; do
  # shellcheck disable=SC2094
  {
    read -r _ </tmp/pipe
    printf "HTTP/1.1 200 OK\r\n\r\n"
    # shellcheck disable=SC2068
    ./betterspeedtest.sh $@
  } | nc -l -p "$PORT" >/tmp/pipe
done
