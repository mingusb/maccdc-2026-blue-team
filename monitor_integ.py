import os
import hashlib
import sys
import syslog

def get_sha256(file_path):
    # ROBUSTNESS CHECK: Skip sockets, device files, etc.
    if not os.path.isfile(file_path) or os.path.islink(file_path):
        return None

    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except (PermissionError, FileNotFoundError, OSError):
        return None

def monitor(directories):
    syslog.openlog(ident="FILE_INTEGRITY_MONITOR", facility=syslog.LOG_AUTH)

    for target_dir in directories:
        db_path = os.path.join(target_dir, ".file_integ.db")
        if not os.path.exists(db_path):
            continue

        # Load Baseline
        baseline = {}
        try:
            with open(db_path, "r") as f:
                for line in f:
                    if "|" in line:
                        path, f_hash = line.strip().split("|")
                        baseline[path] = f_hash
        except Exception as e:
            syslog.syslog(syslog.LOG_ERR, f"Error reading DB {db_path}: {e}")
            continue

        # Scan Current State
        current_files = {}
        for root, _, files in os.walk(target_dir):
            if ".file_integ.db" in files: files.remove(".file_integ.db")
            for name in files:
                path = os.path.join(root, name)
                # Only hash if it's a regular file
                f_hash = get_sha256(path)
                if f_hash:
                    current_files[path] = f_hash

        # Logic for Comparisons
        # 1. Check for Missing or Modified
        for path, old_hash in baseline.items():
            if path not in current_files:
                syslog.syslog(syslog.LOG_CRIT, f"MISSING FILE: {path}")
            elif old_hash != current_files[path]:
                syslog.syslog(syslog.LOG_CRIT, f"MODIFIED FILE: {path}")

        # 2. Check for New files
        for path in current_files:
            if path not in baseline:
                syslog.syslog(syslog.LOG_WARNING, f"NEW FILE: {path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 monitor_integ.py /dir1 /dir2 ...")
    else:
        monitor(sys.argv[1:])
