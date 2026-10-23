
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
