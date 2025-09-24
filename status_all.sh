#!/data/data/com.termux/files/usr/bin/bash
echo "== Hub Status =="
if pgrep -f "python3 copy_hub_flask.py" >/dev/null 2>&1; then
  echo "[✓] Hub running"
else
  echo "[-] Hub stopped"
fi
# show last lines of the log if it exists
[ -f ~/copy_trade_hub/hub.log ] && { echo "--- hub.log (tail 30) ---"; tail -n 30 ~/copy_trade_hub/hub.log; }
