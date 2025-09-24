#!/data/data/com.termux/files/usr/bin/bash
set -e
# stop by process name
pkill -f "python3 copy_hub_flask.py" 2>/dev/null || true
echo "[+] Hub stopped"
