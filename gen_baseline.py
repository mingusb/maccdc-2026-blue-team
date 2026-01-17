import os
import hashlib
import sys

def get_sha256(file_path):
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except (PermissionError, FileNotFoundError):
        return None

def generate_baseline(directory):
    db_path = os.path.join(directory, ".file_integ.db")
    with open(db_path, "w") as db:
        for root, dirs, files in os.walk(directory):
            # Skip the database file itself
            if ".file_integ.db" in files:
                files.remove(".file_integ.db")
            
            for name in files:
                filepath = os.path.join(root, name)
                file_hash = get_sha256(filepath)
                if file_hash:
                    db.write(f"{filepath}|{file_hash}\n")
    
    print(f"Baseline generated successfully in {db_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 gen_baseline.py /path/to/directory")
    else:
        generate_baseline(sys.argv[1])