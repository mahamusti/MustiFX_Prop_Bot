#!/data/data/com.termux/files/usr/bin/bash
pgrep -f "python3 ui_server.py" >/dev/null && echo "[✓] UI running" || echo "[-] UI stopped"
[ -f ~/copy_trade_hub/ui.log ] && tail -n 30 ~/copy_trade_hub/ui.log
