#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y frr frr-pythontools python3-pip git curl wget

# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Configure FRR
cat > /etc/frr/daemons << EOF
bgpd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no
EOF

# Start FRR
systemctl enable frr
systemctl start frr

# Configure BGP based on router ID
ROUTER_ID=${router_id}
ROUTER_COUNT=${router_count}
ASN=$((65000 + ROUTER_ID))

# Create BGP configuration
cat > /etc/frr/frr.conf << EOF
!
! FRR configuration file
!
hostname bgp-router-${ROUTER_ID}
password zebra
enable password zebra
!
log file /var/log/frr/frr.log
!
router bgp ${ASN}
 bgp router-id 10.0.1.${ROUTER_ID}
 network 10.0.${ROUTER_ID}.0/24
!
line vty
!
EOF

# Add BGP neighbors (mesh topology)
for i in $(seq 1 $ROUTER_COUNT); do
  if [ $i -ne $ROUTER_ID ]; then
    NEIGHBOR_ASN=$((65000 + i))
    echo " neighbor 10.0.1.$i remote-as $NEIGHBOR_ASN" >> /etc/frr/frr.conf
  fi
done

# Restart FRR to apply configuration
systemctl restart frr

# Install Python dependencies for monitoring
pip3 install boto3 psutil prometheus-client

# Create monitoring script
cat > /opt/bgp-monitor.py << 'EOF'
#!/usr/bin/env python3
import boto3
import psutil
import subprocess
import time
import json
from datetime import datetime

def get_bgp_status():
    try:
        result = subprocess.run(['vtysh', '-c', 'show ip bgp summary'], 
                              capture_output=True, text=True)
        return result.stdout
    except:
        return "BGP status unavailable"

def get_system_metrics():
    return {
        'cpu_percent': psutil.cpu_percent(),
        'memory_percent': psutil.virtual_memory().percent,
        'disk_percent': psutil.disk_usage('/').percent
    }

def upload_to_s3(bucket_name, data):
    try:
        s3 = boto3.client('s3')
        timestamp = datetime.now().isoformat()
        key = f"logs/router-{data['router_id']}/{timestamp}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(data),
            ContentType='application/json'
        )
    except Exception as e:
        print(f"Failed to upload to S3: {e}")

if __name__ == "__main__":
    import sys
    router_id = sys.argv[1] if len(sys.argv) > 1 else "1"
    bucket_name = sys.argv[2] if len(sys.argv) > 2 else "bgp-logs"
    
    while True:
        data = {
            'router_id': router_id,
            'timestamp': datetime.now().isoformat(),
            'bgp_status': get_bgp_status(),
            'system_metrics': get_system_metrics()
        }
        
        upload_to_s3(bucket_name, data)
        time.sleep(60)  # Upload every minute
EOF

chmod +x /opt/bgp-monitor.py

# Start monitoring in background
nohup /opt/bgp-monitor.py ${ROUTER_ID} ${S3_BUCKET_NAME} > /var/log/bgp-monitor.log 2>&1 &

echo "BGP router ${ROUTER_ID} setup complete" 