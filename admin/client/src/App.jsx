import { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { authToken, getEvents, getPublicEvent, getVoice, login, openStream, setStatus, setToken } from './api'
import MarketingApp from './marketing/App.jsx'
import marketingStyles from './marketing/styles.css?inline'

const priorityRank = { p0Critical: 0, p1High: 1, p2Normal: 2, p3Bulk: 3 }
const statusLabels = { new: 'new', acknowledged: 'acknowledged', dispatched: 'dispatched', resolved: 'resolved' }
const controlRoomPath = '/control-room'
const formatTimestamp = value => { const date = Number(value) ? new Date(Number(value)) : null; return date && !Number.isNaN(date.valueOf()) ? new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(date) : 'Time unavailable' }
const mapUrlFor = (latitude, longitude) => {
  if (latitude == null || longitude == null || latitude === '' || longitude === '') return null
  const lat = Number(latitude)
  const lon = Number(longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null
  const span = 0.01
  return `https://www.openstreetmap.org/export/embed.html?bbox=${lon - span}%2C${lat - span}%2C${lon + span}%2C${lat + span}&layer=mapnik&marker=${lat}%2C${lon}`
}
const isolatedMarketingStyles = marketingStyles
  .replace(/:root/g, ':host')
  .replace(/\bhtml\b/g, '.marketing-root')
  .replace(/\bbody\b/g, '.marketing-root')

function Login({ onLogin }) { const [email, setEmail] = useState('operator@meshsetu.local'); const [password, setPassword] = useState('meshsetu-demo'); const [error, setError] = useState(''); const submit = async e => { e.preventDefault(); try { await login(email, password); onLogin() } catch (err) { setError(err.message) } }; return <main className="login-shell"><div className="login-card"><div className="brand"><i /> MESHSETU</div><span className="eyebrow">AUTHORITY ACCESS / LOCAL CONTROL ROOM</span><h1>Operator<br /><em>sign in.</em></h1><form onSubmit={submit}><label>Operator email<input value={email} onChange={e => setEmail(e.target.value)} type="email" /></label><label>Access password<input value={password} onChange={e => setPassword(e.target.value)} type="password" /></label>{error && <p className="error">{error}</p>}<button className="primary">Enter control room ↗</button></form><small>Local server · no internet required</small></div></main> }

function Badge({ children, tone = '' }) { return <span className={`badge ${tone}`}>{children}</span> }

function MarketingPage() {
  const hostRef = useRef(null)
  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    const shadow = host.shadowRoot ?? host.attachShadow({ mode: 'open' })
    shadow.innerHTML = ''
    const style = document.createElement('style')
    style.textContent = isolatedMarketingStyles
    const mount = document.createElement('div')
    shadow.append(style, mount)
    const root = createRoot(mount)
    root.render(<div className="marketing-root"><MarketingApp /></div>)
    return () => root.unmount()
  }, [])
  return <div className="marketing-shell"><div ref={hostRef} /></div>
}

function ControlRoomApp() { const [signedIn, setSignedIn] = useState(Boolean(authToken())); return signedIn ? <ControlRoom onLogout={() => { setToken(''); setSignedIn(false) }} /> : <Login onLogin={() => setSignedIn(true)} /> }
function PublicIncidentPage({ eventId }) {
  const [event, setEvent] = useState(null); const [error, setError] = useState('');
  useEffect(() => { getPublicEvent(eventId).then(setEvent).catch(err => setError(err.message)) }, [eventId])
  if (error) return <main className="public-incident"><span className="eyebrow">MESHSETU / SOS DETAIL</span><h1>Incident unavailable</h1><p>{error}</p></main>
  if (!event) return <main className="public-incident"><span className="eyebrow">MESHSETU / SOS DETAIL</span><h1>Loading emergency details…</h1></main>
  const coordinates = event.latitude != null && event.longitude != null ? `${Number(event.latitude).toFixed(5)}, ${Number(event.longitude).toFixed(5)}` : 'Unavailable'
  return <main className="public-incident"><header><div><span className="crumb">MESHSETU <b>/</b> LIVE SOS</span><h2>{event.incident_type || 'Emergency SOS'}</h2></div><Badge tone={event.status === 'resolved' ? '' : 'critical'}>{event.status || 'new'}</Badge></header><section className="public-incident-card"><span className="eyebrow">LIVE INCIDENT / {event.event_id}</span><p className="public-transcript">“{event.transcript || 'No transcript attached to this SOS.'}”</p><div className="public-facts"><Fact label="Reporter" value={event.reporter_name || event.reporter_uid || 'Unavailable'} /><Fact label="Phone" value={event.reporter_phone || 'Unavailable'} /><Fact label="Priority" value={event.priority || 'Unavailable'} /><Fact label="Zone" value={event.zone || 'Unavailable'} /><Fact label="Location" value={coordinates} /><Fact label="Relay hops" value={event.hops ?? 'Unavailable'} /><Fact label="Received" value={formatTimestamp(event.received_at_ms || event.created_at_ms)} /><Fact label="Response status" value={event.status || 'new'} /><Fact label="Blood group" value={event.reporter_blood_group || 'Unavailable'} /><Fact label="Emergency contact" value={event.reporter_primary_contact || 'Unavailable'} /></div><IncidentMap latitude={event.latitude} longitude={event.longitude} /><p className="public-note">This is the live SOS detail page linked from your emergency notification.</p></section></main>
}
function App() { const path = window.location.pathname; if (path.startsWith('/sos/')) return <PublicIncidentPage eventId={decodeURIComponent(path.slice('/sos/'.length))} />; return path.startsWith(controlRoomPath) ? <ControlRoomApp /> : <MarketingPage /> }

function ControlRoom({ onLogout }) { const [events, setEvents] = useState([]); const [selectedId, setSelectedId] = useState(''); const [connection, setConnection] = useState('connecting'); const [error, setError] = useState(''); const [filter, setFilter] = useState('all'); const [voiceUrl, setVoiceUrl] = useState(''); const [alertQueue, setAlertQueue] = useState([]);
  const dismissAlert = () => setAlertQueue(q => q.slice(1));
  const load = () => getEvents().then(next => { setEvents(next.sort((a, b) => (priorityRank[a.priority] ?? 9) - (priorityRank[b.priority] ?? 9))); setError('') }).catch(err => setError(err.message))
  useEffect(() => { load(); const socket = openStream(message => { if (message.type === 'snapshot') setEvents(message.data.sort((a, b) => (priorityRank[a.priority] ?? 9) - (priorityRank[b.priority] ?? 9))); if (message.type === 'incident' || message.type === 'voice' || message.type === 'event') { setEvents(current => { const next = new Map(current.map(e => [e.event_id, e])); const isNew = !next.has(message.data.event_id); next.set(message.data.event_id, { ...next.get(message.data.event_id), ...message.data }); if (isNew && (message.data.priority === 'p0Critical' || message.data.incident_type === 'ceal_compact_sos')) { setAlertQueue(q => [...q, message.data]); try { new Audio('data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1rZ2loamZnanJ0c3Z7hImLjY6Sk5eYm5ydoKGkpaipq62vsLK0tre5u72+wMLExcfJysvNz9DR09TV19jZ29ze3+Dh4+Tl5ufp6uvs7e7v8PHy8/T19vf4+fr7/P3+').play().catch(() => {}) } catch {} } return [...next.values()].sort((a, b) => (priorityRank[a.priority] ?? 9) - (priorityRank[b.priority] ?? 9)) }) } }, setConnection); return () => socket.close() }, [])
  const visible = events.filter(e => filter === 'all' || e.status === filter); const selected = visible.find(e => e.event_id === selectedId) || visible[0]; const critical = events.filter(e => e.priority === 'p0Critical' && e.status !== 'resolved').length; const verified = events.filter(e => e.decrypt_status === 'verified').length; const update = async (status) => { try { const next = await setStatus(selected.event_id, status); setEvents(current => current.map(e => e.event_id === next.event_id ? { ...e, ...next } : e)) } catch (err) { setError(err.message) } }; const play = async () => { try { setVoiceUrl(await getVoice(selected.event_id)) } catch (err) { setError(err.message) } }
  return <div className="app">{alertQueue.length > 0 && <SosAlertPopup alert={alertQueue[0]} onDismiss={dismissAlert} onSelect={() => { setSelectedId(alertQueue[0].event_id); dismissAlert() }} />}<aside><div className="brand"><i /> MESHSETU</div><span className="caption">LOCAL CONTROL ROOM</span><div className="site"><b>DEMO01</b><small>active event namespace</small><Badge tone="live">● ONLINE</Badge></div><nav><span className="nav-label">Response layer</span><button className="active">⊙ Overview</button><button>▦ Incidents <b>{events.length}</b></button><button>≋ Mesh network</button><button>⌁ Operators</button></nav><div className="side-bottom"><div className="system"><span>● SYSTEM STATUS</span><strong>Gateway linked</strong><small>Node server / PostgreSQL</small></div><button className="logout" onClick={onLogout}>Sign out ↗</button></div></aside><main className="main"><header><div><span className="crumb">MESHSETU <b>/</b> CONTROL ROOM</span><h2>Live situation <em>room.</em></h2></div><div className="header-actions"><Badge tone={connection === 'live' ? 'live' : 'warn'}>● {connection === 'live' ? 'LIVE SYNC' : connection.toUpperCase()}</Badge><button onClick={load}>↻ Refresh</button></div></header><div className="content">{error && <div className="notice">! {error}<button onClick={load}>Retry</button></div>}<div className="metrics"><Metric label="Open incidents" value={events.filter(e => e.status !== 'resolved').length} note="active response queue" /><Metric label="Critical priority" value={critical} tone="red" note="human review required" /><Metric label="Verified objects" value={verified} tone="light" note="AEAD + protobuf passed" /><Metric label="Gateway sync" value={connection === 'live' ? 'LIVE' : 'WAIT'} tone="light" note="local LAN transport" /></div><section className="grid"><div className="panel queue"><div className="panel-head"><div><span className="eyebrow">LIVE INCIDENTS / {String(visible.length).padStart(2, '0')}</span><h3>Response queue</h3></div><select value={filter} onChange={e => setFilter(e.target.value)}><option value="all">All states</option><option value="new">New</option><option value="acknowledged">Acknowledged</option><option value="dispatched">Dispatched</option><option value="resolved">Resolved</option></select></div>{visible.length ? visible.map(event => <button className={`incident ${selected?.event_id === event.event_id ? 'selected' : ''}`} key={event.event_id} onClick={() => setSelectedId(event.event_id)}><span className={`priority ${event.priority}`}>{event.priority?.replace('p', 'P').replace('Critical', '')}</span><span className="incident-copy"><strong>{event.incident_type || 'Unknown incident'}</strong><small>{formatTimestamp(event.received_at_ms || event.created_at_ms)} · {event.zone || 'Zone unknown'} · {event.hops ?? 0} hops · {event.transcript || 'No transcript'}</small></span><Badge tone={event.status === 'new' ? 'critical' : ''}>{statusLabels[event.status] || event.status}</Badge></button>) : <div className="empty">No incidents match this filter.</div>}</div><Detail event={selected} onStatus={update} onPlay={play} voiceUrl={voiceUrl} /></section><section className="network panel"><div className="panel-head"><div><span className="eyebrow">TRANSPORT OBSERVABILITY</span><h3>Mesh pulse</h3></div><Badge tone="live">● GATEWAY ONLINE</Badge></div><div className="route"><span className="node source">A<br /><small>SENDER</small></span><i /><span className="node">B<br /><small>RELAY</small></span><i /><span className="node gateway">G<br /><small>GATEWAY</small></span><i /><span className="node">CR<br /><small>CONTROL ROOM</small></span></div><div className="network-foot"><span>Relay backlog <b>{events.filter(e => e.audio_state === 'queued').length}</b></span><span>Verified packet stream <b>{verified}</b></span><span>Database <b>CONNECTED</b></span></div></section><footer>MES​HSETU / OFFLINE-FIRST DISASTER RESPONSE <span>APPLICATION-LAYER BLE OVERLAY · PROTOTYPE BUILD</span></footer></div></main></div> }
function Metric({ label, value, note, tone = '' }) { return <div className={`metric ${tone}`}><span>{label}</span><strong>{value}</strong><small>— {note}</small></div> }
function Detail({ event, onStatus, onPlay, voiceUrl }) {
  if (!event) return <div className="panel detail empty">Select a signal to inspect its verified relay object.</div>
  return <div className="panel detail">
    <div className="panel-head"><div><span className="eyebrow">SELECTED INCIDENT</span><h3>Received {formatTimestamp(event.received_at_ms || event.created_at_ms)}</h3></div><Badge tone={event.decrypt_status === 'verified' ? 'live' : 'warn'}>{event.decrypt_status || 'unknown'}</Badge></div>
    <div className="detail-title"><span className={`big-priority ${event.priority}`}>{event.priority === 'p0Critical' ? '!' : '·'}</span><div><h4>{event.incident_type || 'Unknown incident'}</h4><small>{event.zone || 'Zone unknown'} · {event.room_id || event.room || 'No room'}</small></div></div>
    <div className="transcript"><span className="eyebrow">SIGNAL TRANSCRIPT</span><p>“{event.transcript || 'No transcript attached to this signal.'}”</p></div>
    <div className="facts"><Fact label="Reporter" value={event.reporter_name ? `${event.reporter_name}${event.reporter_phone ? ` · ${event.reporter_phone}` : ''}` : 'Unavailable'} /><Fact label="Emergency contact" value={event.reporter_primary_contact || 'Unavailable'} /><Fact label="Blood group" value={event.reporter_blood_group || 'Unavailable'} /><Fact label="Received" value={formatTimestamp(event.received_at_ms || event.created_at_ms)} /><Fact label="Relay hops" value={event.hops ?? '—'} /><Fact label="Origin latency" value={event.relay_latency_ms ? `${event.relay_latency_ms} ms` : '—'} /><Fact label="Voice evidence" value={event.audio_state || 'n/a'} /><Fact label="Triage confidence" value={event.triage_confidence == null ? 'unavailable' : `${Math.round(event.triage_confidence * 100)}%`} /><Fact label="Location" value={mapUrlFor(event.latitude, event.longitude) ? `${Number(event.latitude).toFixed(3)}, ${Number(event.longitude).toFixed(3)}` : 'Unavailable'} /><Fact label="Packet hash" value={event.packet_sha256 ? event.packet_sha256.slice(0, 12) : '—'} /></div>
    <IncidentMap latitude={event.latitude} longitude={event.longitude} />
    {event.audio_state === 'complete' && <div className="audio"><button onClick={onPlay}>▶ Play verified voice</button>{voiceUrl && <audio controls src={voiceUrl} />}</div>}
    <div className="actions"><span className="eyebrow">OPERATOR RESPONSE STATE</span><div>{Object.keys(statusLabels).map(status => <button className={event.status === status ? 'current' : ''} key={status} onClick={() => onStatus(status)}>{status}</button>)}</div></div>
    <div className="detail-foot">⌁ authenticated relay object <span>Human authority remains final</span></div>
  </div>
}
function IncidentMap({ latitude, longitude }) {
  const mapUrl = mapUrlFor(latitude, longitude)
  if (!mapUrl) return null
  return <section className="incident-map"><div className="incident-map-head"><span className="eyebrow">REPORTED LOCATION</span><span>{Number(latitude).toFixed(5)}, {Number(longitude).toFixed(5)}</span></div><iframe title="Reported SOS location" src={mapUrl} loading="lazy" referrerPolicy="no-referrer" /></section>
}
function Fact({ label, value }) { return <div><span>{label}</span><b>{value}</b></div> }
function SosAlertPopup({ alert, onDismiss, onSelect }) {
  useEffect(() => { const timer = setTimeout(onDismiss, 30000); return () => clearTimeout(timer) }, [alert?.event_id])
  const isCeal = alert.incident_type === 'ceal_compact_sos'
  const reporter = alert.reporter_name || (isCeal ? `UID ${alert.reporter_uid || 'unknown'}` : 'Unknown sender')
  return <div className="sos-alert-overlay" onClick={onSelect}><div className="sos-alert-card"><div className="sos-alert-icon">⚠</div><h2>EMERGENCY SOS RECEIVED</h2><p className="sos-alert-type">{isCeal ? 'CEAL-STYLE COMPACT ALERT' : alert.incident_type?.toUpperCase() || 'STRUCTURED SOS'}</p><p className="sos-alert-reporter">{reporter}{alert.reporter_phone ? ` · ${alert.reporter_phone}` : ''}</p><p className="sos-alert-location">Received {formatTimestamp(alert.received_at_ms || alert.created_at_ms)}</p>{alert.transcript && <p className="sos-alert-transcript">"{alert.transcript}"</p>}{alert.latitude != null && <p className="sos-alert-location">GPS: {Number(alert.latitude).toFixed(4)}, {Number(alert.longitude).toFixed(4)}</p>}<div className="sos-alert-actions"><button className="sos-alert-acknowledge" onClick={e => { e.stopPropagation(); onSelect() }}>View incident →</button><button className="sos-alert-dismiss" onClick={e => { e.stopPropagation(); onDismiss() }}>Dismiss</button></div><small>Auto-dismisses in 30 seconds · Click anywhere to inspect</small></div></div>
}
export default App
