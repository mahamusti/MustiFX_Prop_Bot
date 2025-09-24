#!/data/data/com.termux/files/usr/bin/bash
cd ~/copy_trade_hub
pkill -f "python3 ui_server.py" 2>/dev/null || true
nohup python3 ui_server.py > ui.log 2>&1 &
echo "[+] UI started on http://127.0.0.1:8080"
