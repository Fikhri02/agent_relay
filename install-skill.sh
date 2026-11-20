#!/usr/bin/env bash
# Install the inbox skill for Claude Code (terminal and VS Code share ~/.claude/skills).
# Usage: ./install-skill.sh [--codex]   (--codex also copies it to ~/.codex/skills)
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill/inbox"
targets=("$HOME/.claude/skills/inbox")

for arg in "$@"; do
  case "$arg" in
    --codex) targets+=("$HOME/.codex/skills/inbox") ;;
    -h|--help)
      echo "Usage: $0 [--codex]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (usage: $0 [--codex])" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$src/SKILL.md" ]]; then
  echo "Skill source not found: $src" >&2
  exit 1
fi

for dest in "${targets[@]}"; do
  if [[ -e "$dest" ]]; then
    echo "Replacing existing $dest:"
    (cd "$dest" && find . -type f | sed 's|^\./|  |' | sort)
    rm -rf "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
  find "$dest" -name '__pycache__' -type d -prune -exec rm -rf {} +
  chmod +x "$dest/scripts/relay.py"
  echo "Installed $dest"
done
