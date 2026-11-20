#!/bin/bash
# Two Agent Relay instances on one Mac, each with its own data folder and ports.
# Build first: ~/Developer/flutter/bin/flutter build macos --debug
# Stop them by pid (printed below) — never pkill a pattern.
set -euo pipefail
APP="${APP:-build/macos/Build/Products/Debug/Agent Relay.app/Contents/MacOS/Agent Relay}"
[ -x "$APP" ] || { echo "Build the app first: flutter build macos --debug"; exit 1; }

AGENT_RELAY_HOME=/tmp/agent-relay-a AGENT_RELAY_PEER_PORT=8790 AGENT_RELAY_LOCAL_PORT=8791 \
  "$APP" > /tmp/agent-relay-a.log 2>&1 &
A=$!
AGENT_RELAY_HOME=/tmp/agent-relay-b AGENT_RELAY_PEER_PORT=8792 AGENT_RELAY_LOCAL_PORT=8793 \
  "$APP" > /tmp/agent-relay-b.log 2>&1 &
B=$!
echo "A: pid $A  peer 8790  local 8791  home /tmp/agent-relay-a"
echo "B: pid $B  peer 8792  local 8793  home /tmp/agent-relay-b"
echo "Skill against B: AGENT_RELAY_HOME=/tmp/agent-relay-b AGENT_RELAY_LOCAL_PORT=8793 python3 skill/inbox/scripts/relay.py status"
echo "Stop: kill $A $B"
