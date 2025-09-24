# ui_server.py — MustiFX Copy Hub Dashboard (with PIN login + table view)
from flask import Flask, request, jsonify, Response, redirect, make_response
from flask_cors import CORS
from itsdangerous import TimestampSigner, BadSignature
import requests, os, json, time

HUB = os.environ.get("HUB_URL", "http://127.0.0.1:8008")
MASTER_TOKEN = os.environ.get("MASTER_TOKEN", "")
DASH_PIN = os.environ.get("DASH_PIN", "")   # set with:  export DASH_PIN=1234

app = Flask(__name__)
CORS(app)
signer = TimestampSigner(os.environ.get("SECRET_KEY","mustifx-secret"))

def _headers():
    h = {"Content-Type": "application/json"}
    if MASTER_TOKEN:
        h["Authorization"] = f"Bearer {MASTER_TOKEN}"
    return h

def authed(req):
    if not DASH_PIN:
        return True
    cookie = req.cookies.get("mf_auth","")
    if not cookie: return False
    try:
        raw = signer.unsign(cookie, max_age=60*60*12)  # 12h session
        return raw.decode() == "ok"
    except BadSignature:
        return False

@app.get("/login")
def login_page():
    if not DASH_PIN:
        return redirect("/")
    return Response("""
<!doctype html><html><head><meta name=viewport content="width=device-width,initial-scale=1">
<title>Login</title><style>body{font-family:system-ui;background:#0b1220;color:#e7ecf3;margin:40px}
input,button{padding:12px;border-radius:10px;border:1px solid #253355;background:#0f1729;color:#e7ecf3}
button{background:#2563eb;border:0;font-weight:700}</style></head>
<body><h2>🔐 MustiFX Dashboard Login</h2>
<p class=muted>Enter PIN to continue.</p>
<input id=p placeholder="PIN" type=password>
<button onclick="go()">Login</button>
<script>
async function go(){
  const r=await fetch('/do_login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({pin:document.getElementById('p').value})});
  if(r.status==200) location.href='/'; else alert('Wrong PIN');
}
</script></body></html>""", mimetype="text/html")

@app.post("/do_login")
def do_login():
    if not DASH_PIN: return ("ok",200)
    pin = (request.get_json() or {}).get("pin","")
    if pin == DASH_PIN:
        resp = make_response("ok")
        resp.set_cookie("mf_auth", signer.sign(b"ok"), max_age=60*60*12, httponly=True, samesite="Lax")
        return resp
    return ("no",401)

# ---------------- Proxy API (guarded) ----------------
@app.get("/api/recent")
def api_recent():
    if not authed(request): return redirect("/login")
    r = requests.get(f"{HUB}/recent", timeout=10)
    return (r.text, r.status_code, {"Content-Type": "application/json"})

@app.get("/api/pairs")
def api_pairs():
    if not authed(request): return redirect("/login")
    try:
        r = requests.get(f"{HUB}/pairs", timeout=10)
        return (r.text, r.status_code, {"Content-Type": "application/json"})
    except:
        r = requests.get(f"{HUB}/config", timeout=10)
        cfg = r.json()
        return jsonify({"allowed_symbols": cfg.get("allowed_symbols", [])})

@app.post("/api/pairs")
def api_pairs_set():
    if not authed(request): return redirect("/login")
    r = requests.post(f"{HUB}/pairs", data=json.dumps(request.json or {}), headers=_headers(), timeout=10)
    return (r.text, r.status_code, {"Content-Type": "application/json"})

@app.get("/api/config")
def api_config_get():
    if not authed(request): return redirect("/login")
    r = requests.get(f"{HUB}/config", timeout=10)
    return (r.text, r.status_code, {"Content-Type": "application/json"})

@app.post("/api/config")
def api_config_set():
    if not authed(request): return redirect("/login")
    r = requests.post(f"{HUB}/config", data=json.dumps(request.json or {}), headers=_headers(), timeout=10)
    return (r.text, r.status_code, {"Content-Type": "application/json"})

@app.post("/api/publish")
def api_publish():
    if not authed(request): return redirect("/login")
    r = requests.post(f"{HUB}/publish", data=json.dumps(request.json or {}), headers=_headers(), timeout=10)
    return (r.text, r.status_code, {"Content-Type": "application/json"})

# ---------------- Dashboard UI ----------------
INDEX_HTML = r"""
<!doctype html><html><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>MustiFX Hub</title>
<style>
body{font-family:system-ui,Arial;background:#0b1220;color:#e7ecf3;margin:16px}
h1{font-size:20px;margin:4px 0 12px}
.row{display:flex;gap:12px;flex-wrap:wrap}
.card{background:#121a2b;border:1px solid #1f2a44;border-radius:12px;padding:14px;flex:1;min-width:280px}
input,select{width:100%;padding:10px;border-radius:8px;border:1px solid #253355;background:#0f1729;color:#e7ecf3}
button{padding:10px 14px;border:0;border-radius:10px;background:#2563eb;color:#fff;font-weight:600}
.muted{color:#9fb0d2;font-size:12px}
.table{width:100%;border-collapse:collapse;margin-top:8px}
.table th,.table td{border-bottom:1px solid #233457;padding:8px;text-align:left;font-size:13px}
.badge{padding:2px 8px;border-radius:999px;border:1px solid #33508c}
.ok{color:#22c55e} .warn{color:#fbbf24} .err{color:#f97316}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
@media(max-width:680px){.grid{grid-template-columns:1fr}}
</style></head>
<body>
<h1>⚡ MustiFX Copy-Trade Hub — Dashboard</h1>

<div class=row>
  <div class=card style="max-width:560px">
    <h3>Allowed Pairs</h3>
    <div class=grid>
      <input id=pairs placeholder='["XAUUSD","EURUSD","GBPUSD"]'>
      <button onclick=savePairs()>Save</button>
    </div>
    <div id=pairs_now class=muted style="margin-top:8px"></div>
  </div>

  <div class=card style="max-width:560px">
    <h3>Sessions (UTC)</h3>
    <div class=grid>
      <input id=london placeholder='London 07:00-12:00'>
      <input id=ny placeholder='NY 13:00-20:00'>
    </div>
    <button style="margin-top:8px" onclick=saveSessions()>Save</button>
    <div id=sessions_now class=muted style="margin-top:8px"></div>
  </div>
</div>

<div class=row>
  <div class=card>
    <h3>Per-Pair Limits</h3>
    <div class=grid>
      <input id=pair_name placeholder="Symbol e.g. XAUUSD">
      <select id=stake_model><option>percent</option><option>fixed</option></select>
      <input id=stake_value type=number step=0.1 placeholder="Stake value">
      <input id=max_per_window type=number step=1 placeholder="Max per window">
      <input id=window_sec type=number step=1 placeholder="Window sec">
    </div>
    <button style="margin-top:8px" onclick=savePerPair()>Save Per-Pair</button>
    <div id=perpair_now class=muted style="margin-top:8px"></div>
  </div>

  <div class=card>
    <h3>Push Test Signal</h3>
    <div class=grid>
      <input id=t_symbol placeholder="Symbol (XAUUSD)">
      <select id=t_dir><option>CALL</option><option>PUT</option></select>
      <select id=t_tf><option>1m</option><option>5m</option></select>
      <select id=t_exp><option>1m</option><option>5m</option></select>
      <input id=t_stake type=number step=0.1 placeholder="Stake value">
      <input id=t_comment placeholder="Comment">
    </div>
    <button style="margin-top:8px" onclick=sendTest()>Publish</button>
    <div id=pub_out class=muted style="margin-top:8px"></div>
  </div>
</div>

<div class=card style="margin-top:12px">
  <h3>Live Signals</h3>
  <button onclick=loadRecent()>Refresh</button>
  <table class=table id=tbl>
    <thead><tr><th>Time</th><th>Symbol</th><th>Dir</th><th>TF</th><th>Exp</th><th>Stake</th><th>Comment</th></tr></thead>
    <tbody></tbody>
  </table>
</div>

<script>
async function jget(u){const r=await fetch(u);return await r.json()}
async function jpost(u,b){const r=await fetch(u,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b||{})});try{return await r.json()}catch{ return {} }}

async function loadConfig(){
  const cfg=await jget('/api/config');
  document.getElementById('pairs_now').innerText='Now: '+(cfg.allowed_symbols||[]).join(', ');
  const s=(cfg.sessions||[]).map(x=>x.name+': '+x.start+'-'+x.end).join(' | ');
  document.getElementById('sessions_now').innerText='Sessions: '+(s||'none');
  document.getElementById('perpair_now').innerText='Per-pair: '+JSON.stringify(cfg.per_pair||{});
}

async function savePairs(){
  try{const arr=JSON.parse(document.getElementById('pairs').value);await jpost('/api/pairs',{allowed_symbols:arr});alert('Saved');loadConfig()}catch(e){alert('Invalid JSON')}
}
async function saveSessions(){
  const L=document.getElementById('london').value.trim(), N=document.getElementById('ny').value.trim();
  function toObj(n,s){if(!s)return null;const[a,b]=s.split('-');return {name:n,start:a,end:b,tz:'UTC'}}
  await jpost('/api/config',{sessions:[toObj('London',L),toObj('NY',N)].filter(Boolean)});alert('Saved');loadConfig()
}
async function savePerPair(){
  const p=document.getElementById('pair_name').value.trim(); if(!p) return alert('Symbol?');
  const payload={per_pair:{}}; payload.per_pair[p]={stake_model:document.getElementById('stake_model').value, stake_value:parseFloat(document.getElementById('stake_value').value||'0'), max_per_window:parseInt(document.getElementById('max_per_window').value||'0'), window_sec:parseInt(document.getElementById('window_sec').value||'0')};
  await jpost('/api/config',payload); alert('Saved'); loadConfig()
}
async function sendTest(){
  const body={symbol:document.getElementById('t_symbol').value||'XAUUSD',direction:document.getElementById('t_dir').value,timeframe:document.getElementById('t_tf').value,expiry:document.getElementById('t_exp').value,stake_value:parseFloat(document.getElementById('t_stake').value||'1.0'),comment:document.getElementById('t_comment').value||'UI test'};
  const out=await jpost('/api/publish',body); document.getElementById('pub_out').innerText=JSON.stringify(out); loadRecent()
}
function esc(s){return (s??'').toString().replace(/[&<>]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[m]))}
async function loadRecent(){
  const js=await jget('/api/recent'); const tb=document.querySelector('#tbl tbody'); tb.innerHTML='';
  (js.signals||[]).slice(-100).reverse().forEach(x=>{
    const tr=document.createElement('tr');
    const t=new Date(x.created_at||Date.now()).toISOString().slice(11,19);
    tr.innerHTML=`<td>${t}</td><td>${esc(x.symbol)}</td><td><span class="badge">${esc(x.direction)}</span></td><td>${esc(x.timeframe)}</td><td>${esc(x.expiry)}</td><td>${esc(x.stake_value)}</td><td>${esc(x.comment||'')}</td>`;
    tb.appendChild(tr);
  });
}
loadConfig(); loadRecent();
</script></body></html>
"""

@app.get("/")
def index():
    if not authed(request): return redirect("/login")
    return Response(INDEX_HTML, mimetype="text/html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
