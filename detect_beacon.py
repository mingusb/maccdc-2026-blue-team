import time
from collections import defaultdict
from scapy.all import sniff, UDP, IP, conf

# --- THE FIX: FORCE LAYER 3 MODE ---
# This bypasses the L2/WinPcap error by using the OS native L3 socket
conf.L3socket = conf.L3socket 

# Detection Settings
MIN_SAMPLES = 10      # Number of packets to observe before flagging
JITTER_THRESHOLD = 0.5 # Max variance (in seconds) allowed for a 'beacon'
IGNORE_PORTS = {53, 123, 137, 138, 1900, 5353} # Whitelist: DNS, NTP, NetBIOS

# Storage: { (src, dst, dport): [timestamp1, timestamp2, ...] }
flow_db = defaultdict(list)

def detect_beacon(pkt):
    # Only process IP + UDP (Layer 3 and 4)
    if pkt.haslayer(IP) and pkt.haslayer(UDP):
        ip_layer = pkt[IP]
        udp_layer = pkt[UDP]
        
        if udp_layer.dport in IGNORE_PORTS:
            return

        flow_key = (ip_layer.src, ip_layer.dst, udp_layer.dport)
        now = time.time()
        
        history = flow_db[flow_key]
        history.append(now)

        if len(history) >= MIN_SAMPLES:
            # Calculate time intervals between packets
            intervals = [history[i] - history[i-1] for i in range(1, len(history))]
            
            avg_gap = sum(intervals) / len(intervals)
            # Jitter = Difference between the longest and shortest interval observed
            jitter = max(intervals) - min(intervals)

            # Low jitter (consistency) suggests an automated beacon
            if jitter < JITTER_THRESHOLD:
                print(f"\n[!] ALERT: UDP Beacon Detected (Native L3)")
                print(f"    Flow:     {flow_key[0]} -> {flow_key[1]}:{flow_key[2]}")
                print(f"    Interval: ~{avg_gap:.2f}s")
                print(f"    Jitter:   {jitter:.4f}s")

            # Maintain a sliding window to save memory
            flow_db[flow_key] = history[-MIN_SAMPLES:]

print("Starting UDP Beacon Detector using Native Layer 3 Sockets...")
print("Note: Run as Administrator (Windows) or Sudo (Linux).")

# 'store=0' ensures we don't store packets in RAM
sniff(filter="udp", prn=detect_beacon, store=0)
