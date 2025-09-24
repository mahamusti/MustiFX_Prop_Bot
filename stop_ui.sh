#!/data/data/com.termux/files/usr/bin/bash
pkill -f "python3 ui_server.py" 2>/dev/null || true
echo "[+] UI stopped"
