import time
from collections import defaultdict
from scapy.all import sniff, UDP, IP, conf

# --- CRITICAL FIX: FORCE LAYER 3 ---
# This bypasses the L2/WinPcap error by using the OS native L3 socket
conf.L3socket = conf.L3socket 

# Detection Parameters
MIN_SAMPLES = 8       # Number of packets needed to establish a pattern
JITTER_THRESHOLD = 0.4 # Max variance (seconds) to be considered a beacon
WHITELIST_PORTS = {53, 123, 1900, 5353} # DNS, NTP, SSDP, mDNS

# { (src, dst, dport): [timestamp1, timestamp2, ...] }
flow_history = defaultdict(list)

def analyze_packet(pkt):
    # Only process IP + UDP (Layer 3 and 4)
    if pkt.haslayer(IP) and pkt.haslayer(UDP):
        ip_layer = pkt[IP]
        udp_layer = pkt[UDP]

        if udp_layer.dport in WHITELIST_PORTS:
            return

        flow_id = (ip_layer.src, ip_layer.dst, udp_layer.dport)
        now = time.time()
        
        flow_history[flow_id].append(now)
        timestamps = flow_history[flow_id]

        if len(timestamps) >= MIN_SAMPLES:
            # Calculate time intervals between packets
            intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
            
            avg_interval = sum(intervals) / len(intervals)
            # Jitter is the variance in timing (Max diff - Min diff)
            jitter = max(intervals) - min(intervals)

            # A low jitter indicates a programmed heartbeat (malware)
            if jitter < JITTER_THRESHOLD:
                print(f"\n[!] ALERT: UDP Beaconing Detected")
                print(f"    Target:   {flow_id[1]}:{flow_id[2]}")
                print(f"    Internal: {flow_id[0]}")
                print(f"    Interval: {avg_interval:.3f}s")
                print(f"    Jitter:   {jitter:.3f}s")

            # Slide window to save memory
            flow_history[flow_id] = timestamps[-MIN_SAMPLES:]

print("Monitoring UDP at Layer 3 (No WinPcap required)...")
print("Note: Windows users must run as Administrator.")

# Filter is applied at the OS level; store=0 prevents RAM bloat
sniff(filter="udp", prn=analyze_packet, store=0)
