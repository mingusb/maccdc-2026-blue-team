import os
import hashlib
import sys

# Standard name for the baseline database
DB_NAME = ".integ_db"

def get_sha256(file_path):
    """Calculates SHA-256 only for regular files; ignores sockets/pipes."""
    try:
        # Check if it's a regular file (not a socket, device, or directory)
        if not os.path.isfile(file_path) or os.path.islink(file_path):
            return None
            
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except (PermissionError, OSError):
        return None

def generate_baseline(directory):
    directory = os.path.abspath(directory)
    db_path = os.path.join(directory, DB_NAME)
    
    with open(db_path, "w") as db:
        for root, _, files in os.walk(directory):
            for name in files:
                if name == DB_NAME: continue
                
                filepath = os.path.join(root, name)
                file_hash = get_sha256(filepath)
                
                if file_hash:
                    db.write(f"{filepath}|{file_hash}\n")
    
    print(f"Success: Baseline generated in {db_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: sudo python3 gen_baseline.py /path/to/monitor")
    else:
        generate_baseline(sys.argv[1])
