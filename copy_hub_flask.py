import json, os, time
from flask import Flask, request, jsonify

app = Flask(__name__)
LOG_FILE = "signals.json"

@app.route("/publish", methods=["POST"])
def publish():
    sig = request.json
    if not sig:
        return jsonify({"status": "error", "msg": "No signal"}), 400

    # add timestamp
    sig["created_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    # read existing signals
    if os.path.exists(LOG_FILE):
        try:
            with open(LOG_FILE, "r") as f:
                data = json.load(f)
        except Exception:
            data = []
    else:
        data = []

    data.append(sig)

    with open(LOG_FILE, "w") as f:
        json.dump(data, f, indent=2)

    return jsonify({"status": "ok", "signal": sig})

@app.route("/recent", methods=["GET"])
def recent():
    if not os.path.exists(LOG_FILE):
        return jsonify({"signals": []})
    try:
        with open(LOG_FILE, "r") as f:
            data = json.load(f)
    except Exception:
        data = []
    return jsonify({"signals": data[-20:]})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8008)
