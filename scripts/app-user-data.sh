#!/bin/bash
set -e

# Update and install Python
apt-get update -y
apt-get install -y python3

# Create application directory
mkdir -p /opt/ha-webapp

# Create Python web application
cat > /opt/ha-webapp/server.py <<'PYTHON'
#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import socket
import datetime
import uuid

HOSTNAME = socket.gethostname()
REQUEST_COUNTER = 0

class DemoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global REQUEST_COUNTER
        REQUEST_COUNTER += 1

        body = (
            "AWS High Availability Web Application\n"
            "=================================\n"
            f"Hostname: {HOSTNAME}\n"
            "Port: 8002\n"
            f"Current Time: {datetime.datetime.now().isoformat()}\n"
            f"Request Number: {REQUEST_COUNTER}\n"
            f"Request ID: {uuid.uuid4()}\n"
            f"Client IP: {self.client_address[0]}\n"
            f"Requested Path: {self.path}\n"
            "Message: Hello from EC2!\n"
        )

        encoded = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

if __name__ == "__main__":
    ThreadingHTTPServer(
        ("0.0.0.0", 8002), DemoHandler
    ).serve_forever()
PYTHON

# Create systemd service
cat > /etc/systemd/system/ha-webapp.service <<'SERVICE'
[Unit]
Description=HA Web App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/ha-webapp
ExecStart=/usr/bin/python3 -u /opt/ha-webapp/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

chmod 755 /opt/ha-webapp/server.py

# Start application automatically
systemctl daemon-reload
systemctl enable --now ha-webapp.service
systemctl is-active ha-webapp.service
  
