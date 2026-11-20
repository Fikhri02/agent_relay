#!/bin/bash
# Three Agent Relay instances on one Mac, each with its own data folder and
# ports, for checking surat by hand (create, invite, approve/decline, history,
# leave, end). Ports stay clear of a real Agent Relay on 8790/8791.
# Build first: ~/Developer/flutter/bin/flutter build macos --debug
# Stop them by pid (printed below) — never pkill a pattern.
set -euo pipefail
APP="${APP:-build/macos/Build/Products/Debug/Agent Relay.app/Contents/MacOS/Agent Relay}"
[ -x "$APP" ] || { echo "Build the app first: flutter build macos --debug"; exit 1; }

AGENT_RELAY_HOME=/tmp/agent-relay-surat-a AGENT_RELAY_PEER_PORT=8796 AGENT_RELAY_LOCAL_PORT=8797 \
  "$APP" > /tmp/agent-relay-surat-a.log 2>&1 &
A=$!
AGENT_RELAY_HOME=/tmp/agent-relay-surat-b AGENT_RELAY_PEER_PORT=8798 AGENT_RELAY_LOCAL_PORT=8799 \
  "$APP" > /tmp/agent-relay-surat-b.log 2>&1 &
B=$!
AGENT_RELAY_HOME=/tmp/agent-relay-surat-c AGENT_RELAY_PEER_PORT=8800 AGENT_RELAY_LOCAL_PORT=8801 \
  "$APP" > /tmp/agent-relay-surat-c.log 2>&1 &
C=$!
echo "A: pid $A  peer 8796  local 8797  home /tmp/agent-relay-surat-a"
echo "B: pid $B  peer 8798  local 8799  home /tmp/agent-relay-surat-b"
echo "C: pid $C  peer 8800  local 8801  home /tmp/agent-relay-surat-c"
echo "Skill against C: AGENT_RELAY_HOME=/tmp/agent-relay-surat-c AGENT_RELAY_LOCAL_PORT=8801 python3 skill/inbox/scripts/relay.py status"
echo "Stop: kill $A; kill $B; kill $C"
