import socket
import struct
import time
from collections import defaultdict

# --- CONFIGURATION ---
THRESHOLD = 10        # Packets to observe
JITTER_LIMIT = 0.5    # Seconds of variance allowed

# Storage: { (src_ip, dst_ip, port): [timestamps] }
flow_data = defaultdict(list)

def get_sniffer():
    # Windows native raw socket setup
    if socket.os_name == 'nt':
        s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_IP)
        s.bind((socket.gethostbyname(socket.gethostname()), 0))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
        s.ioctl(socket.SIO_RCVALL, socket.RCVALL_ON)
    # Linux native raw socket setup
    else:
        s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(3))
    return s

def run_detector():
    sniffer = get_sniffer()
    print("Monitoring for UDP beacons using native sockets...")

    try:
        while True:
            raw_data, addr = sniffer.recvfrom(65535)
            
            # Manually parse the IP Header (First 20 bytes)
            ip_header = raw_data[0:20]
            iph = struct.unpack('!BBHHHBBH4s4s', ip_header)
            
            protocol = iph[6]
            src_ip = socket.inet_ntoa(iph[8])
            dst_ip = socket.inet_ntoa(iph[9])

            if protocol == 17: # UDP is Protocol 17
                # Parse UDP Header (8 bytes after IP header)
                udp_header = raw_data[20:28]
                udph = struct.unpack('!HHHH', udp_header)
                dst_port = udph[1]
                
                key = (src_ip, dst_ip, dst_port)
                now = time.time()
                flow_data[key].append(now)

                if len(flow_data[key]) >= THRESHOLD:
                    timestamps = flow_data[key]
                    intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
                    jitter = max(intervals) - min(intervals)
                    avg_int = sum(intervals) / len(intervals)

                    if jitter < JITTER_LIMIT:
                        print(f"[!] BEACON: {src_ip} -> {dst_ip}:{dst_port} | Interval: {avg_int:.2f}s | Jitter: {jitter:.2f}s")
                    
                    flow_data[key] = timestamps[-THRESHOLD:]

    except KeyboardInterrupt:
        print("\nStopping...")

run_detector()
