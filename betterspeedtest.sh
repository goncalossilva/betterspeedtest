#!/bin/sh
#
# Copyright (c) 2014-2019 - Rich Brown rich.brown@blueberryhillsoftware.com
# Copyright (c) 2021-2021 - Gonçalo Silva goncalossilva@gmail.com
# GPLv2

# betterspeedtest.sh - Script to measure download/upload speed and latency.
# It's better than 'speedtest.net' because it measures latency *while* measuring the speed.
#
# Usage: sh betterspeedtest.sh [-4 -6] [ -H netperf-server(s) ] [ -t duration ] [ -p host-to-ping ] [ -i ] [ -n streams ]
#
# Options: If options are present:
#
# -H | --hosts:  comma-separated addresses ofnetperf servers (default: netperf.bufferbloat.net)
#                Alternate servers include netperf-east.bufferbloat.net (east coast US),
#                netperf-west.bufferbloat.net (California), and netperf-eu.bufferbloat.net (Denmark)
# -4 | -6:       enable ipv4 or ipv6 testing (default: ipv4)
# -t | --time:   Duration for how long each direction's test should run (default: 60 seconds)
# -p | --ping:   Host to ping to measure latency (default: gstatic.com)
# -n | --number: Number of simultaneous sessions per host (default: 5 sessions)

PING4=ping
command -v ping4 > /dev/null 2>&1 && PING4=ping4
PING6=ping6

# Defaults.
HOSTS="netperf.bufferbloat.net"
DURATION="60"
IDLE_DURATION="15"
PING_HOST="gstatic.com"
SESSIONS="5"
PROTOCOL="-4"
PING=$PING4

run() {
  # Extract options and their arguments into variables.
  while [ $# -gt 0 ]; do
      case "$1" in
        -4|-6)
            case "$1" in
              "-4") PROTOCOL="ipv4" ; PING=$PING4 ;;
              "-6") PROTOCOL="ipv6" ; PING=$PING6 ;;
            esac
            shift 1 ;;
        -H|--hosts)
            case "$2" in
              "") echo "Missing hostname" ; exit 1 ;;
              *) HOSTS=$2 ; shift 2 ;;
            esac ;;
        -t|--time)
          case "$2" in
              "") echo "Missing duration" ; exit 1 ;;
              *) DURATION=$2 ; IDLE_DURATION=$((DURATION/4 < 10 ? 10 : DURATION/4)) ; shift 2 ;;
            esac ;;
        -p|--ping)
            case "$2" in
              "") echo "Missing ping host" ; exit 1 ;;
              *) PING_HOST=$2 ; shift 2 ;;
            esac ;;
        -n|--number)
          case "$2" in
            "") echo "Missing number of simultaneous sessions" ; exit 1 ;;
            *) SESSIONS=$2 ; shift 2 ;;
          esac ;;
        --) shift ; break ;;
        *) echo "Usage: sh betterspeedtest.sh [-4 -6] [ -H netperf-server ] [ -t duration ] [ -p host-to-ping ] [ -n simultaneous-sessions ]" ; exit 1 ;;
      esac
  done

  # Catch a Ctl-C and stop the pinging and the print_dots
  trap kill_netperf_and_pings_and_spinner_and_exit HUP INT TERM

  # Start the main test
  measure_direction "Idle"
  measure_direction "Download"
  measure_direction "Upload"
}

# Measure speed (if not idle) and latency.
# Call measure_direction() with single parameter - "Download", "Upload", or "Idle".
# The function gets other info from globals determined from command-line arguments.
measure_direction() {
  direction=$1

  # Create temp file to store netperf data
  NETPERF_FILE=$(mktemp /tmp/netperf.XXXXXX) || exit 1
  echo "$direction" > "$NETPERF_FILE"

  # Start off the ping process
  start_pings

  # Start netperf with the proper direction
  if [ "$direction" = "Idle" ]; then
    sleep "$IDLE_DURATION"
  else
    # Start $SESSIONS datastreams between netperf client and the netperf server
    # netperf writes the sole output value (in Mbps) to stdout when completed
    if [ "$direction" = "Download" ]; then
      testname="TCP_MAERTS"
    else
      testname="TCP_STREAM"
    fi
    NETPERF_PIDS=""
    for host in $(echo "$HOSTS" | sed "s/,/ /g"); do
      for _ in $( seq "$SESSIONS" ); do
        netperf "$PROTOCOL" -H "$host" -t $testname -l "$DURATION" -v 0 -P 0 >> "$NETPERF_FILE" &

        NETPERF_PIDS="${NETPERF_PIDS:+${NETPERF_PIDS} }$!"
      done
    done

    # Wait until each of the background netperf processes completes
    for pid in $NETPERF_PIDS; do
      wait "$pid"
    done
  fi

  # Stop pinging and spinner
  kill_pings
  kill_spinner

  # Process and summarize ping and netperf data
  process_pings
  process_netperf
  print_summary
}

# Start printing dots, then start a ping process, saving the results to PING_FILE.
start_pings() {
  # Create temp file
  PING_FILE=$(mktemp /tmp/ping.XXXXXX) || exit 1

  # Start spinner
  print_spinner &
  SPINNER_PID=$!

  # Start ping
  "${PING}" "$PING_HOST" > "$PING_FILE" &
  PING_PID=$!
}

# Print a spinner as a progress indicator.
print_spinner() {
  while true; do
    for c in / - \\ \|; do
      printf "%s\b" "$c"
      sleep 1
    done
  done
}

# Process the ping times, and summarize the results in the file
process_pings() {
  # grep to keep lines that have "time=", then sed to isolate the time stamps, and sort them
  # awk builds an array of those values, and captures stores first & last (which are min, max)
  # and computes average, median, 10th and 90th percentile.
  #
  # shellcheck disable=SC1004
  pingdata="$(
    sed 's/^.*time=\([^ ]*\) ms/\1/' < "$PING_FILE" | \
    grep -v "PING" | \
    sort -n | \
    awk 'BEGIN {pdropcount=0; pcount=0; pmin=0; pp10=0; pmed=0; pavg=0; pp90=0; pmax=0;} \
      { \
        if ($0 ~ /timeout/) { \
          pdropcount += 1; \
        } else { \
          pcount += 1; \
          arr[pcount] = $1; \
          sum += $1; \
        } \
      } \
      END { \
        if (pcount == 0) { \
          pcount = 1 \
        } else { \
          pmin = arr[1]; \
          pp10 = arr[int(pcount/10)]; \
          pmed = pcount%2==1 ? arr[(pcount+1)/2] : arr[pcount/2]; \
          pavg = sum/pcount; \
          pp90 = arr[int(pcount*9/10)]; \
          pmax = arr[pcount]; \
        } \
        ploss = pdropcount/(pdropcount+pcount)*100; \
        printf("%d %4.2f %4.2f %4.2f %4.2f %4.2f %4.2f %4.2f", pcount, ploss, pmin, pp10, pmed, pavg, pp90, pmax) \
      }'
    )"
    echo "$pingdata" > "$PING_FILE"
}

# Process speed, and summarize the results.
process_netperf() {
  # Read direction from first line then sum netperf speed data.
  netperfdata="$(head -n 1 "$NETPERF_FILE")"
  nspeeds="$(tail -n +2 "$NETPERF_FILE")"
  if [ -n "$nspeeds" ]; then
    netperfdata="$netperfdata $(echo "$nspeeds" | awk '{speed+=$1} END {printf("%1.2f", speed)}')"
  fi
  echo "$netperfdata" > "$NETPERF_FILE"
}

# Print speed and ping data.
print_summary() {
  read -r ndirection nspeed < "$NETPERF_FILE"
  read -r pcount ploss pmin pp10 pmed pavg pp90 pmax < "$PING_FILE"

  # TODO: Add support for CSV and Prometheus.
  if [ -n "$nspeed" ]; then
    printf "\n%8.8s: %1.2f Mbps\n" "$ndirection" "$nspeed"
  else
    printf "\n%8.8s\n" "$ndirection"
  fi
  printf " Latency: (in msec, %d pings, %4.2f%% packet loss)\n     Min: %4.2f \n   10pct: %4.2f \n  Median: %4.2f \n     Avg: %4.2f \n   90pct: %4.2f \n     Max: %4.2f\n" "$pcount" "$ploss" "$pmin" "$pp10" "$pmed" "$pavg" "$pp90" "$pmax"
}

# Stop the current pings and dots, and exit
# ping command catches (and handles) first Ctrl-C, so you have to hit it again...
kill_netperf_and_pings_and_spinner_and_exit() {
  kill_netperf
  kill_pings
  kill_spinner
  printf "\nStopped\n"
  exit 1
}

# Stop the current measure_direction() processes
kill_netperf() {
  for pid in $NETPERF_PIDS; do
    kill -9 "$pid"
  done
  for pid in $NETPERF_PIDS; do
    wait "$pid" 2>/dev/null
  done
}

# Stop the current print_spinner() process
kill_spinner() {
  kill -9 "$SPINNER_PID"
  wait "$SPINNER_PID" 2>/dev/null
}

# Stop the current start_pings() process
kill_pings() {
  kill -9 "$PING_PID"
  wait "$PING_PID" 2>/dev/null
}

run "$@"
