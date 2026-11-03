"""H8 spike helper: stands in for K2 relay auth, mints local dummy relay JWTs, serves the viewer.

Endpoints (127.0.0.1:8780 by default, PORT env to change; HOST=0.0.0.0 to expose):
  POST /internal/v1/relay-auth   MediaMTX authHTTPAddress. Logs every payload (JWTs reduced to
                                 claims + length) to .local/auth.jsonl and applies the C4 rule:
                                 aud=relay, publish needs typ=publish, read needs typ=whep, path == claim.
  GET  /mint?typ=publish|whep&path=court/<id>/<slot>&ttl=3600
                                 ES256 JWT signed by a throwaway key in .local/ (never a real secret).
  GET  /clock                    Mac clock offset to an SNTP server, for the viewer's latency maths.
  POST /viewer-stats             Viewer samples, appended to .local/viewer.jsonl.
  GET  /                         viewer/index.html
"""

import base64
import json
import os
import socket
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature

ROOT = Path(__file__).resolve().parent
LOCAL = ROOT / ".local"
LOCAL.mkdir(exist_ok=True)
KEY_FILE = LOCAL / "relay-key.pem"
NTP_HOST = os.environ.get("NTP", "time.google.com")

if KEY_FILE.exists():
    KEY = serialization.load_pem_private_key(KEY_FILE.read_bytes(), None)
else:
    KEY = ec.generate_private_key(ec.SECP256R1())
    KEY_FILE.write_bytes(KEY.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    KEY_FILE.chmod(0o600)

clock = {"ntpOffsetMs": None, "ntpRttMs": None, "server": NTP_HOST}
log_lock = threading.Lock()


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def b64url_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def mint(typ: str, path: str, ttl: int) -> str:
    header = {"alg": "ES256", "typ": "JWT", "kid": "h8-spike"}
    # Same claim set as C0 relay tokens, with a device-shaped sub to size the SRT streamid.
    claims = {"aud": "relay", "sub": "device:6f1c2a0e-3b7d-4c55-9a1e-2d8f0b9c7e41", "typ": typ,
              "path": path, "exp": int(time.time()) + ttl}
    signing_input = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
        b64url(json.dumps(claims, separators=(",", ":")).encode())
    r, s = decode_dss_signature(KEY.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
    return signing_input + "." + b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


def verify(token: str):
    head, body, sig = token.split(".")
    raw = b64url_decode(sig)
    signature = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    KEY.public_key().verify(signature, f"{head}.{body}".encode(), ec.ECDSA(hashes.SHA256()))
    return json.loads(b64url_decode(body))


def find_jwt(payload: dict):
    """C4: JWT from Bearer (MediaMTX puts it in token), password, or query token=/jwt=."""
    query = parse_qs(payload.get("query") or "")
    for source, value in (("token", payload.get("token")), ("password", payload.get("password")),
                          ("query.token", (query.get("token") or [None])[0]),
                          ("query.jwt", (query.get("jwt") or [None])[0])):
        if value and value.count(".") == 2:
            return source, value
    return None, None


def authorize(payload: dict):
    source, token = find_jwt(payload)
    if token is None:
        return False, "no jwt", source, None
    try:
        claims = verify(token)
    except Exception as error:  # noqa: BLE001 - spike: any bad token is a 401
        return False, f"bad jwt: {error.__class__.__name__}", source, None
    want = {"publish": "publish", "read": "whep", "playback": "whep"}.get(payload.get("action"))
    if claims.get("aud") != "relay":
        return False, "aud", source, claims
    if want is None or claims.get("typ") != want:
        return False, f"typ {claims.get('typ')} for {payload.get('action')}", source, claims
    if claims.get("path") != payload.get("path"):
        return False, "path", source, claims
    if claims.get("exp", 0) < time.time():
        return False, "expired", source, claims
    return True, "ok", source, claims


def redacted(payload: dict) -> dict:
    out = dict(payload)
    for key in ("token", "password"):
        if out.get(key):
            out[key] = f"<{len(out[key])} chars>"
    if out.get("query"):
        parsed = parse_qs(out["query"])
        out["query"] = {k: (f"<{len(v[0])} chars>" if k in ("token", "jwt") else v[0]) for k, v in parsed.items()}
    return out


def append(name: str, record: dict):
    with log_lock, open(LOCAL / name, "a") as fh:
        fh.write(json.dumps(record) + "\n")


def sntp_loop():
    while True:
        best = None
        for _ in range(6):
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                    sock.settimeout(1.5)
                    t1 = time.time()
                    sock.sendto(b"\x23" + 47 * b"\0", (NTP_HOST, 123))
                    data, _ = sock.recvfrom(48)
                    t4 = time.time()
                secs, frac, secs3, frac3 = struct.unpack("!II", data[32:40]) + struct.unpack("!II", data[40:48])
                t2 = secs - 2208988800 + frac / 2**32
                t3 = secs3 - 2208988800 + frac3 / 2**32
                rtt = (t4 - t1) - (t3 - t2)
                if best is None or rtt < best[1]:
                    best = (((t2 - t1) + (t3 - t4)) / 2, rtt)
            except OSError:
                pass
        if best:
            clock.update(ntpOffsetMs=round(best[0] * 1000, 2), ntpRttMs=round(best[1] * 1000, 2))
        time.sleep(60)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def do_POST(self):
        url = urlparse(self.path)
        if url.path == "/internal/v1/relay-auth":
            payload = json.loads(self.body() or b"{}")
            ok, reason, source, claims = authorize(payload)
            record = {"t": time.time(), "ok": ok, "reason": reason, "jwtFrom": source,
                      "jwtLen": len(find_jwt(payload)[1] or ""), "claims": claims, "payload": redacted(payload)}
            append("auth.jsonl", record)
            print("auth", json.dumps(record), flush=True)
            self.send_json(200 if ok else 401, {"ok": ok})
        elif url.path == "/viewer-stats":
            append("viewer.jsonl", json.loads(self.body() or b"{}"))
            self.send_json(200, {})
        else:
            self.send_json(404, {})

    def do_GET(self):
        url = urlparse(self.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        if url.path == "/mint":
            path = query.get("path", "court/demo/left")
            token = mint(query.get("typ", "publish"), path, int(query.get("ttl", "3600")))
            streamid = f"publish:{path}:d:{token}"
            self.send_json(200, {"token": token, "length": len(token), "srtStreamid": streamid,
                                 "srtStreamidLength": len(streamid)})
        elif url.path == "/clock":
            self.send_json(200, dict(clock, macMs=time.time() * 1000))
        elif url.path in ("/", "/index.html"):
            data = (ROOT / "viewer" / "index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_json(404, {})


if __name__ == "__main__":
    threading.Thread(target=sntp_loop, daemon=True).start()
    host, port = os.environ.get("HOST", "127.0.0.1"), int(os.environ.get("PORT", "8780"))
    print(f"relay_server on http://{host}:{port}", flush=True)
    ThreadingHTTPServer((host, port), Handler).serve_forever()
