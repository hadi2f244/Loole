#!/usr/bin/env python3
"""
Loole Python SOCKS5 Client
Uses Google Drive as a covert transport proxy (same protocol as the Go client).
"""

import json
import logging
import os
import secrets
import ssl
import struct
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, Optional, Tuple

import requests
import urllib3
from requests.adapters import HTTPAdapter
from urllib3.poolmanager import PoolManager
from urllib3.util.ssl_ import create_urllib3_context
import socket

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("loole")

# ─────────────────────────────────────────────
# CONFIG  — loaded from config.json (same directory)
# ─────────────────────────────────────────────
_HERE = os.path.dirname(os.path.abspath(__file__))
_CONFIG_PATH = os.path.join(_HERE, "config.json")

with open(_CONFIG_PATH) as _f:
    _cfg = json.load(_f)


def _resolve(path: str) -> str:
    """Resolve a path relative to config.json's directory."""
    return os.path.normpath(os.path.join(_HERE, path))


CREDENTIALS_JSON = _resolve(_cfg["credentials_json"])
TOKEN_CACHE = _resolve(_cfg["token_cache"])
FOLDER_ID = _cfg["google_folder_id"]
SOCKS_LISTEN = _cfg.get("socks_listen", "127.0.0.1:1080")
POLL_INTERVAL = _cfg.get("poll_interval_ms", 300) / 1000
FLUSH_INTERVAL = _cfg.get("flush_interval_ms", 200) / 1000
CLIENT_ID = _cfg.get("client_id") or secrets.token_hex(4)

# ─────────────────────────────────────────────
# ENVELOPE  (mirrors internal/transport/envelope.go)
# ─────────────────────────────────────────────
MAGIC = 0x1F


def encode_envelope(
    session_id: str,
    seq: int,
    target_addr: str = "",
    payload: bytes = b"",
    close: bool = False,
) -> bytes:
    sid = session_id.encode()
    addr = target_addr.encode()
    hdr = bytearray()
    hdr.append(MAGIC)
    hdr.append(len(sid))
    hdr.extend(sid)
    hdr.extend(struct.pack(">Q", seq))  # uint64 big-endian
    hdr.append(len(addr))
    hdr.extend(addr)
    hdr.append(1 if close else 0)
    hdr.extend(struct.pack(">I", len(payload)))  # uint32
    hdr.extend(payload)
    return bytes(hdr)


def decode_envelope(data: bytes, offset: int = 0) -> Tuple[dict, int]:
    """Decode one envelope starting at offset. Returns (env_dict, new_offset)."""
    start = offset
    if len(data) < offset + 1:
        raise EOFError
    if data[offset] != MAGIC:
        raise ValueError(f"Bad magic byte 0x{data[offset]:02X}")
    offset += 1

    sid_len = data[offset]
    offset += 1
    session_id = data[offset : offset + sid_len].decode()
    offset += sid_len

    seq = struct.unpack_from(">Q", data, offset)[0]
    offset += 8

    addr_len = data[offset]
    offset += 1
    target_addr = data[offset : offset + addr_len].decode()
    offset += addr_len

    close = bool(data[offset])
    offset += 1

    pay_len = struct.unpack_from(">I", data, offset)[0]
    offset += 4
    payload = data[offset : offset + pay_len]
    offset += pay_len

    return {
        "session_id": session_id,
        "seq": seq,
        "target_addr": target_addr,
        "close": close,
        "payload": payload,
    }, offset


def decode_all_envelopes(data: bytes):
    envs = []
    offset = 0
    while offset < len(data):
        try:
            env, offset = decode_envelope(data, offset)
            envs.append(env)
        except (EOFError, struct.error):
            break
        except Exception as e:
            log.warning("Envelope decode error: %s", e)
            break
    return envs


# ─────────────────────────────────────────────
# DOMAIN FRONTING HTTP ADAPTER
# Connects to DOMAIN_FRONT_IP but presents SNI=FRONT_SNI and Host=API_HOST.
# This mirrors the Go httpclient.NewCustomClient() behavior.
# ─────────────────────────────────────────────
_df = _cfg.get("domain_front", {})
DOMAIN_FRONT_IP = _df.get("target_ip", "216.239.38.120")
FRONT_SNI = _df.get("sni", "google.com")
API_HOST = _df.get("api_host", "www.googleapis.com")


class DomainFrontAdapter(HTTPAdapter):
    """
    For every request to www.googleapis.com:
      - TCP connects to DOMAIN_FRONT_IP:443
      - TLS SNI = google.com  (this passes through censorship)
      - HTTP Host header = www.googleapis.com  (Google routes internally)
    """

    def send(
        self, request, stream=False, timeout=None, verify=True, cert=None, proxies=None
    ):
        # Patch the URL to target the front IP so urllib3 dials the right host
        from urllib.parse import urlparse, urlunparse

        parsed = urlparse(request.url)
        # Replace hostname in URL with the front IP for connection purposes
        # but keep Host header as API_HOST
        request.headers["Host"] = API_HOST
        # Rewrite URL to hit front IP directly
        front_url = urlunparse(parsed._replace(netloc=f"{DOMAIN_FRONT_IP}:{443}"))
        request.url = front_url
        return super().send(
            request,
            stream=stream,
            timeout=timeout,
            verify=False,
            cert=cert,
            proxies=proxies,
        )

    def init_poolmanager(self, num_pools=10, maxsize=16, block=False, **kwargs):
        ctx = create_urllib3_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        self.poolmanager = PoolManager(
            num_pools=num_pools,
            maxsize=maxsize,  # enough connections for parallel workers
            block=False,
            ssl_context=ctx,
            server_hostname=FRONT_SNI,  # SNI = "google.com"
            **kwargs,
        )


def _build_fronted_session() -> requests.Session:
    """Build a requests.Session that domain-fronts all https:// calls."""
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    sess = requests.Session()
    adapter = DomainFrontAdapter()
    sess.mount("https://", adapter)
    return sess


# ─────────────────────────────────────────────
# GOOGLE DRIVE BACKEND
# ─────────────────────────────────────────────
class GoogleDrive:
    TOKEN_URI = "https://www.googleapis.com/oauth2/v4/token"
    UPLOAD_URI = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
    FILES_URI = "https://www.googleapis.com/drive/v3/files"

    def __init__(self, creds_path: str, token_cache_path: str, folder_id: str):
        self.folder_id = folder_id
        self.token_cache_path = token_cache_path
        self._creds_path = creds_path
        self._access_token = ""
        self._token_expiry = 0.0
        self._client_id = ""
        self._client_secret = ""
        self._refresh_token = ""
        self._lock = threading.Lock()
        # name → file_id cache
        self._file_ids: Dict[str, str] = {}
        self._file_ids_lock = threading.Lock()
        self._session = _build_fronted_session()

    def login(self):
        with open(self._creds_path) as f:
            creds = json.load(f)
        inst = creds["installed"]
        self._client_id = inst["client_id"]
        self._client_secret = inst["client_secret"]

        # Try cached refresh token
        if os.path.exists(self.token_cache_path):
            with open(self.token_cache_path) as f:
                cache = json.load(f)
            rt = cache.get("refresh_token", "")
            if rt:
                self._refresh_token = rt
                self._do_refresh()
                log.info("Google Drive: authenticated via cached refresh token")
                return

        raise RuntimeError(
            "No refresh token cached. Please run the Go client once to authenticate, "
            "then re-run this script."
        )

    def _do_refresh(self):
        resp = self._session.post(
            self.TOKEN_URI,
            data={
                "grant_type": "refresh_token",
                "refresh_token": self._refresh_token,
                "client_id": self._client_id,
                "client_secret": self._client_secret,
            },
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        self._access_token = data["access_token"]
        self._token_expiry = time.time() + data.get("expires_in", 3600) - 60
        if "refresh_token" in data:
            self._refresh_token = data["refresh_token"]
        log.debug(
            "Google Drive: token refreshed, expires in ~%ds",
            int(self._token_expiry - time.time()),
        )

    def _token(self) -> str:
        with self._lock:
            if time.time() >= self._token_expiry:
                self._do_refresh()
            return self._access_token

    def upload(self, filename: str, data: bytes):
        # Build multipart body manually (no external dependency needed)
        boundary = b"loole_boundary_" + secrets.token_hex(8).encode()
        meta = json.dumps(
            {
                "name": filename,
                "parents": [self.folder_id],
            }
        ).encode()

        body = (
            b"--" + boundary + b"\r\n"
            b"Content-Type: application/json; charset=UTF-8\r\n\r\n" + meta + b"\r\n"
            b"--" + boundary + b"\r\n"
            b"Content-Type: application/octet-stream\r\n\r\n"
            + data
            + b"\r\n--"
            + boundary
            + b"--\r\n"
        )
        headers = {
            "Authorization": "Bearer " + self._token(),
            "Content-Type": "multipart/related; boundary=" + boundary.decode(),
        }
        resp = self._session.post(self.UPLOAD_URI, data=body, headers=headers)
        if resp.status_code not in (200, 201):
            log.warning("Upload failed %d: %s", resp.status_code, resp.text[:200])
            return
        log.debug("Uploaded %s (%d bytes)", filename, len(data))

    def list_prefix(self, prefix: str) -> list:
        q = f"name contains '{prefix}' and '{self.folder_id}' in parents and trashed = false"
        resp = self._session.get(
            self.FILES_URI,
            params={
                "q": q,
                "fields": "files(id,name)",
            },
            headers={"Authorization": "Bearer " + self._token()},
        )
        if resp.status_code != 200:
            log.warning("List failed %d: %s", resp.status_code, resp.text[:200])
            return []
        files = resp.json().get("files", [])
        # Cache name→id
        with self._file_ids_lock:
            if len(self._file_ids) > 2000:
                self._file_ids = {}
            for f in files:
                self._file_ids[f["name"]] = f["id"]
        return [f["name"] for f in files if f["name"].startswith(prefix)]

    def _get_file_id(self, name: str) -> Optional[str]:
        with self._file_ids_lock:
            return self._file_ids.get(name)

    def download(self, filename: str) -> Optional[bytes]:
        fid = self._get_file_id(filename)
        if not fid:
            log.warning("No file ID cached for %s", filename)
            return None
        resp = self._session.get(
            f"https://www.googleapis.com/drive/v3/files/{fid}?alt=media",
            headers={"Authorization": "Bearer " + self._token()},
        )
        if resp.status_code != 200:
            log.warning("Download failed %d for %s", resp.status_code, filename)
            return None
        return resp.content

    def delete(self, filename: str):
        fid = self._get_file_id(filename)
        if not fid:
            return
        resp = self._session.delete(
            f"https://www.googleapis.com/drive/v3/files/{fid}",
            headers={"Authorization": "Bearer " + self._token()},
        )
        if resp.status_code not in (204, 200):
            log.warning("Delete failed %d for %s", resp.status_code, filename)
        else:
            with self._file_ids_lock:
                self._file_ids.pop(filename, None)
            log.debug("Deleted %s", filename)


# ─────────────────────────────────────────────
# SESSION
# ─────────────────────────────────────────────
class Session:
    def __init__(self, session_id: str, target_addr: str):
        self.id = session_id
        self.target_addr = target_addr
        self.tx_buf = bytearray()
        self.tx_seq = 0
        self.rx_seq = 0
        self.rx_queue: Dict[int, dict] = {}  # seq → env
        self.rx_ready = threading.Event()  # set when data is available
        self.rx_data = bytearray()  # reassembled inbound bytes
        self.rx_lock = threading.Lock()
        self.tx_lock = threading.Lock()
        self.closed = False
        self.last_activity = time.time()


# ─────────────────────────────────────────────
# ENGINE  (multiplexer over Google Drive)
# ─────────────────────────────────────────────
class Engine:
    def __init__(self, drive: GoogleDrive, client_id: str):
        self.drive = drive
        self.client_id = client_id
        self.sessions: Dict[str, Session] = {}
        self.sessions_lock = threading.Lock()
        self.processed: set = set()
        self.processed_lock = threading.Lock()
        self._stop = threading.Event()
        # Signals the flush loop to run immediately (set when TX data arrives)
        self._flush_now = threading.Event()
        # Signals the poll loop to run immediately (set after a flush completes)
        self._poll_now = threading.Event()
        self._executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="drive")

    def add_session(self, s: Session):
        with self.sessions_lock:
            self.sessions[s.id] = s
        log.info("Session added: %s → %s", s.id, s.target_addr)
        # Wake flush loop immediately so seq=0 gets uploaded without waiting
        self._flush_now.set()

    def remove_session(self, session_id: str):
        with self.sessions_lock:
            self.sessions.pop(session_id, None)

    def get_session(self, session_id: str) -> Optional[Session]:
        with self.sessions_lock:
            return self.sessions.get(session_id)

    # ── TX: flush all sessions into one mux file ──
    def _flush(self):
        with self.sessions_lock:
            active = list(self.sessions.values())

        chunks = bytearray()
        closed_ids = []

        for s in active:
            with s.tx_lock:
                # On seq=0 always send (even nil payload) to open session on server
                if s.tx_seq > 0 and not s.tx_buf and not s.closed:
                    continue
                payload = bytes(s.tx_buf)
                s.tx_buf = bytearray()
                seq = s.tx_seq
                close = s.closed
                addr = s.target_addr if seq == 0 else ""
                s.tx_seq += 1
                s.last_activity = time.time()

            env_bytes = encode_envelope(s.id, seq, addr, payload, close)
            chunks.extend(env_bytes)

            if close:
                closed_ids.append(s.id)

        if chunks:
            ts = time.time_ns()
            fname = f"req-{self.client_id}-mux-{ts}.bin"
            self.drive.upload(fname, bytes(chunks))

        for sid in closed_ids:
            self.remove_session(sid)

    # ── RX: poll for response files ──
    def _poll(self) -> int:
        """Poll once. Returns number of files processed."""
        prefix = f"res-{self.client_id}-mux-"
        files = self.drive.list_prefix(prefix)

        new_files = []
        for fname in files:
            with self.processed_lock:
                if fname in self.processed:
                    continue
                self.processed.add(fname)
            new_files.append(fname)

        if not new_files:
            return 0

        def _process(fname):
            data = self.drive.download(fname)
            if data is None:
                with self.processed_lock:
                    self.processed.discard(fname)
                return
            envs = decode_all_envelopes(data)
            for env in envs:
                s = self.get_session(env["session_id"])
                if s is None:
                    continue
                self._deliver(s, env)
            self.drive.delete(fname)

        # Download + deliver all files in parallel
        futures = [self._executor.submit(_process, f) for f in new_files]
        for fut in as_completed(futures):
            try:
                fut.result()
            except Exception as e:
                log.warning("Poll process error: %s", e)

        # Prevent processed set from growing unbounded
        with self.processed_lock:
            if len(self.processed) > 5000:
                self.processed = set()

        return len(new_files)

    def _deliver(self, s: Session, env: dict):
        # In-order delivery using rx_queue
        with s.rx_lock:
            if env["seq"] == s.rx_seq:
                if env["payload"]:
                    s.rx_data.extend(env["payload"])
                s.rx_seq += 1
                s.rx_ready.set()

                # Drain queued out-of-order packets
                while s.rx_seq in s.rx_queue:
                    e2 = s.rx_queue.pop(s.rx_seq)
                    if e2["payload"]:
                        s.rx_data.extend(e2["payload"])
                    s.rx_seq += 1

                if env["close"]:
                    s.closed = True
                    s.rx_ready.set()
            elif env["seq"] > s.rx_seq:
                s.rx_queue[env["seq"]] = env
            # else: duplicate, ignore

    def _flush_loop(self):
        while not self._stop.is_set():
            # Wait for either the regular tick OR an immediate-flush signal
            self._flush_now.wait(timeout=FLUSH_INTERVAL)
            self._flush_now.clear()
            try:
                with self.sessions_lock:
                    active = len(self.sessions)
                if active > 0:
                    self._flush()
                    # After flushing, wake the poll loop so it checks for replies
                    self._poll_now.set()
            except Exception as e:
                log.warning("Flush error: %s", e)

    def _poll_loop(self):
        while not self._stop.is_set():
            # Wait for either the regular tick OR a wake signal from flush
            self._poll_now.wait(timeout=POLL_INTERVAL)
            self._poll_now.clear()
            try:
                with self.sessions_lock:
                    active = len(self.sessions)
                if active == 0:
                    continue
                found = self._poll()
                # Adaptive: if we got data, poll again after a tiny pause
                while found > 0 and not self._stop.is_set():
                    time.sleep(0.1)
                    found = self._poll()
            except Exception as e:
                log.warning("Poll error: %s", e)

    def start(self):
        threading.Thread(target=self._flush_loop, daemon=True, name="flush").start()
        threading.Thread(target=self._poll_loop, daemon=True, name="poll").start()
        log.info("Engine started (client_id=%s)", self.client_id)

    def stop(self):
        self._stop.set()
        self._flush_now.set()
        self._poll_now.set()
        self._executor.shutdown(wait=False)


# ─────────────────────────────────────────────
# VIRTUAL CONN  (used by SOCKS5 handler)
# ─────────────────────────────────────────────
class VirtualConn:
    """Wraps a Session to look like a socket."""

    def __init__(self, session: Session, engine: Engine):
        self.session = session
        self.engine = engine
        self._closed = False

    def send(self, data: bytes) -> int:
        with self.session.tx_lock:
            self.session.tx_buf.extend(data)
            self.session.last_activity = time.time()
        # Wake the flush loop immediately instead of waiting for the next tick
        self.engine._flush_now.set()
        return len(data)

    def recv(self, size: int, timeout: float = 30.0) -> bytes:
        deadline = time.time() + timeout
        while True:
            with self.session.rx_lock:
                if self.session.rx_data:
                    chunk = bytes(self.session.rx_data[:size])
                    self.session.rx_data = self.session.rx_data[size:]
                    if not self.session.rx_data:
                        self.session.rx_ready.clear()
                    return chunk
                if self.session.closed:
                    return b""
            remaining = deadline - time.time()
            if remaining <= 0:
                return b""
            self.session.rx_ready.wait(min(remaining, 0.1))

    def close(self):
        if not self._closed:
            self._closed = True
            with self.session.tx_lock:
                self.session.closed = True


# ─────────────────────────────────────────────
# SOCKS5 SERVER
# ─────────────────────────────────────────────
SOCKS5_VERSION = 5
NO_AUTH = 0
CMD_CONNECT = 1
ATYP_IPV4 = 1
ATYP_DOMAIN = 3
ATYP_IPV6 = 4


def socks5_handshake(sock: socket.socket) -> bool:
    """Negotiate no-auth SOCKS5. Returns True on success."""
    header = _recv_exact(sock, 2)
    if not header or header[0] != SOCKS5_VERSION:
        return False
    n_methods = header[1]
    methods = _recv_exact(sock, n_methods)
    if NO_AUTH not in methods:
        sock.sendall(bytes([SOCKS5_VERSION, 0xFF]))  # no acceptable method
        return False
    sock.sendall(bytes([SOCKS5_VERSION, NO_AUTH]))
    return True


def socks5_read_request(sock: socket.socket) -> Optional[str]:
    """Read CONNECT request. Returns 'host:port' or None."""
    header = _recv_exact(sock, 4)
    if not header or header[0] != SOCKS5_VERSION or header[2] != 0x00:
        return None
    cmd = header[1]
    if cmd != CMD_CONNECT:
        sock.sendall(bytes([SOCKS5_VERSION, 0x07, 0x00, ATYP_IPV4, 0, 0, 0, 0, 0, 0]))
        return None
    atyp = header[3]
    if atyp == ATYP_IPV4:
        addr_bytes = _recv_exact(sock, 4)
        host = socket.inet_ntoa(addr_bytes)
    elif atyp == ATYP_DOMAIN:
        dlen = _recv_exact(sock, 1)[0]
        host = _recv_exact(sock, dlen).decode()
    elif atyp == ATYP_IPV6:
        addr_bytes = _recv_exact(sock, 16)
        host = socket.inet_ntop(socket.AF_INET6, addr_bytes)
    else:
        return None
    port_bytes = _recv_exact(sock, 2)
    port = struct.unpack(">H", port_bytes)[0]
    return f"{host}:{port}"


def socks5_send_success(sock: socket.socket):
    # Reply: VER=5, REP=0 (success), RSV=0, ATYP=1(IPv4), BND.ADDR=0.0.0.0, BND.PORT=0
    sock.sendall(bytes([SOCKS5_VERSION, 0x00, 0x00, ATYP_IPV4, 0, 0, 0, 0, 0, 0]))


def _recv_exact(sock: socket.socket, n: int) -> Optional[bytes]:
    buf = b""
    while len(buf) < n:
        try:
            chunk = sock.recv(n - len(buf))
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
    return buf


def handle_client(conn: socket.socket, addr, engine: Engine):
    conn.settimeout(30)
    try:
        if not socks5_handshake(conn):
            return
        target = socks5_read_request(conn)
        if not target:
            return

        log.info("CONNECT %s from %s", target, addr)

        session_id = secrets.token_hex(16)  # 32-char hex
        session = Session(session_id, target)
        engine.add_session(session)

        vconn = VirtualConn(session, engine)

        # Signal server to open TCP connection (seq=0 with empty payload)
        # The flush loop will pick it up

        socks5_send_success(conn)

        # Pipe data in both directions
        conn.settimeout(None)
        t1 = threading.Thread(target=_local_to_remote, args=(conn, vconn), daemon=True)
        t2 = threading.Thread(target=_remote_to_local, args=(vconn, conn), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

    except Exception as e:
        log.debug("Client handler error: %s", e)
    finally:
        try:
            conn.close()
        except Exception:
            pass
        engine.remove_session(session.id if "session" in dir() else "")


def _local_to_remote(src: socket.socket, dst: VirtualConn):
    try:
        while True:
            try:
                data = src.recv(4096)
            except OSError:
                break
            if not data:
                break
            dst.send(data)
    finally:
        dst.close()


def _remote_to_local(src: VirtualConn, dst: socket.socket):
    try:
        while True:
            data = src.recv(4096, timeout=60)
            if not data:
                break
            try:
                dst.sendall(data)
            except OSError:
                break
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except Exception:
            pass


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
def main():
    log.info("Loole Python Client starting...")

    drive = GoogleDrive(CREDENTIALS_JSON, TOKEN_CACHE, FOLDER_ID)
    drive.login()

    engine = Engine(drive, CLIENT_ID)
    engine.start()

    host, port_str = SOCKS_LISTEN.rsplit(":", 1)
    port = int(port_str)

    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind((host, port))
    server_sock.listen(128)
    log.info("SOCKS5 listening on %s:%d (client_id=%s)", host, port, CLIENT_ID)
    log.info("Test: curl --proxy socks5h://127.0.0.1:%d https://httpbin.org/ip", port)

    try:
        while True:
            try:
                conn, addr = server_sock.accept()
            except KeyboardInterrupt:
                break
            t = threading.Thread(
                target=handle_client, args=(conn, addr, engine), daemon=True
            )
            t.start()
    finally:
        server_sock.close()
        engine.stop()
        log.info("Loole Python Client stopped.")


if __name__ == "__main__":
    main()
