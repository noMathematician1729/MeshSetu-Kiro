"""MeshSetu local control-room dashboard (Bible §15.2).

Run: uvicorn main:app --host 0.0.0.0 --port 8000
No internet access required — gateway phone and this laptop just need to
share a local Wi-Fi network/hotspot.
"""

import os

from fastapi import FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from typing import Optional

app = FastAPI(title="MeshSetu Local Control Room")
clients: set[WebSocket] = set()
latest: dict[str, dict] = {}

# Demo-only shared secret between the gateway phone and this laptop.
# Bible §9.4/§16: never a production credential, override via env for a demo.
DEMO_KEY = os.environ.get("MESHSETU_DEMO_KEY", "change-me")


class Event(BaseModel):
    event_id: str
    priority: str = "unknown"
    incident_type: str = "unknown"
    transcript: Optional[str] = None
    zone: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    accuracy_m: Optional[float] = None
    location_captured_at_ms: Optional[int] = None
    room: Optional[str] = None
    hops: int = 0
    relay_latency_ms: Optional[int] = None
    voice_clip_id: Optional[str] = None
    audio_state: Optional[str] = None


@app.post("/api/events")
async def ingest(event: Event, x_meshsetu_demo_key: str = Header(default="")):
    if x_meshsetu_demo_key != DEMO_KEY:
        raise HTTPException(401, "bad demo key")
    update = event.model_dump(exclude_unset=True)
    latest[event.event_id] = {**latest.get(event.event_id, {}), **update}
    dead = []
    for ws in clients:
        try:
            await ws.send_json({"type": "event", "data": latest[event.event_id]})
        except Exception:
            dead.append(ws)
    for ws in dead:
        clients.discard(ws)
    return {"ok": True}


@app.get("/api/events")
def list_events():
    return list(latest.values())


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    clients.add(ws)
    await ws.send_json({"type": "snapshot", "data": list(latest.values())})
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        clients.discard(ws)


@app.get("/")
def index():
    return FileResponse(os.path.join(os.path.dirname(__file__), "static", "index.html"))


app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")
