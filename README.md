# betterspeedtest

Tests the performance of an internet connection by measuring download and upload speeds, as well as latency while idle, downloading, and uploading. Relies on [`netperf`](https://github.com/HewlettPackard/netperf) and `ping`.

## Usage 

`betterspeedtest.sh [-4 -6] [ -H netperf-server(s) ] [ -t duration ] [ -p host-to-ping ] [ -n streams ] [ -o format ] [--idle --download --upload]`

Options:
- `-H`, `--hosts`:  Comma-separated addresses of netperf servers (default: netperf.bufferbloat.net). Alternate servers include netperf-east.bufferbloat.net (east coast US), netperf-west.bufferbloat.net (California), and netperf-eu.bufferbloat.net (Denmark).
- `-4`, `-6`:       Enable ipv4 or ipv6 testing (default: ipv4).
- `-t`, `--time`:   Duration for how long each direction's test should run (default: 60 seconds).
- `-p`, `--ping`:   Host to ping to measure latency (default: gstatic.com).
- `-n`, `--number`: Number of simultaneous sessions per host (default: 5 sessions)
- `-o`, `--format`: Output format (default: plain). Available options are `plain`, `yaml` or `prometheus`.
- `--idle`:         Only measure idle latency.
- `--download`:     Only measure download speed and latency.
- `--upload`:       Only measure upload speed and latency.

### Dockerfile

A containerized version can be built using `Dockerfile`, and ran like so:

`docker run betterspeedtest -H netperf-eu.bufferbloat.net -t 15`

## Acknowledgements 

This is a heavily modified copy of [richb-hanover/OpenWrtScripts's betterspeedtest.sh](https://github.com/richb-hanover/OpenWrtScripts/blob/master/betterspeedtest.sh).
