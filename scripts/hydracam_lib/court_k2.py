"""K2 Court Cloud single-device-record enrollment & C1 1.29 contract helpers.

Aligned with:
- C0/C1 1.29 contracts (`services/court-cloud` & `android/app/src/court/`):
  - `GET /health` (`contractVersion` vs `1.29` skew check)
  - `GET /api/courts/:slug` (canonical K2 court UUID + valid camera slots)
  - `GET /internal/v1/devices` (list canonical device records)
  - `POST /internal/v1/devices` (create or re-enroll single device record by `deviceId`)
  - `POST /internal/v1/devices/:id/assign` (move court/slot without rotating secret)
  - `GET /internal/v1/aliases/:source/:legacyId` & `POST /internal/v1/aliases`
  - `POST /device/v1/token` (verify device credential without following redirects)
- `CourtEnrollReceiver` (`com.amaia23.hydracam.court.ENROLL` / `.CLEAR`)
"""

from __future__ import annotations

import json
import os
import re
import shlex
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Sequence

from hydracam_lib.adb import list_devices
from hydracam_lib.proc import CommandResult, run

C1_CONTRACT_VERSION = "1.29"
DEFAULT_K2_URL = "https://app.kvisor.com"
DEFAULT_COURT_PACKAGE = "com.amaia23.hydracam.court"
ENROLL_RECEIVER = "com.amaia23.hydracam.court.CourtEnrollReceiver"
ENROLL_ACTION = "com.amaia23.hydracam.court.ENROLL"
CLEAR_ACTION = "com.amaia23.hydracam.court.CLEAR"
COURT_ACTIVITY = "com.amaia23.hydracam.court.CourtActivity"
DEFAULT_CREDS_FILE = Path.home() / ".config" / "hydracam" / "court-devices.json"

CONTRACT_VERSION_RE = re.compile(r"^\d+(?:\.\d+)+$")
COURT_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "[::1]", "::1"})


class K2Error(RuntimeError):
    """Error raised when K2 Court Cloud rejects or fails a request."""

    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        code: str | None = None,
        detail: Any = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.detail = detail


class DeviceIdentityConflictError(K2Error):
    """Raised when local cached deviceId conflicts with K2's alias registry."""


def contract_at_least(version: str | None, minimum: str) -> bool:
    """Compare dotted contract versions (`1.29.0` >= `1.29`, `1.10.1` < `1.11`)."""
    if not version or not CONTRACT_VERSION_RE.match(version):
        return False
    if not CONTRACT_VERSION_RE.match(minimum):
        return False
    a = [int(p) for p in version.split(".")]
    b = [int(p) for p in minimum.split(".")]
    for i in range(max(len(a), len(b))):
        diff = (a[i] if i < len(a) else 0) - (b[i] if i < len(b) else 0)
        if diff != 0:
            return diff > 0
    return True


def contract_skew(
    version: str | None,
    expected: str = C1_CONTRACT_VERSION,
) -> str:
    """Return 'same', 'older', 'newer', or 'unknown' against `expected`."""
    if not version or not CONTRACT_VERSION_RE.match(version):
        return "unknown"
    if not contract_at_least(version, expected):
        return "older"
    return "same" if contract_at_least(expected, version) else "newer"


def is_allowed_k2_url(url: str) -> bool:
    """Match C1 `CourtUrls.isAllowed`: https:// anywhere, http:// only on loopback."""
    parsed = urllib.parse.urlsplit(url.strip())
    scheme = parsed.scheme.lower()
    host = (parsed.hostname or "").lower()
    if not host:
        return False
    if scheme == "https":
        return True
    if scheme == "http":
        return host in LOOPBACK_HOSTS
    return False


def normalize_k2_url(url: str) -> str:
    return url.strip().rstrip("/")


def validate_k2_url(url: str) -> str:
    """Validate and normalize K2 URL, rejecting the bare landing page host."""
    cleaned = normalize_k2_url(url)
    if not is_allowed_k2_url(cleaned):
        raise ValueError(
            "k2Url must be https://host (http:// is allowed only for loopback)"
        )
    host = (urllib.parse.urlsplit(cleaned).hostname or "").lower()
    if host == "kvisor.com":
        raise ValueError(
            "kvisor.com is the landing page and redirects /api; use https://app.kvisor.com"
        )
    return cleaned


def is_safe_court_id(value: str) -> bool:
    """Match Kotlin `CourtIds.isSafe`."""
    return bool(COURT_ID_RE.match(value))


@dataclass(frozen=True)
class CourtEnrollment:
    """Canonical K1<->K2 device enrollment payload (`CourtAuth.kt`)."""

    k2_url: str
    device_id: str
    secret: str
    court_id: str
    slot: str
    mount_rev: int = 1
    court_slug: str | None = None
    name: str | None = None

    def __repr__(self) -> str:
        return (
            f"CourtEnrollment(k2_url={self.k2_url!r}, device_id={self.device_id!r}, "
            f"secret='<redacted>', court_id={self.court_id!r}, slot={self.slot!r}, "
            f"mount_rev={self.mount_rev!r})"
        )

    def __str__(self) -> str:
        return self.__repr__()

    def validate(self) -> list[str]:
        problems: list[str] = []
        try:
            validate_k2_url(self.k2_url)
        except ValueError as exc:
            problems.append(str(exc))
        if not self.device_id.strip():
            problems.append("deviceId is required")
        if not self.secret.strip():
            problems.append("secret is required")
        if not self.court_id.strip() or not is_safe_court_id(self.court_id.strip()):
            problems.append("courtId must be a safe non-empty K2 court id")
        if not self.slot.strip() or not is_safe_court_id(self.slot.strip()):
            problems.append("slot must be a safe non-empty slot name")
        if (
            isinstance(self.mount_rev, bool)
            or not isinstance(self.mount_rev, int)
            or self.mount_rev < 0
        ):
            problems.append("mountRev must be a non-negative integer")
        return problems

    def raise_for_invalid(self) -> None:
        problems = self.validate()
        if problems:
            raise ValueError("; ".join(problems))

    def to_dict(self, *, include_secret: bool = False) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "k2Url": normalize_k2_url(self.k2_url),
            "deviceId": self.device_id,
            "courtId": self.court_id,
            "slot": self.slot,
            "mountRev": self.mount_rev,
        }
        if self.court_slug is not None:
            payload["courtSlug"] = self.court_slug
        if self.name is not None:
            payload["name"] = self.name
        if include_secret:
            payload["secret"] = self.secret
        return payload

    def build_enroll_broadcast_command(
        self,
        package_name: str = DEFAULT_COURT_PACKAGE,
    ) -> str:
        """Build the `am broadcast` command to feed to root `su` over stdin."""
        self.raise_for_invalid()
        component = f"{package_name}/{ENROLL_RECEIVER}"
        args = [
            "am",
            "broadcast",
            "-n",
            component,
            "-a",
            ENROLL_ACTION,
            "--es",
            "k2Url",
            normalize_k2_url(self.k2_url),
            "--es",
            "deviceId",
            self.device_id.strip(),
            "--es",
            "secret",
            self.secret,
            "--es",
            "courtId",
            self.court_id.strip(),
            "--es",
            "slot",
            self.slot.strip(),
            "--ei",
            "mountRev",
            str(self.mount_rev),
        ]
        return " ".join(shlex.quote(part) for part in args)

    @staticmethod
    def build_clear_broadcast_command(
        package_name: str = DEFAULT_COURT_PACKAGE,
    ) -> str:
        component = f"{package_name}/{ENROLL_RECEIVER}"
        return " ".join(
            shlex.quote(part)
            for part in ("am", "broadcast", "-n", component, "-a", CLEAR_ACTION)
        )


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001, D102
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirectHandler())


def default_http_transport(
    method: str,
    url: str,
    *,
    headers: dict[str, str],
    body: bytes | None,
    timeout: float,
) -> tuple[int, bytes]:
    req = urllib.request.Request(
        url,
        data=body,
        method=method.upper(),
        headers=headers,
    )
    try:
        # Never follow redirects on secret-bearing K2 endpoints (matches CourtAuth.kt).
        with _NO_REDIRECT_OPENER.open(req, timeout=timeout) as resp:
            return int(resp.status), resp.read()
    except urllib.error.HTTPError as err:
        try:
            try:
                err_body = err.read()
            except OSError:
                err_body = b""
            return int(err.code), err_body
        finally:
            err.close()
    except urllib.error.URLError as err:
        raise K2Error(f"K2 request failed for {url}: {err.reason}") from err


HttpTransport = Callable[..., tuple[int, bytes]]


class K2CourtCloudClient:
    """HTTP client for K2 Court Cloud C0/C1 device registration and lookup."""

    def __init__(
        self,
        base_url: str,
        *,
        admin_token: str | None = None,
        timeout: float = 15.0,
        transport: HttpTransport | None = None,
    ) -> None:
        self.base_url = validate_k2_url(base_url)
        self.admin_token = admin_token
        self.timeout = timeout
        self._transport = transport or default_http_transport

    def _request_json(
        self,
        method: str,
        path: str,
        *,
        payload: dict[str, Any] | None = None,
        require_admin: bool = False,
        allow_404: bool = False,
    ) -> tuple[int, Any]:
        headers = {"Accept": "application/json"}
        body: bytes | None = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode("utf-8")
        if require_admin:
            if not self.admin_token:
                raise K2Error(
                    "K2 admin token is required (set COURT_CLOUD_ADMIN_TOKEN)",
                    status=401,
                    code="missing-admin-token",
                )
            headers["Authorization"] = f"Bearer {self.admin_token}"

        url = f"{self.base_url}{path}"
        status, raw = self._transport(
            method,
            url,
            headers=headers,
            body=body,
            timeout=self.timeout,
        )
        decoded: Any = {}
        if raw:
            try:
                decoded = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                decoded = {"raw": raw.decode("utf-8", errors="replace")}

        if allow_404 and status == 404:
            return status, None
        if status < 200 or status >= 300:
            code = decoded.get("error") if isinstance(decoded, dict) else None
            msg = f"K2 {method} {path} returned HTTP {status}"
            if code:
                msg = f"{msg} ({code})"
            raise K2Error(msg, status=status, code=code, detail=decoded)
        return status, decoded

    def health(self) -> dict[str, Any]:
        _, data = self._request_json("GET", "/health")
        if not isinstance(data, dict):
            raise K2Error("K2 /health did not return a JSON object")
        version = data.get("contractVersion")
        return {
            **data,
            "contractSkew": contract_skew(
                version if isinstance(version, str) else None
            ),
        }

    def get_court(self, court_slug: str) -> dict[str, Any]:
        quoted = urllib.parse.quote(court_slug, safe="")
        _, data = self._request_json("GET", f"/api/courts/{quoted}")
        if not isinstance(data, dict) or not data.get("id"):
            raise K2Error(f"K2 court {court_slug!r} returned invalid payload")
        return data

    def list_devices(self) -> list[dict[str, Any]]:
        _, data = self._request_json("GET", "/internal/v1/devices", require_admin=True)
        if not isinstance(data, dict) or not isinstance(data.get("devices"), list):
            raise K2Error("K2 /internal/v1/devices returned invalid payload")
        return list(data["devices"])

    def resolve_alias(self, source: str, legacy_id: str) -> dict[str, Any] | None:
        src = urllib.parse.quote(source, safe="")
        lid = urllib.parse.quote(legacy_id, safe="")
        _, data = self._request_json(
            "GET",
            f"/internal/v1/aliases/{src}/{lid}",
            require_admin=True,
            allow_404=True,
        )
        return data if isinstance(data, dict) else None

    def upsert_aliases(self, aliases: Sequence[dict[str, Any]]) -> dict[str, Any]:
        if not aliases:
            return {"created": 0, "updated": 0, "unchanged": 0}
        _, data = self._request_json(
            "POST",
            "/internal/v1/aliases",
            payload={"aliases": list(aliases)},
            require_admin=True,
        )
        return data if isinstance(data, dict) else {}

    def enroll_device(
        self,
        court_slug: str,
        slot: str,
        *,
        device_id: str | None = None,
        name: str | None = None,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {"courtSlug": court_slug, "slot": slot}
        if device_id:
            body["deviceId"] = device_id
        if name is not None:
            body["name"] = name
        _, data = self._request_json(
            "POST",
            "/internal/v1/devices",
            payload=body,
            require_admin=True,
        )
        if not isinstance(data, dict) or not data.get("deviceId") or not data.get("secret"):
            raise K2Error("K2 POST /internal/v1/devices returned incomplete credentials")
        return data

    def assign_device(self, device_id: str, court_slug: str, slot: str) -> dict[str, Any]:
        quoted = urllib.parse.quote(device_id, safe="")
        _, data = self._request_json(
            "POST",
            f"/internal/v1/devices/{quoted}/assign",
            payload={"courtSlug": court_slug, "slot": slot},
            require_admin=True,
        )
        if not isinstance(data, dict) or not data.get("id"):
            raise K2Error("K2 assign returned invalid device payload")
        return data

    def verify_device_token(self, device_id: str, secret: str) -> bool:
        try:
            _, data = self._request_json(
                "POST",
                "/device/v1/token",
                payload={"deviceId": device_id, "secret": secret},
            )
        except K2Error as exc:
            if exc.status in (401, 403):
                return False
            raise
        return isinstance(data, dict) and bool(data.get("accessToken"))


@dataclass(frozen=True)
class EnrollmentOutcome:
    """Result of resolving and enrolling a single K2 device record."""

    enrollment: CourtEnrollment
    action: str  # created | reused | reassigned | re-enrolled
    court: dict[str, Any]


def resolve_device_id(
    *,
    explicit_device_id: str | None = None,
    cached_device_id: str | None = None,
    serial: str | None = None,
    host: str | None = None,
    client: K2CourtCloudClient | None = None,
) -> str | None:
    """Resolve the canonical K2 deviceId for a phone, detecting split identity."""
    if explicit_device_id:
        return explicit_device_id.strip()

    serial_alias = (
        client.resolve_alias("adb-serial", serial) if client and serial else None
    )
    host_alias = (
        client.resolve_alias("fleet-host", host) if client and host else None
    )

    alias_serial_id = serial_alias.get("deviceId") if serial_alias else None
    alias_host_id = host_alias.get("deviceId") if host_alias else None

    if cached_device_id and alias_serial_id and cached_device_id != alias_serial_id:
        raise DeviceIdentityConflictError(
            f"Local cached deviceId {cached_device_id} conflicts with K2 adb-serial alias "
            f"{alias_serial_id} for {serial}; pass --device-id to choose explicitly",
            code="identity-conflict",
        )
    if alias_serial_id and alias_host_id and alias_serial_id != alias_host_id:
        raise DeviceIdentityConflictError(
            f"K2 adb-serial alias ({alias_serial_id}) conflicts with fleet-host alias "
            f"({alias_host_id}); pass --device-id to choose explicitly",
            code="identity-conflict",
        )
    return cached_device_id or alias_serial_id or alias_host_id


def enroll_single_k2_device(
    *,
    client: K2CourtCloudClient,
    court_slug: str,
    slot: str,
    serial: str | None = None,
    host: str | None = None,
    name: str | None = None,
    device_id: str | None = None,
    cached_device_id: str | None = None,
    cached_secret: str | None = None,
    rotate_secret: bool = False,
    sync_aliases: bool = True,
) -> EnrollmentOutcome:
    """Create, reuse, or update the single K2 Court Cloud record for a phone."""
    court = client.get_court(court_slug)
    cameras = court.get("cameras") or []
    valid_slots = {c.get("slot") for c in cameras if isinstance(c, dict)}
    if slot not in valid_slots:
        raise K2Error(
            f"unknown-slot: slot {slot!r} is not in court {court_slug!r} ({sorted(s for s in valid_slots if s)})",
            status=400,
            code="unknown-slot",
        )

    resolved_id = resolve_device_id(
        explicit_device_id=device_id,
        cached_device_id=cached_device_id,
        serial=serial,
        host=host,
        client=client,
    )

    existing: dict[str, Any] | None = None
    if resolved_id:
        existing = next(
            (d for d in client.list_devices() if d.get("id") == resolved_id),
            None,
        )

    secret: str
    mount_rev: int
    action: str

    if (
        existing
        and not existing.get("revoked")
        and cached_secret
        and not rotate_secret
        and client.verify_device_token(resolved_id or "", cached_secret)
    ):
        secret = cached_secret
        if existing.get("courtId") == court["id"] and existing.get("slot") == slot:
            mount_rev = int(existing.get("mountRev", 1))
            action = "reused"
        else:
            assigned = client.assign_device(resolved_id or "", court_slug, slot)
            mount_rev = int(assigned.get("mountRev", int(existing.get("mountRev", 1)) + 1))
            action = "reassigned"
    else:
        enrolled = client.enroll_device(
            court_slug,
            slot,
            device_id=resolved_id,
            name=name or host,
        )
        resolved_id = str(enrolled["deviceId"])
        secret = str(enrolled["secret"])
        mount_rev = int(enrolled.get("mountRev", 1))
        action = "re-enrolled" if existing or resolved_id == device_id else "created"
        if not client.verify_device_token(resolved_id, secret):
            raise K2Error(
                f"K2 rejected newly issued credential for device {resolved_id}",
                status=401,
                code="token-verify-failed",
            )

    if sync_aliases:
        alias_entries: list[dict[str, Any]] = []
        if serial:
            alias_entries.append(
                {
                    "source": "adb-serial",
                    "legacyId": serial,
                    "deviceId": resolved_id,
                    "note": "hydracam court_k2_enroll",
                }
            )
        if host:
            alias_entries.append(
                {
                    "source": "fleet-host",
                    "legacyId": host,
                    "deviceId": resolved_id,
                    "note": "hydracam court_k2_enroll",
                }
            )
        if alias_entries:
            client.upsert_aliases(alias_entries)

    enrollment = CourtEnrollment(
        k2_url=client.base_url,
        device_id=resolved_id or "",
        secret=secret,
        court_id=str(court["id"]),
        slot=slot,
        mount_rev=mount_rev,
        court_slug=court_slug,
        name=name or host,
    )
    enrollment.raise_for_invalid()
    return EnrollmentOutcome(enrollment=enrollment, action=action, court=court)


# ---- 0o600 local credentials store ----------------------------------------


def load_creds_store(path: Path) -> list[dict[str, Any]]:
    """Read device credential records from `path` (returns [] if absent)."""
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"Credentials file {path} must contain a JSON array")
    return [dict(item) for item in data if isinstance(item, dict)]


def save_creds_store(path: Path, entries: Sequence[dict[str, Any]]) -> None:
    """Atomically write `entries` to `path` with strict 0o600 permissions."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    tmp = path.with_suffix(path.suffix + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(list(entries), indent=2) + "\n")
    except Exception:
        if tmp.exists():
            tmp.unlink()
        raise
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def find_creds_entry(
    entries: Sequence[dict[str, Any]],
    *,
    serial: str | None = None,
    host: str | None = None,
    device_id: str | None = None,
) -> dict[str, Any] | None:
    """Find a credential entry by deviceId, serial, or host."""
    for entry in entries:
        if device_id and entry.get("deviceId") == device_id:
            return entry
        if serial and entry.get("serial") == serial:
            return entry
        if host and entry.get("host") == host:
            return entry
    return None


def upsert_creds_entry(
    path: Path,
    *,
    enrollment: CourtEnrollment,
    serial: str | None,
    host: str | None = None,
    port: int | None = None,
) -> None:
    """Insert or update the single entry for this deviceId/serial in `path`."""
    entries = load_creds_store(path)
    record: dict[str, Any] = {
        "k2Url": normalize_k2_url(enrollment.k2_url),
        "deviceId": enrollment.device_id,
        "secret": enrollment.secret,
        "courtId": enrollment.court_id,
        "slot": enrollment.slot,
        "mountRev": enrollment.mount_rev,
    }
    if serial:
        record["serial"] = serial
    if host or enrollment.name:
        record["host"] = host or enrollment.name
    if enrollment.court_slug:
        record["courtSlug"] = enrollment.court_slug
    if port is not None:
        record["port"] = port

    replaced = False
    updated: list[dict[str, Any]] = []
    for entry in entries:
        same_id = entry.get("deviceId") == enrollment.device_id
        same_serial = bool(serial and entry.get("serial") == serial)
        if same_id or same_serial:
            if not replaced:
                merged = {**entry, **record}
                updated.append(merged)
                replaced = True
        else:
            updated.append(entry)
    if not replaced:
        updated.append(record)
    save_creds_store(path, updated)


# ---- ADB transport resolution --------------------------------------------


def _raw_adb_rows(
    adb_bin: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> dict[str, str]:
    result = runner([adb_bin, "devices", "-l"], timeout=timeout)
    if result.returncode != 0:
        raise RuntimeError(
            f"adb devices -l failed ({result.returncode}): {result.combined_output}"
        )
    rows: dict[str, str] = {}
    for line in result.stdout.splitlines()[1:]:
        parts = line.strip().split()
        if len(parts) >= 2:
            rows[parts[0]] = parts[1]
    return rows


def _read_remote_serial(
    adb_bin: str,
    endpoint: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> str:
    for prop in ("ro.serialno", "ro.boot.serialno"):
        res = runner([adb_bin, "-s", endpoint, "shell", f"getprop {prop}"], timeout=timeout)
        val = res.stdout.strip()
        if val:
            return val
    return ""


def resolve_adb_endpoint(
    adb_bin: str,
    *,
    serial: str | None = None,
    host: str | None = None,
    port: int | None = None,
    endpoint: str | None = None,
    timeout: int = 15,
    runner: Callable[..., CommandResult] = run,
) -> str:
    """Resolve the active ADB transport for a phone and verify serial identity.

    Resolution order: explicit ``endpoint`` -> USB ``serial`` -> tunnel
    ``127.0.0.1:<port>`` -> Tailscale ``<host>:5555``. Network endpoints are
    cross-checked against ``ro.serialno`` when ``serial`` is known.
    """
    rows = _raw_adb_rows(adb_bin, timeout=timeout, runner=runner)

    if endpoint:
        state = rows.get(endpoint)
        if state != "device":
            raise RuntimeError(
                f"ADB endpoint {endpoint} is {state or 'absent'} (expected 'device')"
            )
        if serial and ":" in endpoint:
            actual = _read_remote_serial(adb_bin, endpoint, timeout=timeout, runner=runner)
            if actual and actual != serial:
                raise RuntimeError(
                    f"ADB endpoint {endpoint} reports serial {actual}, expected {serial}"
                )
        return endpoint

    candidates: list[str] = []
    if serial:
        candidates.append(serial)
    if port is not None:
        candidates.append(f"127.0.0.1:{port}")
    if host:
        candidates.append(f"{host}:5555")

    if not candidates:
        authorized = list_devices(adb_bin, timeout=timeout, runner=runner)
        if len(authorized) == 1:
            return authorized[0].serial
        if not authorized:
            raise RuntimeError("No authorized Android devices found via adb devices -l")
        serials = ", ".join(d.serial for d in authorized)
        raise RuntimeError(
            f"Multiple authorized Android devices found ({serials}); pass --serial or --endpoint"
        )

    bad_states: list[str] = []
    for cand in candidates:
        state = rows.get(cand)
        if state is None:
            continue
        if state != "device":
            bad_states.append(f"{cand}={state}")
            continue
        if serial and ":" in cand:
            actual = _read_remote_serial(adb_bin, cand, timeout=timeout, runner=runner)
            if actual != serial:
                raise RuntimeError(
                    f"ADB endpoint {cand} reports serial {actual or 'unknown'}, expected {serial}"
                )
        return cand

    if bad_states:
        hint = (
            'Tap "Allow" on the phone and tick "Always allow"'
            if any("unauthorized" in s for s in bad_states)
            else "Check USB cable or ADB tunnel"
        )
        raise RuntimeError(
            f"ADB device not ready ({', '.join(bad_states)}); {hint}"
        )
    raise RuntimeError(
        f"Phone not reachable on any ADB transport ({', '.join(candidates)})"
    )
