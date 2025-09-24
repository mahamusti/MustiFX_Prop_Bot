from fastapi import FastAPI, Request, Header, HTTPException
from sse_starlette.sse import EventSourceResponse
from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict
from datetime import datetime, timezone
import asyncio, uuid

MASTER_TOKEN = "CHANGE_ME_SUPER_SECRET"
app = FastAPI(title="MustiFX Copy-Trade Signal Hub")

class Signal(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    symbol: str
    direction: str
    timeframe: str
    expiry: str
    stake_model: str = "fixed"
    stake_value: float = 1.0
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    comment: Optional[str] = None

    @validator("direction")
    def _validate_dir(cls, v):
        v = v.upper()
        if v not in ("CALL","PUT"):
            raise ValueError("direction must be CALL or PUT")
        return v

signals: List[Dict] = []
listeners: List[asyncio.Queue] = []

def notify(sig: Dict):
    for q in listeners:
        try: q.put_nowait(sig)
        except Exception: pass

@app.post("/publish")
async def publish(sig: Signal, authorization: str = Header(default="")):
    if authorization.replace("Bearer ","").strip() != MASTER_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")
    s = sig.dict()
    signals.append(s)
    if len(signals) > 1000:
        del signals[:500]
    notify(s)
    return {"status":"ok","id":s["id"]}

@app.get("/recent")
async def recent(limit: int = 50):
    return {"signals": signals[-limit:]}

@app.get("/stream")
async def stream(request: Request):
    q: asyncio.Queue = asyncio.Queue()
    listeners.append(q)
    async def gen():
        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    item = await asyncio.wait_for(q.get(), timeout=15.0)
                except asyncio.TimeoutError:
                    yield {"event":"keepalive","data":"ping"}
                else:
                    yield {"event":"signal","data": item}
        finally:
            listeners.remove(q)
    return EventSourceResponse(gen())
