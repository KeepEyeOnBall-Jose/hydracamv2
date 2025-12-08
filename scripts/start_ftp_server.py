#!/usr/bin/env python3
"""
Start a temporary FTP server on Mac to receive files from Android device.
"""

import os
import sys
from pathlib import Path
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer
import socket

def get_local_ip():
    """Get the local IP address."""
    try:
        # Connect to external address to determine local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"

def main():
    # Create download directory
    download_dir = Path.home() / "Desktop" / "android_videos"
    download_dir.mkdir(exist_ok=True)

    # Get local IP
    local_ip = get_local_ip()
    port = 2121

    # Set up FTP server
    authorizer = DummyAuthorizer()

    # Add anonymous user with write permissions
    authorizer.add_anonymous(str(download_dir), perm="elradfmw")

    handler = FTPHandler
    handler.authorizer = authorizer

    # Enable passive mode with a port range
    handler.passive_ports = range(60000, 60100)

    # Banner
    handler.banner = "Android Video Transfer FTP Server Ready"

    server = FTPServer((local_ip, port), handler)

    # Set max connections
    server.max_cons = 256
    server.max_cons_per_ip = 5

    print("=" * 70)
    print("🚀 FTP SERVER STARTED")
    print("=" * 70)
    print(f"📁 Download Directory: {download_dir}")
    print(f"🌐 Server Address: {local_ip}:{port}")
    print(f"👤 Username: anonymous (no password)")
    print("=" * 70)
    print()
    print("📱 On your Android device, use an FTP client app to connect:")
    print(f"   - Host: {local_ip}")
    print(f"   - Port: {port}")
    print(f"   - Username: anonymous")
    print(f"   - Password: (leave blank)")
    print()
    print("Or use ADB to push files via FTP client:")
    print(f"   See instructions in android_ftp_upload.sh")
    print()
    print("=" * 70)
    print("Press Ctrl+C to stop the server")
    print("=" * 70)
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped")
        server.close_all()

if __name__ == "__main__":
    main()

