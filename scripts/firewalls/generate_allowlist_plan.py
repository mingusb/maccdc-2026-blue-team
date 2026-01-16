#!/usr/bin/env python3
"""Generate firewall allow-list plan files from config/services.json.

Modes: list, dry-run, apply, backup, restore
"""

import argparse
import csv
import json
import os
import shutil
import sys
import time


def now_ts():
    return time.strftime("%Y%m%d-%H%M%S")


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def probe_services(services, ftp_passive_range):
    issues = []
    for svc in services:
        name = svc.get("name", "unnamed")
        if "host" not in svc:
            issues.append(f"{name}: missing host")
        if "public_ip" not in svc:
            issues.append(f"{name}: missing public_ip")
        if "type" not in svc:
            issues.append(f"{name}: missing type")
        if "port" not in svc and svc.get("type") not in ("http", "https", "dns"):
            issues.append(f"{name}: missing port")
        if svc.get("type") == "ftp" and not ftp_passive_range:
            issues.append(f"{name}: ftp passive range not specified")
    return issues


def build_plan(services, ftp_passive_range):
    plan = []
    for svc in services:
        if not svc.get("enabled", True):
            continue
        service_type = svc.get("type", "tcp")
        port = svc.get("port")
        if service_type in ("http", "https"):
            port = port or (443 if service_type == "https" else 80)
        elif service_type == "dns":
            port = port or 53
        entry = {
            "name": svc.get("name", "unnamed"),
            "type": service_type,
            "protocol": "tcp" if service_type not in ("dns", "icmp") else "udp/tcp",
            "port": str(port) if port else "",
            "public_ip": svc.get("public_ip", ""),
            "internal_host": svc.get("host", ""),
            "notes": svc.get("notes", ""),
        }
        plan.append(entry)
        if service_type == "ftp" and ftp_passive_range:
            plan.append(
                {
                    "name": f"{svc.get('name','ftp')}_passive",
                    "type": "ftp-passive",
                    "protocol": "tcp",
                    "port": ftp_passive_range,
                    "public_ip": svc.get("public_ip", ""),
                    "internal_host": svc.get("host", ""),
                    "notes": "FTP passive range",
                }
            )
    return plan


def write_plan(plan, outdir):
    os.makedirs(outdir, exist_ok=True)
    ts = now_ts()
    csv_path = os.path.join(outdir, f"allowlist_{ts}.csv")
    json_path = os.path.join(outdir, f"allowlist_{ts}.json")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "name",
                "type",
                "protocol",
                "port",
                "public_ip",
                "internal_host",
                "notes",
            ],
        )
        writer.writeheader()
        for row in plan:
            writer.writerow(row)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=2)
    return csv_path, json_path


def backup_dir(outdir):
    ts = now_ts()
    bdir = os.path.join(outdir, "backup", ts)
    os.makedirs(bdir, exist_ok=True)
    return bdir


def backup_existing(outdir):
    if not os.path.isdir(outdir):
        return None
    bdir = backup_dir(outdir)
    for name in os.listdir(outdir):
        if name.startswith("allowlist_"):
            shutil.copy2(os.path.join(outdir, name), os.path.join(bdir, name))
    return bdir


def restore_latest(outdir):
    backup_root = os.path.join(outdir, "backup")
    if not os.path.isdir(backup_root):
        return None
    entries = sorted(os.listdir(backup_root))
    if not entries:
        return None
    latest = os.path.join(backup_root, entries[-1])
    for name in os.listdir(latest):
        shutil.copy2(os.path.join(latest, name), os.path.join(outdir, name))
    return latest


def main():
    parser = argparse.ArgumentParser(description="Generate firewall allow-list plan files")
    parser.add_argument("--mode", default="list", choices=["list", "dry-run", "apply", "backup", "restore"])
    parser.add_argument("--config", default="config/services.json")
    parser.add_argument("--output-dir", default="artifacts/firewall_plans")
    parser.add_argument("--ftp-passive-range", default="")
    args = parser.parse_args()

    if args.mode in ("list", "dry-run", "apply"):
        if not os.path.exists(args.config):
            print(f"Config not found: {args.config}")
            return 1
        config = load_config(args.config)
        services = config.get("services", [])
        issues = probe_services(services, args.ftp_passive_range)
        if args.mode == "list":
            print(f"services: {len(services)}")
            for svc in services:
                print(f"- {svc.get('name','unnamed')} ({svc.get('type','tcp')})")
            if issues:
                print("warnings:")
                for item in issues:
                    print(f"- {item}")
            return 0
        if args.mode == "dry-run":
            if issues:
                print("probe issues:")
                for item in issues:
                    print(f"- {item}")
            plan = build_plan(services, args.ftp_passive_range)
            print(f"would generate plan entries: {len(plan)}")
            return 0
        if args.mode == "apply":
            if issues:
                print("probe issues:")
                for item in issues:
                    print(f"- {item}")
            bdir = backup_existing(args.output_dir)
            if bdir:
                print(f"backed up existing plans to: {bdir}")
            plan = build_plan(services, args.ftp_passive_range)
            csv_path, json_path = write_plan(plan, args.output_dir)
            print(f"wrote: {csv_path}")
            print(f"wrote: {json_path}")
            return 0

    if args.mode == "backup":
        bdir = backup_existing(args.output_dir)
        if not bdir:
            print("no existing plans to back up")
        else:
            print(f"backed up plans to: {bdir}")
        return 0

    if args.mode == "restore":
        restored = restore_latest(args.output_dir)
        if not restored:
            print("no backups found to restore")
            return 1
        print(f"restored from: {restored}")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
