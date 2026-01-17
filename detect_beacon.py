import time
from collections import defaultdict
from scapy.all import sniff, UDP, IP, conf

# --- FORCE LAYER 3 MODE ---
# This bypasses the need for WinPcap/Npcap by using the OS native L3 socket
conf.L3socket = conf.L3socket 

# Detection Settings
MIN_SAMPLES = 10      # Number of packets needed to verify a pattern
MAX_JITTER = 0.5      # Maximum variance (in seconds) allowed for a 'beacon'
IGNORE_PORTS = {53, 123, 137, 138, 1900} # Whitelist: DNS, NTP, NetBIOS, SSDP

# Data Store: { (src, dst, dport): [timestamp1, timestamp2, ...] }
flow_db = defaultdict(list)

def detect_udp_beacon(pkt):
    # Ensure we have IP and UDP layers (L2 is ignored/absent)
    if pkt.haslayer(IP) and pkt.haslayer(UDP):
        ip_src = pkt[IP].src
        ip_dst = pkt[IP].dst
        port_dst = pkt[UDP].dport
        
        if port_dst in IGNORE_PORTS:
            return

        flow_key = (ip_src, ip_dst, port_dst)
        now = time.time()
        
        # Track timing
        flow_db[flow_key].append(now)
        timestamps = flow_db[flow_key]

        if len(timestamps) >= MIN_SAMPLES:
            # Calculate time differences between packets
            intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
            
            avg_interval = sum(intervals) / len(intervals)
            # Jitter = Difference between slowest and fastest packet in the window
            jitter = max(intervals) - min(intervals)

            # If jitter is low, the timing is automated (a beacon)
            if jitter < MAX_JITTER:
                print(f"\n[!] ALERT: UDP Beacon Detected")
                print(f"    Flow:     {ip_src} -> {ip_dst}:{port_dst}")
                print(f"    Interval: {avg_interval:.3f}s")
                print(f"    Jitter:   {jitter:.3f}s")

            # Maintain a sliding window to keep memory usage low
            flow_db[flow_key] = timestamps[-MIN_SAMPLES:]

print("Scanning for UDP beacons at Layer 3...")
print("Administrator/Sudo privileges are required for raw sockets.")

# sniff() will now use the L3 socket defined in conf.L3socket
sniff(filter="udp", prn=detect_udp_beacon, store=0)
