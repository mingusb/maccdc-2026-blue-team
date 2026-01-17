import os
import hashlib
import sys

def get_sha256(file_path):
    # ROBUSTNESS CHECK: Only process regular files
    # This ignores sockets, pipes, and device files
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

def generate_baseline(directory):
    db_path = os.path.join(directory, ".file_integ.db")
    count = 0
    with open(db_path, "w") as db:
        for root, dirs, files in os.walk(directory):
            if ".file_integ.db" in files:
                files.remove(".file_integ.db")
            
            for name in files:
                filepath = os.path.join(root, name)
                file_hash = get_sha256(filepath)
                if file_hash:
                    db.write(f"{filepath}|{file_hash}\n")
                    count += 1
    
    print(f"Baseline generated for {count} regular files in {db_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 gen_baseline.py /path/to/directory")
    else:
        generate_baseline(sys.argv[1])
