import time
from scapy.all import sniff, UDP, IP
from collections import defaultdict

# Configuration
THRESHOLD_COUNT = 10  # Number of packets to observe before analyzing
JITTER_TOLERANCE = 0.5 # Seconds of variance allowed for a "steady" heartbeat

# Data store: { (src, dst, dport): [timestamp1, timestamp2, ...] }
traffic_map = defaultdict(list)

def analyze_packet(pkt):
    if pkt.haslayer(UDP) and pkt.haslayer(IP):
        src = pkt[IP].src
        dst = pkt[IP].dst
        dport = pkt[UDP].dport
        flow_key = (src, dst, dport)
        
        # Record the arrival time
        now = time.time()
        traffic_map[flow_key].append(now)
        
        # Check if we have enough data to look for a pattern
        timestamps = traffic_map[flow_key]
        if len(timestamps) >= THRESHOLD_COUNT:
            # Calculate intervals between packets
            intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
            
            # Calculate average interval and variance (jitter)
            avg_interval = sum(intervals) / len(intervals)
            variance = max(intervals) - min(intervals)
            
            if variance < JITTER_TOLERANCE:
                print(f"[!] POTENTIAL BEACON DETECTED")
                print(f"    Flow: {src} -> {dst}:{dport}")
                print(f"    Interval: {avg_interval:.2f}s (Variance: {variance:.2f}s)")
                print("-" * 30)
            
            # Keep the list short to avoid memory bloat
            traffic_map[flow_key] = timestamps[-THRESHOLD_COUNT:]

print("Searching for UDP heartbeats... (Press Ctrl+C to stop)")
sniff(filter="udp", prn=analyze_packet, store=0)