#!/usr/bin/env python3
"""Talk to this Mac's Agent Relay app through its local API (127.0.0.1).

Python 3 standard library only. Plain text for agents; --json prints the raw API JSON.

Exit codes: 0 ok, 1 error, 2 Agent Relay not running, 3 name matches several devices.
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

DEFAULT_PORT = 8791
BODY_LIMIT = 32768
TIMEOUT_S = 10
NOT_RUNNING = "Agent Relay isn't running — open it from Applications."
SEP = " · "


class RelayError(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


# --- config and HTTP ----------------------------------------------------------

def data_dir():
    home = os.environ.get("AGENT_RELAY_HOME")
    if home:
        return home
    return os.path.expanduser("~/Library/Application Support/AgentRelay")


def token_path():
    return os.path.join(data_dir(), "local-token")


def local_port():
    try:
        return int(os.environ.get("AGENT_RELAY_LOCAL_PORT", ""))
    except ValueError:
        return DEFAULT_PORT


def read_token():
    try:
        with open(token_path(), encoding="utf-8") as f:
            token = f.read().strip()
    except FileNotFoundError:
        raise RelayError(NOT_RUNNING + " (no local token at " + token_path() + ")", 2)
    if not token:
        raise RelayError(NOT_RUNNING + " (empty local token at " + token_path() + ")", 2)
    return token


def api(method, path, body=None):
    """Call the local API. Returns (status, json). Raises RelayError for 401 and no app."""
    url = "http://127.0.0.1:%d%s" % (local_port(), path)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + read_token())
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        # Never through HTTP(S)_PROXY: the token and messages stay on this Mac.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(req, timeout=TIMEOUT_S) as resp:
            return resp.status, _json(resp.read())
    except urllib.error.HTTPError as e:
        payload = _json(e.read())
        if e.code == 401:
            raise RelayError(
                "Agent Relay rejected the local token (401). The app rewrites "
                + token_path() + " every time it starts; if AGENT_RELAY_HOME is set, it must "
                "point at the running app's data folder.")
        return e.code, payload
    except urllib.error.URLError as e:
        if isinstance(e.reason, (ConnectionRefusedError, socket.timeout, TimeoutError)):
            raise RelayError(NOT_RUNNING, 2)
        raise RelayError("Couldn't reach Agent Relay on 127.0.0.1:%d: %s"
                         % (local_port(), e.reason), 2)
    except (ConnectionError, socket.timeout, TimeoutError):
        raise RelayError(NOT_RUNNING, 2)


def _json(raw):
    if not raw:
        return None
    try:
        return json.loads(raw.decode("utf-8"))
    except ValueError:
        return {"error": raw.decode("utf-8", "replace")}


def expect_ok(status, payload, what):
    if 200 <= status < 300:
        return payload
    err = payload.get("error") if isinstance(payload, dict) else None
    raise RelayError("%s failed (HTTP %d%s)." % (what, status, ": " + err if err else ""))


def get(path, what):
    status, payload = api("GET", path)
    return expect_ok(status, payload, what)


# --- formatting ---------------------------------------------------------------

def fmt_time(value):
    if value is None:
        return "?"
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value / 1000).strftime("%Y-%m-%d %H:%M")
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return dt.astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return str(value)


def context_line(ctx):
    if not isinstance(ctx, dict):
        return None
    parts = [str(ctx[k]) for k in ("repo", "branch", "commit", "path") if ctx.get(k)]
    return SEP.join(parts) if parts else None


def gap_banner(gap):
    n = gap.get("missing", 0)
    return "waiting for %d message%s from %s" % (n, "" if n == 1 else "s", gap.get("personName"))


LOCKED_REASONS = {
    "they_have_not_approved_you": "{name} hasn't approved you",
    "you_have_not_approved_them": "{name} hasn't been approved by you",
}


def print_message(m):
    sender = (m.get("from") or {}).get("personName", "?")
    if m.get("kind") == "event":
        print("· %s" % m.get("body"))
        print()
        return
    head = "[%s] %s%s%s" % (m.get("id"), sender, SEP, fmt_time(m.get("sentAt")))
    if m.get("arrivedLate"):
        head += SEP + "arrived late"
    print(head)
    ctx = context_line(m.get("context"))
    if ctx:
        print("context: " + ctx)
    if m.get("replyTo"):
        print("reply to: " + str(m["replyTo"]))
    reason = LOCKED_REASONS.get(m.get("lockedReason"))
    if reason and (m.get("status") == "locked" or m.get("body") is None):
        print("[locked — %s]" % reason.format(name=sender))
    elif m.get("status") == "locked" or m.get("body") is None:
        print("Locked — this message can't be read on this Mac.")
    else:
        print(m["body"])
    for r in m.get("receipts") or []:
        print(receipt_line(r))
    print()


def receipt_line(r):
    """Delivered / seen in the app / read by their agent, for one recipient."""
    who = r.get("personName", "?")
    if not r.get("deliveredAt"):
        return "  %s: not delivered yet" % who
    parts = ["delivered " + fmt_time(r["deliveredAt"])]
    if r.get("seenAt"):
        parts.append("seen " + fmt_time(r["seenAt"]))
    if r.get("agentReadAt"):
        parts.append("read by their agent " + fmt_time(r["agentReadAt"]))
    return "  %s: %s" % (who, SEP.join(parts))


def print_messages(name, payload, all_messages):
    for gap in payload.get("gaps") or []:
        print("(" + gap_banner(gap) + ")")
    msgs = payload.get("messages") or []
    if not msgs:
        print("No %smessages from %s." % ("" if all_messages else "unread ", name))
        return
    for m in msgs:
        print_message(m)


def channel_name(ch):
    peer = ch.get("peer") or {}
    return ch.get("name") or peer.get("personName") or ch.get("id")


def channel_label(ch):
    return "surat" if ch.get("kind") == "surat" else "private channel"


def print_draft(d, names):
    to = names.get(d.get("channelId"), d.get("channelId") or "?")
    when = d.get("createdAt") or d.get("sentAt")
    print("[%s] to %s%s%s%sawaiting approval" % (d.get("id"), to, SEP, fmt_time(when), SEP))
    if d.get("kind") == "event":
        print(d.get("body") or "")
        print()
        return
    ctx = context_line(d.get("context"))
    if ctx:
        print("context: " + ctx)
    if d.get("replyTo"):
        print("reply to: " + str(d["replyTo"]))
    print(d.get("body") or "")
    print()


def emit_json(payload):
    print(json.dumps(payload, indent=2, ensure_ascii=False))


# --- name resolution and git context -------------------------------------------

def resolve(target, channels, surat_only=False):
    """Return the channel for a channel id, a person's name or a surat name (case-insensitive).

    "surat {name}" means the surat only. Several matches exit 3 with the ids listed."""
    for ch in channels:
        if ch.get("id") == target and (not surat_only or ch.get("kind") == "surat"):
            return ch
    want = target.casefold()
    if want.startswith("surat "):
        want = want[len("surat "):].strip()
        surat_only = True
    surats = [ch for ch in channels if ch.get("kind") == "surat"
              and str(ch.get("name") or "").casefold() == want]
    privates = [] if surat_only else [
        ch for ch in channels if ch.get("kind", "private") == "private"
        and str((ch.get("peer") or {}).get("personName") or ch.get("name") or "")
        .casefold() == want]
    matches = privates + surats
    if len(matches) > 1:
        open_ones = [ch for ch in matches if not ch.get("closed")]
        if len(open_ones) == 1:
            return open_ones[0]
        lines = []
        for ch in matches:
            if ch.get("kind") == "surat":
                lines.append("%s (surat) → %s" % (channel_name(ch), ch["id"]))
            else:
                lines.append("%s (%s) → %s" % ((ch.get("peer") or {}).get("personName",
                                                                          channel_name(ch)),
                                                (ch.get("peer") or {}).get("deviceName", "?"),
                                                ch["id"]))
        what = "several surat" if all(ch.get("kind") == "surat" for ch in matches) \
            else "several Macs"
        raise RelayError("%s has %s. Pick one by channel id:\n  %s"
                         % (target, what, "\n  ".join(lines)), 3)
    if not matches:
        pool = [ch for ch in channels if ch.get("kind") == "surat"] if surat_only else channels
        known = sorted({channel_name(ch) for ch in pool})
        has_surat = any(ch.get("kind") == "surat" for ch in channels)
        noun = "surat" if surat_only else "private channel or surat" if has_surat \
            else "private channel"
        raise RelayError("No %s with %s. %s: %s."
                         % (noun, target, "Surat" if surat_only else "Channels",
                            ", ".join(known) if known else
                            "none" if surat_only else "none — pair in the app first"))
    return matches[0]


def resolve_person(name, peers):
    """Return the paired peer for a person's name (case-insensitive) or a device id."""
    paired = [p for p in peers if p.get("trust", "paired") == "paired"]
    for p in paired:
        if p.get("deviceId") == name:
            return p
    want = name.casefold()
    matches = [p for p in paired if str(p.get("personName") or "").casefold() == want]
    if len(matches) > 1:
        lines = ["%s (%s) → %s" % (p.get("personName"), p.get("deviceName", "?"),
                                   p.get("deviceId")) for p in matches]
        raise RelayError("%s has several Macs. Pick one by device id:\n  %s"
                         % (name, "\n  ".join(lines)), 3)
    if not matches:
        known = sorted({str(p.get("personName")) for p in paired})
        raise RelayError("No paired person %s. Paired: %s."
                         % (name, ", ".join(known) if known else "none — pair in the app first"))
    return matches[0]


def git_context(cwd=None):
    def git(*args):
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""

    try:
        top = git("rev-parse", "--show-toplevel")
    except OSError:
        return None
    if not top:
        return None
    ctx = {"repo": os.path.basename(top)}
    branch = git("rev-parse", "--abbrev-ref", "HEAD") or git("symbolic-ref", "--short", "HEAD")
    if branch:
        ctx["branch"] = branch
    commit = git("rev-parse", "--short", "HEAD")
    if commit:
        ctx["commit"] = commit
    here = os.path.realpath(cwd or os.getcwd())
    ctx["path"] = os.path.relpath(here, os.path.realpath(top))
    return ctx


SURAT_ERRORS = {
    "empty_name": "A surat needs a name.",
    "no_invitees": "Pick at least one person to invite.",
    "too_many_members": "A surat holds at most 5 devices.",
    "unknown_peer": "That person isn't paired with this Mac.",
    "not_allowed": "Not allowed: the surat has ended, isn't published yet, or you aren't "
                   "the one who can do that.",
    "channel_closed": "The surat {name} has ended.",
    "not_a_member": "You aren't a member of {name}.",
    "unknown_channel": "No such surat.",
}


def ask_line(draft_id, what):
    return ("Ask the person now, in the session's question dialog, with %s: "
            "Send -> relay.py approve %s · Discard -> relay.py discard %s · "
            "Edit -> discard, draft again, ask again." % (what, draft_id, draft_id))


def fetch_pending():
    status, payload = api("GET", "/pending")
    return payload if 200 <= status < 300 and isinstance(payload, list) else []


def print_pending(pending):
    print("== Waiting for your decision (%d) ==" % len(pending))
    for p in pending:
        who = "%s (%s)" % (p.get("personName"), p.get("deviceName"))
        by = p.get("inviterName")
        if p.get("kind") == "invite":
            line = "[%s] %s invited you to surat %s — Accept / Decline" % (
                p.get("id"), by or "Someone", p.get("suratName"))
        else:
            line = "[%s] %s wants to join surat %s%s — Approve / Decline" % (
                p.get("id"), who, p.get("suratName"), (", invited by " + by) if by else "")
        if p.get("declined"):
            line += " (you declined)"
        print(line)
    print()


def draft_surat(path, body, summary, args):
    """POST a surat drafting route and print the draft with the ask line."""
    status, payload = api("POST", path, body)
    err = payload.get("error") if isinstance(payload, dict) else None
    if err in SURAT_ERRORS:
        raise RelayError(SURAT_ERRORS[err].format(name=summary))
    payload = expect_ok(status, payload, "Drafting")
    if args.json:
        return emit_json(payload)
    draft_id = payload.get("id")
    print("Draft %s: %s — awaiting approval." % (draft_id, summary))
    print(ask_line(draft_id, "this action"))


# --- commands -----------------------------------------------------------------

def cmd_status(args):
    s = get("/status", "status")
    if args.json:
        return emit_json(s)
    print("Agent Relay %s — %s on %s (device %s)"
          % (s.get("version", "?"), s.get("personName"), s.get("deviceName"), s.get("deviceId")))


def cmd_peers(args):
    peers = get("/peers", "peers")
    if args.json:
        return emit_json(peers)
    if not peers:
        print("No paired people yet — pair in the Agent Relay app.")
        return
    for p in peers:
        bits = ["online" if p.get("reachable") else "offline"]
        trust = p.get("trust")
        if trust == "mismatch":
            bits.append("identity changed — pair again")
        elif trust and trust != "paired":
            bits.append(trust)
        skew = p.get("clockSkewMs")
        if skew:
            bits.append("clocks differ by %d s" % round(abs(skew) / 1000))
        print("%s (%s) — %s" % (p.get("personName"), p.get("deviceName"), ", ".join(bits)))


def cmd_channels(args):
    channels = get("/channels", "channels")
    if args.json:
        return emit_json(channels)
    if not channels:
        print("No channels yet — pair in the Agent Relay app.")
        return
    for ch in channels:
        kind = "private channel" if ch.get("kind", "private") == "private" else ch.get("kind")
        line = "%s — %s, %d unread" % (channel_name(ch), kind, ch.get("unread") or 0)
        if ch.get("kind") == "surat":
            n = len(ch.get("members") or [])
            if n:
                line += ", %d other member%s" % (n, "" if n == 1 else "s")
            if ch.get("pending"):
                line += ", %d waiting for a decision" % ch["pending"]
        if ch.get("closed"):
            line += ", closed"
        print(line + " → " + str(ch.get("id")))


def fetch_messages(ch, all_messages):
    path = "/channels/%s/messages?status=%s" % (
        urllib.parse.quote(str(ch["id"]), safe=""), "all" if all_messages else "unread")
    return get(path, "reading " + channel_name(ch))


def cmd_read(args):
    ch = resolve(args.target, get("/channels", "channels"))
    payload = fetch_messages(ch, args.all)
    if args.json:
        return emit_json(payload)
    print("== %s (%s) ==" % (channel_name(ch), channel_label(ch)))
    print_messages(channel_name(ch), payload, args.all)


def cmd_inbox(args):
    channels = get("/channels", "channels")
    result = []
    for ch in channels:
        if (ch.get("unread") or 0) > 0:
            result.append({"channel": ch, **fetch_messages(ch, False)})
    outbox = get("/outbox", "outbox") or []
    pending = fetch_pending()
    if args.json:
        return emit_json({"channels": result, "pending": pending, "outbox": outbox})
    if not result:
        print("No unread messages.")
    for entry in result:
        ch = entry["channel"]
        print("== %s (%s) — %d unread ==" % (channel_name(ch), channel_label(ch),
                                             len(entry["messages"])))
        print_messages(channel_name(ch), entry, False)
    if pending:
        print_pending(pending)
    if outbox:
        names = {c.get("id"): channel_name(c) for c in channels}
        print("== Your drafts awaiting approval (%d) ==" % len(outbox))
        for d in outbox:
            print_draft(d, names)


def cmd_send(args):
    body = sys.stdin.read().rstrip("\n")
    if not body.strip():
        raise RelayError("Nothing to send — pass the message text on stdin.")
    ch = resolve(args.target, get("/channels", "channels"))
    name = channel_name(ch)
    req = {"body": body}
    ctx = git_context() if args.context == "auto" else None
    if ctx:
        req["context"] = ctx
    if args.reply_to:
        req["replyTo"] = args.reply_to
    status, payload = api("POST", "/channels/%s/send" % urllib.parse.quote(str(ch["id"]), safe=""),
                          req)
    err = payload.get("error") if isinstance(payload, dict) else None
    if status == 413 or err == "body_too_large":
        limit = (payload or {}).get("limit", BODY_LIMIT)
        raise RelayError("Message is too long: %d bytes (UTF-8), the limit is %d bytes. "
                         "Shorten it or split it into several messages."
                         % (len(body.encode("utf-8")), limit))
    if ch.get("kind") == "surat" and (status in (403, 404, 409) or err):
        if err in SURAT_ERRORS:
            raise RelayError(SURAT_ERRORS[err].format(name=name))
    if status == 409 or err == "channel_closed":
        raise RelayError("The private channel with %s is closed (they unpaired). "
                         "Pair again in the Agent Relay app." % name)
    payload = expect_ok(status, payload, "Sending to " + name)
    if args.json:
        return emit_json(payload)
    draft_id = payload.get("id")
    print("Draft %s to %s — awaiting approval." % (draft_id, name))
    print("context: " + (context_line(ctx) or "none"))
    if args.reply_to:
        print("reply to: " + args.reply_to)
    print("----- exact text -----")
    print(body)
    print("----------------------")
    print(ask_line(draft_id, "this exact text and context line"))


def outbox_action(draft_id, action):
    status, payload = api("POST", "/outbox/%s/%s" % (urllib.parse.quote(draft_id, safe=""), action))
    if status == 404:
        raise RelayError("No draft %s in the outbox (already sent, discarded or expired?)."
                         % draft_id)
    return expect_ok(status, payload, "%s %s" % (action.capitalize(), draft_id))


def cmd_approve(args):
    payload = outbox_action(args.draft_id, "approve")
    if args.json:
        return emit_json(payload)
    state = payload.get("status")
    queued = payload.get("queuedFor") or []
    if state == "sent":
        print("Sent.")
    elif state == "queued":
        if queued:
            print("Approved — queued for %s (offline). Agent Relay delivers it when their "
                  "Mac is reachable." % ", ".join(queued))
        else:
            print("Approved — queued; Agent Relay is delivering it.")
    elif state == "expired":
        raise RelayError("Not sent: draft %s expired (drafts expire after 1 hour). "
                         "Draft it again." % args.draft_id)
    elif state == "discarded":
        raise RelayError("Not sent: draft %s was discarded." % args.draft_id)
    else:
        raise RelayError("Not sent: draft %s is %s." % (args.draft_id, state))


def cmd_discard(args):
    payload = outbox_action(args.draft_id, "discard")
    if args.json:
        return emit_json(payload)
    print("Discarded draft %s." % args.draft_id)


def cmd_outbox(args):
    outbox = get("/outbox", "outbox") or []
    if args.json:
        return emit_json(outbox)
    if not outbox:
        print("Nothing awaiting approval.")
        return
    names = {c.get("id"): channel_name(c) for c in get("/channels", "channels")}
    for d in outbox:
        print_draft(d, names)


def cmd_surat_new(args):
    peers = get("/peers", "peers") or []
    people = [resolve_person(n, peers) for n in args.people]
    ids = [p["deviceId"] for p in people]
    who = ", ".join("%s (%s)" % (p.get("personName"), p.get("deviceName")) for p in people)
    draft_surat("/surat", {"name": args.name, "invite": ids},
                "new surat %s with %s" % (args.name, who), args)


def surat_path(ch, action):
    return "/surat/%s/%s" % (urllib.parse.quote(str(ch["id"]), safe=""), action)


def cmd_invite(args):
    channels = get("/channels", "channels")
    ch = resolve(args.surat, channels, surat_only=True)
    person = resolve_person(args.person, get("/peers", "peers") or [])
    draft_surat(surat_path(ch, "invite"), {"deviceId": person["deviceId"]},
                "invite %s (%s) to %s" % (person.get("personName"), person.get("deviceName"),
                                          channel_name(ch)), args)


def cmd_leave(args):
    ch = resolve(args.surat, get("/channels", "channels"), surat_only=True)
    draft_surat(surat_path(ch, "leave"), None, "leave %s" % channel_name(ch), args)


def cmd_rename(args):
    ch = resolve(args.surat, get("/channels", "channels"), surat_only=True)
    draft_surat(surat_path(ch, "rename"), {"name": args.new_name},
                "rename %s to %s" % (channel_name(ch), args.new_name), args)


def cmd_pending(args):
    pending = fetch_pending()
    if args.json:
        return emit_json(pending)
    if not pending:
        print("Nothing waiting for your decision.")
        return
    print_pending(pending)


def cmd_decide(args):
    action = args.decision
    status, payload = api("POST", "/pending/%s/%s" % (urllib.parse.quote(args.pending_id, safe=""),
                                                      action))
    err = payload.get("error") if isinstance(payload, dict) else None
    if status == 409 or err == "already_approved":
        raise RelayError("Already approved — nothing to do.")
    if status == 404 or err == "unknown_pending":
        raise RelayError("No pending item %s (already decided, or the surat changed)."
                         % args.pending_id)
    if status == 403 or err == "not_allowed":
        raise RelayError("Not allowed: that surat has ended.")
    payload = expect_ok(status, payload, "Deciding " + args.pending_id)
    if args.json:
        return emit_json(payload)
    print("Approved." if action == "approve" else "Declined.")


# --- CLI ----------------------------------------------------------------------

def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", default=argparse.SUPPRESS,
                        help="print the raw API JSON")
    p = argparse.ArgumentParser(prog="relay.py", parents=[common],
                                description="Agent Relay inbox: read and send private channel "
                                            "messages through this Mac's Agent Relay app.")
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("status", parents=[common], help="this Mac's identity").set_defaults(
        func=cmd_status)
    sub.add_parser("peers", parents=[common], help="paired people and who's online").set_defaults(
        func=cmd_peers)
    sub.add_parser("channels", parents=[common], help="channels with unread counts").set_defaults(
        func=cmd_channels)

    r = sub.add_parser("read", parents=[common], help="read a channel (unread by default)")
    r.add_argument("target", help="person's name or channel id")
    r.add_argument("--all", action="store_true", help="all messages, not only unread")
    r.set_defaults(func=cmd_read)

    sub.add_parser("inbox", parents=[common],
                   help="every channel with unread messages, then drafts awaiting approval"
                   ).set_defaults(func=cmd_inbox)

    s = sub.add_parser("send", parents=[common],
                       help="draft a message (body on stdin); it waits for approval")
    s.add_argument("target", help="person's name or channel id")
    s.add_argument("--reply-to", metavar="ID", help="message id this replies to")
    s.add_argument("--context", choices=["auto", "none"], default="auto",
                   help="auto adds repo, branch, commit, path when inside a git repo (default)")
    s.set_defaults(func=cmd_send)

    a = sub.add_parser("approve", parents=[common], help="send a draft (after the person's yes)")
    a.add_argument("draft_id")
    a.set_defaults(func=cmd_approve)

    d = sub.add_parser("discard", parents=[common], help="drop a draft")
    d.add_argument("draft_id")
    d.set_defaults(func=cmd_discard)

    sub.add_parser("outbox", parents=[common], help="drafts awaiting approval").set_defaults(
        func=cmd_outbox)

    n = sub.add_parser("surat-new", parents=[common],
                       help="draft a new surat (group channel of up to 5 devices)")
    n.add_argument("name", help="the surat's name")
    n.add_argument("--with", dest="people", nargs="+", required=True, metavar="PERSON",
                   help="paired people to invite")
    n.set_defaults(func=cmd_surat_new)

    i = sub.add_parser("invite", parents=[common], help="draft an invite into a surat")
    i.add_argument("person")
    i.add_argument("--to", dest="surat", required=True, metavar="SURAT")
    i.set_defaults(func=cmd_invite)

    lv = sub.add_parser("leave", parents=[common], help="draft leaving a surat")
    lv.add_argument("surat")
    lv.set_defaults(func=cmd_leave)

    rn = sub.add_parser("rename", parents=[common], help="draft renaming a surat")
    rn.add_argument("surat")
    rn.add_argument("new_name")
    rn.set_defaults(func=cmd_rename)

    sub.add_parser("pending", parents=[common],
                   help="invites and newcomers waiting for your decision").set_defaults(
        func=cmd_pending)

    dc = sub.add_parser("decide", parents=[common],
                        help="record the person's own answer on a pending item")
    dc.add_argument("pending_id")
    dc.add_argument("decision", choices=["approve", "decline"])
    dc.set_defaults(func=cmd_decide)
    return p


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    args = build_parser().parse_args(argv)
    if not hasattr(args, "json"):
        args.json = False
    try:
        args.func(args)
    except RelayError as e:
        print(str(e), file=sys.stderr)
        return e.code
    return 0


if __name__ == "__main__":
    sys.exit(main())
