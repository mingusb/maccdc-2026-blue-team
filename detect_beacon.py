import time
from scapy.all import sniff, UDP, IP, conf
from collections import defaultdict

# Force Scapy to use Layer 3 sockets for better compatibility
# This helps on interfaces that don't provide Ethernet headers
conf.L3socket = conf.L3socket 

# Configuration
THRESHOLD_COUNT = 8    # Packets to observe before flagging
JITTER_TOLERANCE = 0.7 # Max deviation in seconds
WHITELIST_PORTS = {53, 123} # Ignore DNS and NTP

traffic_map = defaultdict(list)

def analyze_packet(pkt):
    # Check for IP layer (Layer 3) and UDP layer (Layer 4)
    if pkt.haslayer(IP) and pkt.haslayer(UDP):
        src = pkt[IP].src
        dst = pkt[IP].dst
        dport = pkt[UDP].dport
        
        if dport in WHITELIST_PORTS:
            return

        flow_key = (src, dst, dport)
        now = time.time()
        traffic_map[flow_key].append(now)
        
        timestamps = traffic_map[flow_key]
        if len(timestamps) >= THRESHOLD_COUNT:
            intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
            avg_interval = sum(intervals) / len(intervals)
            
            # Calculate Jitter (Consistency of the heartbeat)
            # A true beacon will have a very low standard deviation
            variance = max(intervals) - min(intervals)
            
            if variance < JITTER_TOLERANCE:
                print(f"\n[!] BEACON ATTRIBUTES DETECTED")
                print(f"    Source:      {src}")
                print(f"    Destination: {dst}:{dport}")
                print(f"    Interval:    ~{avg_interval:.2f}s")
                print(f"    Jitter:      {variance:.4f}s")
            
            # Slide the window
            traffic_map[flow_key] = timestamps[-(THRESHOLD_COUNT-1):]

print("Monitoring L3 UDP traffic for heartbeat patterns...")
# 'store=0' ensures we don't eat up RAM by saving every packet
sniff(filter="udp", prn=analyze_packet, store=0)
