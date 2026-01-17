import socket
import struct
import time
import os
from collections import defaultdict

# --- CONFIGURATION ---
THRESHOLD = 8         # Number of packets to analyze for a pattern
JITTER_TOLERANCE = 0.4 # Seconds of variance allowed (Lower = more "robotic")

# Data store: { (src, dst, port): [timestamps] }
flow_data = defaultdict(list)

def setup_sniffer():
    # Windows Implementation
    if os.name == 'nt':
        # Get the internal IP of the machine to bind the sniffer
        hostname = socket.gethostname()
        ip_addr = socket.gethostbyname(hostname)
        
        # Create raw socket
        s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_IP)
        s.bind((ip_addr, 0))
        
        # Include IP headers in the capture
        s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
        
        # Enable Promiscuous Mode (This is the "WinPcap-less" magic)
        s.ioctl(socket.SIO_RCVALL, socket.RCVALL_ON)
        return s
    
    # Linux/Unix Implementation
    else:
        # AF_PACKET allows us to see all traffic at the driver level on Linux
        s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(3))
        return s

def run_detector():
    sniffer = setup_sniffer()
    print(f"[*] Sniffing for UDP beacons on {os.name}...")

    try:
        while True:
            raw_packet, _ = sniffer.recvfrom(65535)
            
            # 1. Unpack IP Header (First 20 bytes)
            # !BBHHHBBH4s4s is the format for the IP header
            ip_header = struct.unpack('!BBHHHBBH4s4s', raw_packet[:20])
            protocol = ip_header[6]
            
            if protocol == 17:  # 17 = UDP
                src_ip = socket.inet_ntoa(ip_header[8])
                dst_ip = socket.inet_ntoa(ip_header[9])
                
                # 2. Unpack UDP Header (Next 8 bytes)
                # Format: !HHHH (Source Port, Dest Port, Length, Checksum)
                udp_raw = raw_packet[20:28]
                udp_header = struct.unpack('!HHHH', udp_raw)
                dst_port = udp_header[1]
                
                # 3. Analyze Timing
                flow_key = (src_ip, dst_ip, dst_port)
                now = time.time()
                flow_data[flow_key].append(now)
                
                if len(flow_data[flow_key]) >= THRESHOLD:
                    timestamps = flow_data[flow_key]
                    intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
                    
                    avg_interval = sum(intervals) / len(intervals)
                    jitter = max(intervals) - min(intervals)
                    
                    # If the jitter is low, it's a heartbeat/beacon
                    if jitter < JITTER_TOLERANCE:
                        print(f"\n[!] BEACON DETECTED")
                        print(f"    {src_ip} -> {dst_ip}:{dst_port}")
                        print(f"    Interval: {avg_interval:.2f}s | Jitter: {jitter:.4f}s")
                    
                    # Keep the window sliding
                    flow_data[flow_key] = timestamps[-THRESHOLD:]

    except KeyboardInterrupt:
        if os.name == 'nt':
            sniffer.ioctl(socket.SIO_RCVALL, socket.RCVALL_OFF)
        print("\nShutting down.")

if __name__ == "__main__":
    run_detector()
