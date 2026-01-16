#!/usr/bin/env python3
"""Safe, explicit service checks for MACCDC environments.

Reads a JSON config file and checks only the listed services.
Results are written to artifacts/service_checks by default.
"""

import argparse
import json
import os
import random
import socket
import ssl
import struct
import sys
import time
import urllib.request
import smtplib
import poplib
import ftplib

DEFAULT_TIMEOUT = 5
USER_AGENT = "MACCDC-ServiceCheck/1.0"


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def now_ts():
    return time.strftime("%Y%m%d-%H%M%S")


def record_result(results, name, service_type, ok, duration, detail, skipped=False):
    results.append(
        {
            "name": name,
            "type": service_type,
            "ok": ok,
            "skipped": skipped,
            "duration_ms": int(duration * 1000),
            "detail": detail,
        }
    )


def check_tcp(service, timeout):
    host = service["host"]
    port = int(service.get("port", 0))
    if port <= 0:
        return False, "missing port"
    start = time.time()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
        return True, f"connected to {host}:{port}"
    except Exception as exc:
        return False, f"tcp error: {exc}"
    finally:
        _ = time.time() - start


def check_http(service, timeout, scheme):
    host = service["host"]
    port = int(service.get("port", 443 if scheme == "https" else 80))
    path = service.get("path", "/")
    url = service.get("url", f"{scheme}://{host}:{port}{path}")
    expect_status = int(service.get("expect_status", 200))
    expect_statuses = service.get("expect_statuses")
    expect_contains = service.get("expect_contains")
    verify_tls = bool(service.get("tls_verify", True))

    if expect_statuses is None:
        expect_statuses = [expect_status]
    else:
        expect_statuses = [int(x) for x in expect_statuses]

    context = None
    if scheme == "https" and not verify_tls:
        context = ssl._create_unverified_context()

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=context) as resp:
            status = resp.getcode()
            status_ok = status in expect_statuses
            if expect_contains is not None:
                body = resp.read(1024 * 1024).decode("utf-8", errors="replace")
                ok = status_ok and (expect_contains in body)
            else:
                ok = status_ok
            return ok, f"status={status} url={url}"
    except Exception as exc:
        return False, f"http error: {exc}"
    finally:
        _ = time.time() - start


def check_smtp(service, timeout):
    host = service["host"]
    port = int(service.get("port", 25))
    starttls = bool(service.get("starttls", False))
    username = service.get("username")
    password = service.get("password")

    start = time.time()
    try:
        with smtplib.SMTP(host=host, port=port, timeout=timeout) as smtp:
            smtp.ehlo_or_helo_if_needed()
            if starttls:
                smtp.starttls(context=ssl.create_default_context())
                smtp.ehlo()
            if username and password:
                smtp.login(username, password)
            code, _ = smtp.noop()
        ok = code == 250
        return ok, f"smtp noop code={code}"
    except Exception as exc:
        return False, f"smtp error: {exc}"
    finally:
        _ = time.time() - start


def check_pop3(service, timeout):
    host = service["host"]
    port = int(service.get("port", 110))
    use_tls = bool(service.get("tls", False))
    username = service.get("username")
    password = service.get("password")

    start = time.time()
    try:
        if use_tls:
            pop = poplib.POP3_SSL(host, port, timeout=timeout)
        else:
            pop = poplib.POP3(host, port, timeout=timeout)
        with pop:
            if username and password:
                pop.user(username)
                pop.pass_(password)
            pop.stat()
        return True, "pop3 stat ok"
    except Exception as exc:
        return False, f"pop3 error: {exc}"
    finally:
        _ = time.time() - start


def check_ftp(service, timeout):
    host = service["host"]
    port = int(service.get("port", 21))
    use_tls = bool(service.get("tls", False))
    username = service.get("username")
    password = service.get("password")

    start = time.time()
    try:
        if use_tls:
            ftp = ftplib.FTP_TLS()
            ftp.connect(host, port, timeout=timeout)
            if username and password:
                ftp.login(username, password)
                ftp.prot_p()
            else:
                ftp.login()
        else:
            ftp = ftplib.FTP()
            ftp.connect(host, port, timeout=timeout)
            if username and password:
                ftp.login(username, password)
            else:
                ftp.login()
        ftp.pwd()
        ftp.quit()
        return True, "ftp pwd ok"
    except Exception as exc:
        return False, f"ftp error: {exc}"
    finally:
        _ = time.time() - start


def build_dns_query(name):
    tid = random.randint(0, 65535)
    flags = 0x0100
    qdcount = 1
    header = struct.pack("!HHHHHH", tid, flags, qdcount, 0, 0, 0)
    qname = b"".join(
        bytes([len(label)]) + label.encode("ascii") for label in name.split(".") if label
    ) + b"\x00"
    qtype = 1  # A
    qclass = 1  # IN
    question = qname + struct.pack("!HH", qtype, qclass)
    return tid, header + question


def check_dns(service, timeout):
    host = service["host"]
    port = int(service.get("port", 53))
    query_name = service.get("query_name", "example.com")

    start = time.time()
    try:
        tid, payload = build_dns_query(query_name)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        with sock:
            sock.sendto(payload, (host, port))
            data, _ = sock.recvfrom(512)
        if len(data) < 12:
            return False, "dns response too short"
        resp_tid, resp_flags, _qd, ancount, _ns, _ar = struct.unpack("!HHHHHH", data[:12])
        rcode = resp_flags & 0x000F
        ok = (resp_tid == tid) and (rcode == 0) and (ancount >= 1)
        return ok, f"rcode={rcode} ancount={ancount}"
    except Exception as exc:
        return False, f"dns error: {exc}"
    finally:
        _ = time.time() - start


def run_checks(config, output_path):
    timeout = int(config.get("timeout_seconds", DEFAULT_TIMEOUT))
    services = config.get("services", [])
    results = []

    for service in services:
        name = service.get("name", "unnamed")
        service_type = service.get("type", "tcp").lower()
        enabled = service.get("enabled", True)
        start = time.time()

        if not enabled:
            duration = time.time() - start
            record_result(
                results,
                name,
                service_type,
                True,
                duration,
                "skipped (disabled)",
                skipped=True,
            )
            print(f"SKIP {name} ({service_type}): disabled")
            continue

        if service_type in ("http", "https"):
            ok, detail = check_http(service, timeout, service_type)
        elif service_type == "smtp":
            ok, detail = check_smtp(service, timeout)
        elif service_type == "pop3":
            ok, detail = check_pop3(service, timeout)
        elif service_type == "ftp":
            ok, detail = check_ftp(service, timeout)
        elif service_type == "dns":
            ok, detail = check_dns(service, timeout)
        else:
            ok, detail = check_tcp(service, timeout)

        duration = time.time() - start
        record_result(results, name, service_type, ok, duration, detail)
        status = "OK" if ok else "FAIL"
        print(f"{status} {name} ({service_type}): {detail}")

    ensure_dir(os.path.dirname(output_path))
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"timestamp": now_ts(), "results": results}, f, indent=2)

    any_fail = any((not r["ok"]) and (not r.get("skipped")) for r in results)
    return 2 if any_fail else 0


def main():
    parser = argparse.ArgumentParser(description="MACCDC safe service checks")
    parser.add_argument(
        "--config",
        default="config/services.json",
        help="Path to service config JSON",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output JSON path (default: artifacts/service_checks/<timestamp>.json)",
    )
    args = parser.parse_args()

    if not os.path.exists(args.config):
        print(f"Config not found: {args.config}")
        return 1

    config = load_config(args.config)
    if args.output:
        output_path = args.output
    else:
        output_path = os.path.join("artifacts", "service_checks", f"{now_ts()}.json")

    return run_checks(config, output_path)


if __name__ == "__main__":
    sys.exit(main())
