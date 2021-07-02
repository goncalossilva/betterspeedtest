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
              *) DURATION=$2 ; shift 2 ;;
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

  # Start off the ping process
  start_pings

  # Start netperf with the proper direction
  if [ "$direction" = "Idle" ]; then
    sleep "$DURATION"
  else
    # Create temp file to store netperf data
    NETPERF_FILE=$(mktemp /tmp/netperf.XXXXXX) || exit 1

    if [ "$direction" = "Download" ]; then
      testname="TCP_MAERTS"
    else
      testname="TCP_STREAM"
    fi

    # Start $SESSIONS datastreams between netperf client and the netperf server
    # netperf writes the sole output value (in Mbps) to stdout when completed
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

  # Summarize speed and ping data
  print_speed_data "$direction"
  print_ping_data
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

# Print the contents of the netperf's output file.
print_speed_data() {
  direction=$(printf %8.8s "$1")

  if [ -f "$NETPERF_FILE" ]; then
    awk -v testname="$direction" '{s+=$1} END {printf " \n%s: %1.2f Mbps\n", testname, s}' < "$NETPERF_FILE"

    rm "$NETPERF_FILE"
  else
    printf " \n%s\n" "$direction"
  fi
}

# Summarize the contents of ping's output file to show min, avg, median, max, etc.
print_ping_data() {     
  # Process the ping times, and summarize the results
  # grep to keep lines that have "time=", then sed to isolate the time stamps, and sort them
  # awk builds an array of those values, and prints first & last (which are min, max) 
  # and computes average.
  # If the number of samples is >= 10, also computes median, and 10th and 90th percentile readings

  # shellcheck disable=SC1004
  sed 's/^.*time=\([^ ]*\) ms/\1/' < "$PING_FILE" | grep -v "PING" | sort -n | \
  awk 'BEGIN {numdrops=0; numrows=0;} \
    { \
      if ($0 ~ /timeout/) { \
        numdrops += 1; \
      } else { \
        numrows += 1; \
        arr[numrows] = $1; \
        sum += $1; \
      } \
    } \
    END { \
      pc10="-"; pc90="-"; med="-"; \
      if (numrows == 0) { \
        numrows = 1 \
      } else if (numrows >= 10) { \
        ix = int(numrows/10); \
        pc10 = arr[ix]; \
        ix = int(numrows*9/10); \
        pc90 = arr[ix]; \
        if (numrows%2==1) { \
          med = arr[(numrows+1)/2];
        } else { \
          med = (arr[numrows/2]); \
        } \
      } \
      printf(" Latency: (in msec, %d pings, %4.2f%% packet loss)\n     Min: %4.3f \n   10pct: %4.3f \n  Median: %4.3f \n     Avg: %4.3f \n   90pct: %4.3f \n     Max: %4.3f\n", numrows, pktloss, arr[1], pc10, med, sum/numrows, pc90, arr[numrows] )\
     }'

  # and finally remove the PING_FILE
  rm "$PING_FILE"
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