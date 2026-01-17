import time
from collections import defaultdict
from scapy.all import sniff, UDP, IP, conf

# --- THE FIX FOR NO WINPCAP ---
# This forces Scapy to use the OS native L3 socket instead of L2 Ethernet
conf.L3socket = conf.L3socket 

# Detection Constants
MIN_SAMPLES = 10      # Need 10 packets to establish a pattern
MAX_JITTER = 0.5      # Max variance (seconds) allowed for a "beacon"
IGNORE_PORTS = {53, 123, 137, 138, 1900, 5353} # Whitelist common noise

# Storage: { (src, dst, dport): [timestamp1, timestamp2, ...] }
flow_history = defaultdict(list)

def detect_beacon(pkt):
    # We only care about IP and UDP layers; Layer 2 is bypassed
    if pkt.haslayer(IP) and pkt.haslayer(UDP):
        ip_layer = pkt[IP]
        udp_layer = pkt[UDP]
        
        if udp_layer.dport in IGNORE_PORTS:
            return

        flow_id = (ip_layer.src, ip_layer.dst, udp_layer.dport)
        now = time.time()
        
        history = flow_history[flow_id]
        history.append(now)

        if len(history) >= MIN_SAMPLES:
            # Calculate time intervals (delta) between consecutive packets
            intervals = [history[i] - history[i-1] for i in range(1, len(history))]
            
            avg_gap = sum(intervals) / len(intervals)
            # Jitter = Difference between the longest and shortest interval observed
            jitter = max(intervals) - min(intervals)

            # Low jitter implies automated timing (a beacon)
            if jitter < MAX_JITTER:
                print(f"\n[!] ALERT: UDP Beacon Detected (L3 Native)")
                print(f"    Flow:     {flow_id[0]} -> {flow_id[1]}:{flow_id[2]}")
                print(f"    Avg Gap:  {avg_gap:.3f}s")
                print(f"    Jitter:   {jitter:.3f}s")

            # Slide the window to prevent memory bloat
            flow_history[flow_id] = history[-MIN_SAMPLES:]

print("Starting Native L3 UDP Sniffer...")
print("Note: Run as Administrator (Windows) or Sudo (Linux).")

# 'store=0' ensures we don't store packets in RAM, only process them
sniff(filter="udp", prn=detect_beacon, store=0)
