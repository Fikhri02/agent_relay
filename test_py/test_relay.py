"""Tests for skill/inbox/scripts/relay.py against a fake Agent Relay local API.

Run from the repo root: python3 -m unittest test_py.test_relay -v
"""

import copy
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO_ROOT, "skill", "inbox", "scripts", "relay.py")
TOKEN = "test-token-abc123"

XAVIER_PEER = {"deviceId": "dev-x", "personName": "Xavier", "deviceName": "Xavier MBP"}
TOMMY_PEER = {"deviceId": "dev-t", "personName": "Tommy", "deviceName": "Tommy iMac"}

DEFAULT_STATE = {
    "status": {
        "deviceId": "dev-me",
        "personName": "Irfan",
        "deviceName": "Irfan MacBook",
        "version": "0.1.0",
    },
    "peers": [
        dict(XAVIER_PEER, trust="paired", reachable=True, clockSkewMs=None),
        dict(TOMMY_PEER, trust="paired", reachable=False, clockSkewMs=45000),
    ],
    "channels": [
        {"id": "ch-x", "kind": "private", "name": "Xavier", "peer": XAVIER_PEER,
         "unread": 2, "closed": False},
        {"id": "ch-t", "kind": "private", "name": "Tommy", "peer": TOMMY_PEER,
         "unread": 0, "closed": False},
    ],
    "messages": {
        "ch-x": {
            "messages": [
                {"id": "m-1", "from": {"deviceId": "dev-x", "personName": "Xavier"},
                 "sentAt": 1763600000000, "hlc": "h1", "body": "Pushed the fix to develop.",
                 "context": {"repo": "middleware", "branch": "develop", "commit": "abc1234",
                             "path": "src/Api"},
                 "replyTo": None, "status": "unread", "arrivedLate": False},
                {"id": "m-2", "from": {"deviceId": "dev-x", "personName": "Xavier"},
                 "sentAt": 1763600060000, "hlc": "h2", "body": "Can you check the POS build?",
                 "context": None, "replyTo": "m-0", "status": "unread", "arrivedLate": True},
            ],
            "gaps": [{"personName": "Xavier", "missing": 1}],
        },
        "ch-t": {"messages": [], "gaps": []},
    },
    "outbox": [],
    "send": {"code": 201, "json": {"id": "d-42", "status": "awaiting_approval"}},
    "approve": {"code": 200, "json": {"status": "queued", "queuedFor": ["Tommy"]}},
    "discard": {"code": 200, "json": {"status": "discarded"}},
}


class FakeRelay:
    """A fake local API on 127.0.0.1 with a random port."""

    def __init__(self):
        self.state = copy.deepcopy(DEFAULT_STATE)
        self.requests = []
        relay = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _reply(self, code, payload):
                data = json.dumps(payload).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _handle(self, method):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                body = json.loads(raw.decode("utf-8")) if raw else None
                relay.requests.append({"method": method, "path": self.path, "body": body,
                                       "auth": self.headers.get("Authorization")})
                if self.headers.get("Authorization") != "Bearer " + TOKEN:
                    return self._reply(401, {"error": "unauthorized"})
                url = urlsplit(self.path)
                parts = [p for p in url.path.split("/") if p]
                s = relay.state
                if method == "GET" and parts == ["status"]:
                    return self._reply(200, s["status"])
                if method == "GET" and parts == ["peers"]:
                    return self._reply(200, s["peers"])
                if method == "GET" and parts == ["channels"]:
                    return self._reply(200, s["channels"])
                if method == "GET" and parts == ["outbox"]:
                    return self._reply(200, s["outbox"])
                if len(parts) == 3 and parts[0] == "channels":
                    if parts[1] not in s["messages"]:
                        return self._reply(404, {"error": "unknown_channel"})
                    if method == "GET" and parts[2] == "messages":
                        return self._reply(200, s["messages"][parts[1]])
                    if method == "POST" and parts[2] == "send":
                        return self._reply(s["send"]["code"], s["send"]["json"])
                if method == "POST" and len(parts) == 3 and parts[0] == "outbox":
                    if parts[2] in ("approve", "discard"):
                        r = s[parts[2]]
                        return self._reply(r["code"], r["json"])
                return self._reply(404, {"error": "not_found"})

            def do_GET(self):
                self._handle("GET")

            def do_POST(self):
                self._handle("POST")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    def paths(self, method=None):
        return [r["path"] for r in self.requests if method is None or r["method"] == method]

    def last_post(self):
        return [r for r in self.requests if r["method"] == "POST"][-1]


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class RelayScriptTest(unittest.TestCase):
    def setUp(self):
        self.relay = FakeRelay()
        self.addCleanup(self.relay.stop)
        self.home = tempfile.mkdtemp(prefix="agent-relay-home-")
        self.addCleanup(shutil.rmtree, self.home, True)
        self.write_token(TOKEN)
        self.port = self.relay.port

    def write_token(self, token):
        with open(os.path.join(self.home, "local-token"), "w") as f:
            f.write(token + "\n")

    def run_relay(self, *args, stdin="", cwd=None):
        env = dict(os.environ)
        env["AGENT_RELAY_HOME"] = self.home
        env["AGENT_RELAY_LOCAL_PORT"] = str(self.port)
        return subprocess.run(
            [sys.executable, SCRIPT, *args], input=stdin, capture_output=True,
            text=True, env=env, cwd=cwd or self.home, timeout=30,
        )

    def output(self, result):
        return result.stdout + result.stderr

    # --- the plan's six tests -------------------------------------------------

    def test_send_prints_draft_id_and_awaiting_approval(self):
        r = self.run_relay("send", "Xavier", "--context", "none",
                           stdin="Build is green on develop.\n")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("d-42", r.stdout)
        self.assertIn("awaiting approval", r.stdout)
        self.assertIn("Build is green on develop.", r.stdout)
        post = self.relay.last_post()
        self.assertEqual(post["path"], "/channels/ch-x/send")
        self.assertEqual(post["body"]["body"], "Build is green on develop.")
        self.assertNotIn("context", post["body"])

    def test_read_by_person_name_resolves_private_channel(self):
        r = self.run_relay("read", "xAVIER")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("/channels/ch-x/messages?status=unread", self.relay.paths("GET"))
        self.assertIn("Pushed the fix to develop.", r.stdout)
        self.assertIn("Can you check the POS build?", r.stdout)

    def test_two_devices_for_one_person_exit_3_and_list_them(self):
        self.relay.state["channels"] = [
            {"id": "ch-x1", "kind": "private", "name": "Xavier", "peer": XAVIER_PEER,
             "unread": 0, "closed": False},
            {"id": "ch-x2", "kind": "private", "name": "Xavier",
             "peer": {"deviceId": "dev-x2", "personName": "Xavier", "deviceName": "Xavier iMac"},
             "unread": 0, "closed": False},
        ]
        r = self.run_relay("read", "xavier")
        self.assertEqual(r.returncode, 3, self.output(r))
        out = self.output(r)
        self.assertIn("Xavier (Xavier MBP) → ch-x1", out)
        self.assertIn("Xavier (Xavier iMac) → ch-x2", out)
        self.assertFalse(any("/messages" in p for p in self.relay.paths()))

    def test_connection_refused_exit_2_with_message(self):
        self.port = free_port()
        r = self.run_relay("inbox")
        self.assertEqual(r.returncode, 2, self.output(r))
        self.assertIn("Agent Relay isn't running — open it from Applications.", self.output(r))

    def test_context_auto_fills_repo_branch_commit_inside_git(self):
        repo = os.path.join(self.home, "my-repo")
        sub = os.path.join(repo, "lib", "core")
        os.makedirs(sub)

        def git(*a):
            return subprocess.run(["git", *a], cwd=repo, check=True, capture_output=True,
                                  text=True).stdout.strip()

        git("init", "-q", "-b", "feature/relay")
        with open(os.path.join(repo, "a.txt"), "w") as f:
            f.write("a")
        git("add", "a.txt")
        git("-c", "user.name=t", "-c", "user.email=t@example.com",
            "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init")
        short = git("rev-parse", "--short", "HEAD")

        r = self.run_relay("send", "Xavier", stdin="hello", cwd=sub)
        self.assertEqual(r.returncode, 0, self.output(r))
        ctx = self.relay.last_post()["body"]["context"]
        self.assertEqual(ctx, {"repo": "my-repo", "branch": "feature/relay",
                               "commit": short, "path": "lib/core"})
        self.assertIn("my-repo · feature/relay · " + short, r.stdout)

    def test_inbox_prints_gaps_banner(self):
        r = self.run_relay("inbox")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("waiting for 1 message from Xavier", r.stdout)
        self.assertIn("Pushed the fix to develop.", r.stdout)
        # only channels with unread are read
        self.assertIn("/channels/ch-x/messages?status=unread", self.relay.paths("GET"))
        self.assertFalse(any(p.startswith("/channels/ch-t/") for p in self.relay.paths()))

    # --- more coverage --------------------------------------------------------

    def test_token_sent_as_bearer(self):
        self.run_relay("status")
        self.assertEqual(self.relay.requests[0]["auth"], "Bearer " + TOKEN)

    def test_inbox_shows_context_line_arrived_late_and_reply_to(self):
        r = self.run_relay("inbox")
        self.assertIn("middleware · develop · abc1234 · src/Api", r.stdout)
        self.assertIn("arrived late", r.stdout)
        self.assertIn("m-0", r.stdout)

    def test_read_shows_receipts_on_my_messages(self):
        self.relay.state["messages"]["ch-x"]["messages"].append(
            {"id": "m-3", "direction": "out", "from": {"deviceId": "dev-me", "personName": "Irfan"},
             "sentAt": 1763600120000, "hlc": "h3", "body": "Staging is free now", "context": None,
             "replyTo": None, "status": "sent", "arrivedLate": False,
             "receipts": [{"personName": "Xavier", "deliveredAt": 1763600121000,
                           "seenAt": 1763600180000, "agentReadAt": 1763600240000}]})
        r = self.run_relay("read", "Xavier", "--all")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("Xavier: delivered", r.stdout)
        self.assertIn("seen", r.stdout)
        self.assertIn("read by their agent", r.stdout)

    def test_read_shows_waiting_when_not_delivered(self):
        self.relay.state["messages"]["ch-x"]["messages"].append(
            {"id": "m-4", "direction": "out", "from": {"deviceId": "dev-me", "personName": "Irfan"},
             "sentAt": 1763600120000, "hlc": "h4", "body": "x", "context": None,
             "replyTo": None, "status": "queued", "arrivedLate": False,
             "receipts": [{"personName": "Xavier", "deliveredAt": None, "seenAt": None, "agentReadAt": None}]})
        r = self.run_relay("read", "Xavier", "--all")
        self.assertIn("Xavier: not delivered yet", r.stdout)

    def test_inbox_plural_gap_banner(self):
        self.relay.state["messages"]["ch-x"]["gaps"] = [{"personName": "Xavier", "missing": 3}]
        r = self.run_relay("inbox")
        self.assertIn("waiting for 3 messages from Xavier", r.stdout)

    def test_inbox_nothing_unread(self):
        for ch in self.relay.state["channels"]:
            ch["unread"] = 0
        r = self.run_relay("inbox")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("No unread messages", r.stdout)

    def test_inbox_lists_drafts_awaiting_approval_after_messages(self):
        self.relay.state["outbox"] = [
            {"id": "d-7", "channelId": "ch-t", "body": "Draft for Tommy", "context": None,
             "status": "awaiting_approval", "createdAt": 1763600000000},
        ]
        r = self.run_relay("inbox")
        self.assertIn("d-7", r.stdout)
        self.assertGreater(r.stdout.index("d-7"), r.stdout.index("Pushed the fix"))

    def test_locked_message_shows_locked(self):
        self.relay.state["messages"]["ch-x"]["messages"][0].update(body=None, status="locked")
        r = self.run_relay("read", "Xavier")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("Locked", r.stdout)

    def test_read_all_flag(self):
        r = self.run_relay("read", "Xavier", "--all")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("/channels/ch-x/messages?status=all", self.relay.paths("GET"))

    def test_read_by_channel_id(self):
        r = self.run_relay("read", "ch-t")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("/channels/ch-t/messages?status=unread", self.relay.paths("GET"))

    def test_unknown_name_exit_1_lists_people(self):
        r = self.run_relay("read", "Nobody")
        self.assertEqual(r.returncode, 1, self.output(r))
        self.assertIn("Nobody", r.stderr)
        self.assertIn("Xavier", r.stderr)
        self.assertIn("Tommy", r.stderr)

    def test_send_reply_to(self):
        r = self.run_relay("send", "Xavier", "--reply-to", "m-2", "--context", "none",
                           stdin="On it.")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertEqual(self.relay.last_post()["body"]["replyTo"], "m-2")

    def test_send_outside_git_has_no_context(self):
        r = self.run_relay("send", "Xavier", stdin="hello")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertNotIn("context", self.relay.last_post()["body"])

    def test_send_empty_body_is_rejected_without_calling_send(self):
        r = self.run_relay("send", "Xavier", stdin="  \n")
        self.assertEqual(r.returncode, 1, self.output(r))
        self.assertFalse(any(p.endswith("/send") for p in self.relay.paths()))

    def test_send_body_too_large_413(self):
        self.relay.state["send"] = {"code": 413,
                                    "json": {"error": "body_too_large", "limit": 32768}}
        r = self.run_relay("send", "Xavier", "--context", "none", stdin="é" * 16385)
        self.assertEqual(r.returncode, 1, self.output(r))
        self.assertIn("too long", r.stderr)
        self.assertIn("32770", r.stderr)
        self.assertIn("32768", r.stderr)

    def test_send_channel_closed_409(self):
        self.relay.state["send"] = {"code": 409, "json": {"error": "channel_closed"}}
        r = self.run_relay("send", "Xavier", "--context", "none", stdin="hi")
        self.assertEqual(r.returncode, 1, self.output(r))
        self.assertIn("closed", r.stderr)

    def test_approve_reports_queued_for_offline(self):
        r = self.run_relay("approve", "d-42")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertEqual(self.relay.last_post()["path"], "/outbox/d-42/approve")
        self.assertIn("queued for Tommy (offline)", r.stdout)

    def test_approve_sent(self):
        self.relay.state["approve"] = {"code": 200, "json": {"status": "sent", "queuedFor": []}}
        r = self.run_relay("approve", "d-42")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("Sent", r.stdout)
        self.assertNotIn("queued", r.stdout)

    def test_approve_expired_draft_is_not_sent(self):
        self.relay.state["approve"] = {"code": 200, "json": {"status": "expired", "queuedFor": []}}
        r = self.run_relay("approve", "d-42")
        self.assertEqual(r.returncode, 1, self.output(r))
        self.assertIn("expired", r.stderr)

    def test_approve_unknown_draft_404(self):
        self.relay.state["approve"] = {"code": 404, "json": {"error": "not_found"}}
        r = self.run_relay("approve", "d-404")
        self.assertEqual(r.returncode, 1, self.output(r))
        self.assertIn("d-404", r.stderr)

    def test_discard(self):
        r = self.run_relay("discard", "d-42")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertEqual(self.relay.last_post()["path"], "/outbox/d-42/discard")
        self.assertIn("Discarded", r.stdout)

    def test_outbox_lists_drafts_with_recipient(self):
        self.relay.state["outbox"] = [
            {"id": "d-7", "channelId": "ch-t", "body": "Draft for Tommy",
             "context": {"repo": "pos", "branch": "main", "commit": "fff0000"},
             "status": "awaiting_approval", "createdAt": 1763600000000},
        ]
        r = self.run_relay("outbox")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("d-7", r.stdout)
        self.assertIn("Tommy", r.stdout)
        self.assertIn("Draft for Tommy", r.stdout)
        self.assertIn("pos · main · fff0000", r.stdout)

    def test_outbox_empty(self):
        r = self.run_relay("outbox")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("Nothing awaiting approval", r.stdout)

    def test_peers_shows_reachability_and_clock_skew(self):
        self.relay.state["peers"].append(
            {"deviceId": "dev-k", "personName": "Kim", "deviceName": "Kim MBP",
             "trust": "mismatch", "reachable": False, "clockSkewMs": None})
        r = self.run_relay("peers")
        self.assertEqual(r.returncode, 0, self.output(r))
        lines = r.stdout.splitlines()
        xavier = next(line for line in lines if "Xavier" in line)
        tommy = next(line for line in lines if "Tommy" in line)
        kim = next(line for line in lines if "Kim" in line)
        self.assertIn("online", xavier)
        self.assertIn("offline", tommy)
        self.assertIn("clocks differ by 45 s", tommy)
        self.assertIn("identity changed", kim)

    def test_channels_lists_unread_counts(self):
        r = self.run_relay("channels")
        self.assertEqual(r.returncode, 0, self.output(r))
        xavier = next(line for line in r.stdout.splitlines() if "Xavier" in line)
        self.assertIn("2 unread", xavier)
        self.assertIn("ch-x", xavier)

    def test_status(self):
        r = self.run_relay("status")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertIn("Irfan", r.stdout)
        self.assertIn("Irfan MacBook", r.stdout)
        self.assertIn("0.1.0", r.stdout)

    def test_json_output_is_raw_api_json(self):
        r = self.run_relay("--json", "channels")
        self.assertEqual(r.returncode, 0, self.output(r))
        self.assertEqual(json.loads(r.stdout), self.relay.state["channels"])
        r = self.run_relay("peers", "--json")
        self.assertEqual(json.loads(r.stdout), self.relay.state["peers"])
        r = self.run_relay("send", "Xavier", "--context", "none", "--json", stdin="x")
        self.assertEqual(json.loads(r.stdout), {"id": "d-42", "status": "awaiting_approval"})

    def test_json_inbox(self):
        r = self.run_relay("inbox", "--json")
        self.assertEqual(r.returncode, 0, self.output(r))
        data = json.loads(r.stdout)
        self.assertEqual(data["channels"][0]["channel"]["id"], "ch-x")
        self.assertEqual(data["channels"][0]["gaps"], [{"personName": "Xavier", "missing": 1}])
        self.assertEqual(len(data["channels"][0]["messages"]), 2)
        self.assertEqual(data["outbox"], [])

    def test_bad_token_401_clear_message(self):
        self.write_token("wrong-token")
        r = self.run_relay("channels")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("token", r.stderr)
        self.assertIn("local-token", r.stderr)
        self.assertNotIn("Traceback", r.stderr)

    def test_missing_token_file_exit_2(self):
        os.remove(os.path.join(self.home, "local-token"))
        r = self.run_relay("inbox")
        self.assertEqual(r.returncode, 2, self.output(r))
        self.assertIn("Agent Relay isn't running", r.stderr)


if __name__ == "__main__":
    unittest.main()
