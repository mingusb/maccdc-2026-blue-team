import os
import hashlib
import sys
import syslog

def get_sha256(file_path):
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except: return None

def monitor(directories):
    syslog.openlog(ident="FILE_INTEGRITY_MONITOR", facility=syslog.LOG_AUTH)

    for target_dir in directories:
        db_path = os.path.join(target_dir, ".file_integ.db")
        if not os.path.exists(db_path):
            syslog.syslog(syslog.LOG_ERR, f"Database missing for {target_dir}. Run generator first.")
            continue

        # Load Baseline
        baseline = {}
        with open(db_path, "r") as f:
            for line in f:
                path, f_hash = line.strip().split("|")
                baseline[path] = f_hash

        # Scan Current State
        current_files = {}
        for root, _, files in os.walk(target_dir):
            if ".file_integ.db" in files: files.remove(".file_integ.db")
            for name in files:
                path = os.path.join(root, name)
                current_files[path] = get_sha256(path)

        # Compare
        all_paths = set(baseline.keys()).union(set(current_files.keys()))
        for path in all_paths:
            if path not in baseline:
                syslog.syslog(syslog.LOG_WARNING, f"NEW FILE detected: {path}")
            elif path not in current_files:
                syslog.syslog(syslog.LOG_CRIT, f"MISSING FILE detected: {path}")
            elif baseline[path] != current_files[path]:
                syslog.syslog(syslog.LOG_CRIT, f"MODIFIED FILE detected (Hash Mismatch): {path}")

if __name__ == "__main__":
    # Example: python3 monitor_integ.py /etc /bin /var/www
    if len(sys.argv) < 2:
        print("Usage: python3 monitor_integ.py /dir1 /dir2 ...")
    else:
        monitor(sys.argv[1:])