#!/usr/bin/env python3
"""Credential rotation helper with list/dry-run/apply/backup/restore modes."""

import argparse
import json
import os
import secrets
import shutil
import string
import sys
import time


def now_ts():
    return time.strftime("%Y%m%d-%H%M%S")


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def gen_password(policy):
    length = int(policy.get("length", 20))
    charset = ""
    if policy.get("upper", True):
        charset += string.ascii_uppercase
    if policy.get("lower", True):
        charset += string.ascii_lowercase
    if policy.get("digits", True):
        charset += string.digits
    if policy.get("symbols", False):
        charset += "!@#$%_-+"
    if not charset:
        raise ValueError("Password policy has empty charset")
    return "".join(secrets.choice(charset) for _ in range(length))


def backup_file(path, backup_dir):
    if not os.path.exists(path):
        return None
    os.makedirs(backup_dir, exist_ok=True)
    dest = os.path.join(backup_dir, f"credentials_{now_ts()}.md")
    shutil.copy2(path, dest)
    return dest


def restore_file(src, dest):
    if not os.path.exists(src):
        raise FileNotFoundError(src)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(src, dest)


def write_credentials_md(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = ["Rotated credentials", "", "| Host | Username | Password |", "| --- | --- | --- |"]
    for entry in entries:
        lines.append(
            f"| {entry['host']} | {entry['username']} | {entry['password']} |"
        )
    lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def list_accounts(config):
    accounts = config.get("accounts", [])
    print(f"accounts: {len(accounts)}")
    for acct in accounts:
        print(f"- {acct.get('host')}:{acct.get('username')} ({acct.get('platform','unknown')})")


def probe(config, apply_local):
    issues = []
    accounts = config.get("accounts", [])
    if not accounts:
        issues.append("no accounts defined")
    if apply_local and os.geteuid() != 0:
        issues.append("apply-local requires root")
    if apply_local and shutil.which("chpasswd") is None:
        issues.append("chpasswd not found for apply-local")
    return issues


def apply_local_changes(entries, config):
    for entry in entries:
        acct = entry["account"]
        if not acct.get("apply_local"):
            continue
        if acct.get("platform") != "linux":
            continue
        username = acct.get("username")
        password = entry["password"]
        os.system(f"echo '{username}:{password}' | chpasswd")


def main():
    parser = argparse.ArgumentParser(description="Rotate credentials")
    parser.add_argument("--mode", choices=["list", "dry-run", "apply", "backup", "restore"], default="list")
    parser.add_argument("--config", default="config/credentials.json")
    parser.add_argument("--fallback-config", default="config/credentials.example.json")
    parser.add_argument("--secrets-path", default="secrets/credentials.md")
    parser.add_argument("--backup-dir", default="artifacts/backups/credentials")
    parser.add_argument("--restore-from", default="")
    parser.add_argument("--apply-local", action="store_true", help="Apply to local Linux accounts marked apply_local")
    args = parser.parse_args()

    config_path = args.config if os.path.exists(args.config) else args.fallback_config
    if not os.path.exists(config_path):
        print(f"Config not found: {config_path}")
        return 1

    config = load_config(config_path)

    if args.mode == "list":
        list_accounts(config)
        return 0

    if args.mode == "backup":
        dest = backup_file(args.secrets_path, args.backup_dir)
        if dest:
            print(f"backup created: {dest}")
        else:
            print("no secrets file to back up")
        return 0

    if args.mode == "restore":
        if not args.restore_from:
            print("--restore-from is required")
            return 1
        restore_file(args.restore_from, args.secrets_path)
        print(f"restored: {args.secrets_path}")
        return 0

    issues = probe(config, args.apply_local)
    if args.mode == "dry-run":
        if issues:
            print("probe issues:")
            for item in issues:
                print(f"- {item}")
        print("would rotate credentials for:")
        for acct in config.get("accounts", []):
            print(f"- {acct.get('host')}:{acct.get('username')}")
        return 0

    if args.mode == "apply":
        if issues:
            print("probe issues:")
            for item in issues:
                print(f"- {item}")
        backup_file(args.secrets_path, args.backup_dir)
        policy = config.get("password_policy", {})
        entries = []
        for acct in config.get("accounts", []):
            pwd = gen_password(policy)
            entries.append(
                {"host": acct.get("host"), "username": acct.get("username"), "password": pwd, "account": acct}
            )
        write_credentials_md(args.secrets_path, entries)
        os.makedirs("artifacts/credentials", exist_ok=True)
        out_json = os.path.join("artifacts/credentials", f"credentials_{now_ts()}.json")
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump(entries, f, indent=2)
        if args.apply_local:
            apply_local_changes(entries, config)
        print(f"wrote: {args.secrets_path}")
        print(f"wrote: {out_json}")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
