#!/bin/sh

# betterspeedtest.sh - Script to simulate http://speedtest.net
# Start pinging, then initiate a download, let it finish, then start an upload
# Output the measured transfer rates and the resulting ping latency
# It's better than 'speedtest.net' because it measures latency *while* measuring the speed.

# Usage: sh betterspeedtest.sh [-4 -6] [ -H netperf-server ] [ -t duration ] [ -p host-to-ping ] [ -i ] [ -n simultaneous-streams ]

# Options: If options are present:
#
# -H | --hosts:  comma-separated addresses ofnetperf servers (default: netperf.bufferbloat.net)
#                Alternate servers include netperf-east.bufferbloat.net (east coast US),
#                netperf-west.bufferbloat.net (California), and netperf-eu.bufferbloat.net (Denmark)
# -4 | -6:       enable ipv4 or ipv6 testing (default: ipv4)
# -t | --time:   Duration for how long each direction's test should run (default:60 seconds)
# -p | --ping:   Host to ping to measure latency (default: gstatic.com)
# -n | --number: Number of simultaneous sessions per host (default: 5 sessions)

# Copyright (c) 2014-2019 - Rich Brown rich.brown@blueberryhillsoftware.com
# GPLv2

# Summarize the contents of the ping's output file to show min, avg, median, max, etc.
summarize_pings() {     
  # Process the ping times, and summarize the results
  # grep to keep lines that have "time=", then sed to isolate the time stamps, and sort them
  # awk builds an array of those values, and prints first & last (which are min, max) 
  # and computes average.
  # If the number of samples is >= 10, also computes median, and 10th and 90th percentile readings

  # stop pinging and spinner
  kill_pings
  kill_spinner

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

# Print a spinner as a progress indicator.
print_spinner() {
  while true; do
    for c in / - \\ \|; do
      printf "%s\b" "$c"
      sleep 1
    done
  done
}

# Stop the current print_spinner() process
kill_spinner() {
  kill -9 "$SPINNER_PID"
  wait "$SPINNER_PID" 2>/dev/null
  SPINNER_PID=0
}

# Stop the current start_pings() process
kill_pings() {
  kill -9 "$PING_PID" 
  wait "$PING_PID" 2>/dev/null
  PING_PID=0
}

# Stop the current pings and dots, and exit
# ping command catches (and handles) first Ctrl-C, so you have to hit it again...
kill_pings_and_spinner_and_exit() {
  kill_pings
  kill_spinner
  printf "\nStopped\n"
  exit 1
}

# Start printing dots, then start a ping process, saving the results to PING_FILE
start_pings() {
  # Create temp file
  PING_FILE=$(mktemp /tmp/ping.XXXXXX) || exit 1

  # Start spinner
  print_spinner &
  SPINNER_PID=$!

  # Start Ping
  if [ "$TESTPROTO" -eq "-4" ]; then
    "${PING4}" "$PINGHOST" > "$PING_FILE" &
  else
    "${PING6}" "$PINGHOST" > "$PING_FILE" &
  fi
  PING_PID=$!
}

# Call measure_direction() with single parameter - "Download", "Upload", or "Idle"
# The function gets other info from globals determined from command-line arguments
measure_direction() {
  direction=$1

  # Start netperf with the proper direction
  if [ "$direction" = "Idle" ]; then
    start_pings
    sleep "$TESTDUR"
  else
    # Create temp file to store netperf data
    NETPERF_FILE=$(mktemp /tmp/netperf.XXXXXX) || exit 1

    if [ "$direction" = "Download" ]; then
      dir="TCP_MAERTS"
    else
      dir="TCP_STREAM"
    fi

    # Start $MAXSESSIONS datastreams between netperf client and the netperf server
    # netperf writes the sole output value (in Mbps) to stdout when completed
    netperf_pids=""
    for host in $(echo "$TESTHOSTS" | sed "s/,/ /g"); do
      for _ in $( seq "$MAXSESSIONS" ); do
        netperf "$TESTPROTO" -H "$host" -t $dir -l "$TESTDUR" -v 0 -P 0 >> "$NETPERF_FILE" &
        netperf_pids="${netperf_pids:+${netperf_pids} }$!"
      done
    done

    # Start off the ping process
    start_pings
    
    # Wait until each of the background netperf processes completes 
    for pid in $netperf_pids; do
      wait "$pid"
    done

    # Print speed
    awk -v dir="$(printf %8.8s "$direction")" '{s+=$1} END {printf " \n%s: %1.2f Mbps\n", dir, s}' < "$NETPERF_FILE"

    # Remove temp file
    rm "$NETPERF_FILE"
  fi

  # Summarize ping data
  summarize_pings
}

# ------- Start of the main routine --------
#
# Usage: sh betterspeedtest.sh [ -4 -6 ] [ -H netperf-server ] [ -t duration ] [ -p host-to-ping ] [ -i ] [ -n simultaneous-sessions ]
#
# “H” and “host” DNS or IP address of the netperf server host (default: netperf.bufferbloat.net)
# “t” and “time” Time to run the test in each direction (default: 60 seconds)
# “p” and “ping” Host to ping for latency measurements (default: gstatic.com)
# "n" and "number" Number of simultaneous upload or download sessions (default: 5 sessions;
#       5 sessions chosen empirically because total didn't increase much after that number)

# set an initial values for defaults
TESTHOSTS="netperf.bufferbloat.net"
TESTDUR="60"

PING4=ping
command -v ping4 > /dev/null 2>&1 && PING4=ping4
PING6=ping6

PINGHOST="gstatic.com"
MAXSESSIONS="5"
TESTPROTO="-4"

# Extract options and their arguments into variables.
while [ $# -gt 0 ]; do
    case "$1" in
      -4|-6) TESTPROTO=$1 ; shift 1 ;;
      -H|--hosts)
          case "$2" in
              "") echo "Missing hostname" ; exit 1 ;;
              *) TESTHOSTS=$2 ; shift 2 ;;
          esac ;;
      -t|--time) 
        case "$2" in
          "") echo "Missing duration" ; exit 1 ;;
              *) TESTDUR=$2 ; shift 2 ;;
          esac ;;
      -p|--ping)
          case "$2" in
              "") echo "Missing ping host" ; exit 1 ;;
              *) PINGHOST=$2 ; shift 2 ;;
          esac ;;
      -n|--number)
        case "$2" in
          "") echo "Missing number of simultaneous sessions" ; exit 1 ;;
          *) MAXSESSIONS=$2 ; shift 2 ;;
        esac ;;
      --) shift ; break ;;
        *) echo "Usage: sh betterspeedtest.sh [-4 -6] [ -H netperf-server ] [ -t duration ] [ -p host-to-ping ] [ -n simultaneous-sessions ]" ; exit 1 ;;
    esac
done

# Start the main test
if [ "$TESTPROTO" -eq "-4" ]; then
  PROTO="ipv4"
else
  PROTO="ipv6"
fi
DATE=$(date "+%Y-%m-%d %H:%M:%S")

# Catch a Ctl-C and stop the pinging and the print_dots
trap kill_pings_and_spinner_and_exit HUP INT TERM

echo "$DATE Testing against $TESTHOSTS ($PROTO) with $MAXSESSIONS sessions while pinging $PINGHOST ($TESTDUR seconds while idle and in each direction)"
measure_direction "Idle"
measure_direction "Download"
measure_direction "Upload"
