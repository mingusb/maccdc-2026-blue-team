import time
from collections import defaultdict
from scapy.all import sniff, UDP, IP, conf

# --- L3 CONFIGURATION ---
# This tells Scapy to ignore the lack of WinPcap/Npcap 
# and use the OS's native Layer 3 raw sockets.
conf.L3socket = conf.L3socket 

# Configuration Constants
MIN_PACKETS = 10      # Need 10 packets to establish a pattern
MAX_JITTER = 0.5      # Max seconds of variation allowed for a "beacon"
IGNORE_PORTS = {53, 123, 1900} # DNS, NTP, SSDP (Common noise)

# Storage: {(src, dst, dport): [timestamp1, timestamp2, ...]}
flow_history = defaultdict(list)

def detect_beacon(pkt):
    # We check for IP layer directly since L2 (Ethernet) is unavailable
    if pkt.haslayer(IP) and pkt.haslayer(UDP):
        ip_layer = pkt[IP]
        udp_layer = pkt[UDP]
        
        if udp_layer.dport in IGNORE_PORTS:
            return

        flow_id = (ip_layer.src, ip_layer.dst, udp_layer.dport)
        now = time.time()
        
        history = flow_history[flow_id]
        history.append(now)

        if len(history) >= MIN_PACKETS:
            # Calculate the time difference between consecutive packets
            intervals = [history[i] - history[i-1] for i in range(1, len(history))]
            
            avg_gap = sum(intervals) / len(intervals)
            # Jitter is the difference between the longest and shortest interval
            jitter = max(intervals) - min(intervals)

            # If the timing is very consistent, it's a beacon
            if jitter < MAX_JITTER:
                print(f"\n[!] ALERT: UDP Beacon Pattern Detected")
                print(f"    Source:      {flow_id[0]}")
                print(f"    Destination: {flow_id[1]}:{flow_id[2]}")
                print(f"    Avg Gap:     {avg_gap:.3f}s")
                print(f"    Jitter:      {jitter:.3f}s")

            # Keep memory usage low by sliding the window
            flow_history[flow_id] = history[-(MIN_PACKETS):]

print("Starting Layer 3 UDP Sniffer...")
print("Note: On Windows, ensure you are running as Administrator.")

# Use 'store=0' to prevent memory exhaustion
sniff(filter="udp", prn=detect_beacon, store=0)
