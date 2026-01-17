import os
import hashlib
import sys
import syslog

DB_NAME = ".integ_db"

def get_sha256(file_path):
    if not os.path.isfile(file_path) or os.path.islink(file_path):
        return None
    try:
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except: return None

def monitor(directories):
    # Initialize Syslog
    syslog.openlog(ident="FILE_INTEGRITY", facility=syslog.LOG_AUTH)

    for target_dir in directories:
        target_dir = os.path.abspath(target_dir)
        db_path = os.path.join(target_dir, DB_NAME)
        
        if not os.path.exists(db_path):
            syslog.syslog(syslog.LOG_ERR, f"Integrity check failed: No database found in {target_dir}")
            continue

        # 1. Load Baseline
        baseline = {}
        with open(db_path, "r") as f:
            for line in f:
                if "|" in line:
                    path, f_hash = line.strip().split("|")
                    baseline[path] = f_hash

        # 2. Scan Current State
        current_state = {}
        for root, _, files in os.walk(target_dir):
            for name in files:
                if name == DB_NAME: continue
                path = os.path.join(root, name)
                f_hash = get_sha256(path)
                if f_hash: current_state[path] = f_hash

        # 3. Compare and Alert
        # Check for Missing or Modified files
        for path, old_hash in baseline.items():
            if path not in current_state:
                syslog.syslog(syslog.LOG_CRIT, f"ALERT: Missing file detected: {path}")
            elif old_hash != current_state[path]:
                syslog.syslog(syslog.LOG_CRIT, f"ALERT: File modified (hash mismatch): {path}")

        # Check for New files
        for path in current_state:
            if path not in baseline:
                syslog.syslog(syslog.LOG_WARNING, f"ALERT: New file detected: {path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 monitor_integ.py /dir1 /dir2 ...")
    else:
        monitor(sys.argv[1:])
