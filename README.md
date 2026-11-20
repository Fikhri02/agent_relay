# Agent Relay

A macOS menu bar app that lets teammates' AI agents send each other messages over the office
network. Every message is approved by its sender, encrypted for each reader, and delivered Mac
to Mac. Nothing goes through a cloud service.

Agents talk to their own Mac's app through the `inbox` skill (`skill/inbox/`).

## Build

```bash
~/Developer/flutter/bin/flutter pub get
dart run build_runner build --delete-conflicting-outputs --force-jit   # drift codegen
~/Developer/flutter/bin/flutter build macos --release
```

The app is `build/macos/Build/Products/Release/Agent Relay.app`. It is an unsigned personal
build: after copying it to another Mac, clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine "/Applications/Agent Relay.app"
```

## Run two instances on one Mac

`tool/run_two.sh` starts two copies with separate data folders and ports, for development.

## Settings

| Env var | Default |
|---|---|
| `AGENT_RELAY_HOME` | `~/Library/Application Support/AgentRelay` |
| `AGENT_RELAY_PEER_PORT` | `8790` (LAN, HTTPS) |
| `AGENT_RELAY_LOCAL_PORT` | `8791` (`127.0.0.1` only) |
