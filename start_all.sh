#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/copy_trade_hub
# kill anything on port 8008 (optional)
fuser -k 8008/tcp 2>/dev/null || true
# start hub in background, log to hub.log
nohup python3 copy_hub_flask.py > hub.log 2>&1 &
echo "[+] Hub started → http://127.0.0.1:8008"
