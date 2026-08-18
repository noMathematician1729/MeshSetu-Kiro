const state = {
  events: new Map(),
  selectedId: null,
  filter: 'all',
};

const priorityMeta = {
  p0Critical: { label: 'P0', className: 'critical' },
  p1High: { label: 'P1', className: 'high' },
  p2Normal: { label: 'P2', className: 'normal' },
  p3Bulk: { label: 'P3', className: 'bulk' },
};

const listElement = document.getElementById('incident-list');
const detailElement = document.getElementById('detail-content');
const emptyDetailElement = document.getElementById('empty-detail');
const connectionElement = document.querySelector('.live-status');
const connectionDot = document.getElementById('connection-dot');
const connectionLabel = document.getElementById('connection-label');

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  }[character]));
}

function priorityFor(event) {
  return priorityMeta[event.priority] || { label: '—', className: 'bulk' };
}

function readableType(event) {
  return (event.incident_type || 'unknown signal').replaceAll('_', ' ');
}

function formatTime(value) {
  if (!value) return 'time unavailable';
  const date = new Date(typeof value === 'number' ? value : Date.parse(value));
  if (Number.isNaN(date.getTime())) return 'time unavailable';
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function formatLocation(event) {
  if (event.latitude == null || event.longitude == null) return 'Location unavailable';
  return `${Number(event.latitude).toFixed(4)}, ${Number(event.longitude).toFixed(4)}`;
}

function sortedEvents() {
  const priorityRank = { p0Critical: 0, p1High: 1, p2Normal: 2, p3Bulk: 3 };
  return [...state.events.values()].sort((a, b) => {
    const priority = (priorityRank[a.priority] ?? 9) - (priorityRank[b.priority] ?? 9);
    if (priority !== 0) return priority;
    return String(b.updated_at || b.received_at || b.event_id).localeCompare(String(a.updated_at || a.received_at || a.event_id));
  });
}

function setConnection(status) {
  connectionElement.classList.toggle('is-live', status === 'live');
  connectionElement.classList.toggle('is-offline', status === 'offline');
  connectionLabel.textContent = status === 'live' ? 'live relay' : status === 'offline' ? 'reconnecting' : 'connecting';
}

function renderMetrics(events) {
  const critical = events.filter((event) => event.priority === 'p0Critical').length;
  const latest = events[0];
  document.getElementById('metric-critical').textContent = critical;
  document.getElementById('metric-active').textContent = events.length;
  document.getElementById('metric-hops').textContent = latest?.hops ?? '—';
  document.getElementById('metric-latency').textContent = latest?.relay_latency_ms == null ? '—' : `${latest.relay_latency_ms}ms`;
  document.getElementById('incident-count').textContent = events.length;
  document.getElementById('last-updated').textContent = `Last update ${latest ? formatTime(latest.updated_at || latest.received_at) : '—'}`;
}

function renderList() {
  const events = sortedEvents().filter((event) => state.filter === 'all' || event.priority === state.filter);
  renderMetrics(sortedEvents());
  if (events.length === 0) {
    listElement.innerHTML = `<div class="empty-queue">No signals match this view.<br /><span>Incoming SOS traffic will appear here as the gateway receives it.</span></div>`;
    return;
  }
  listElement.innerHTML = events.map((event) => {
    const priority = priorityFor(event);
    const selected = event.event_id === state.selectedId ? ' is-selected' : '';
    const stateLabel = event.audio_state === 'complete' ? 'evidence ready' : event.audio_state === 'queued' ? 'evidence queued' : 'structured SOS';
    return `<article class="incident-card${selected}" data-event-id="${escapeHtml(event.event_id)}" tabindex="0" role="button" aria-label="Open ${escapeHtml(readableType(event))} incident">
      <span class="incident-card__priority incident-card__priority--${priority.className}">${priority.label}</span>
      <div class="incident-card__main">
        <strong>${escapeHtml(readableType(event))}</strong>
        <span>${escapeHtml(event.transcript || 'No transcript attached')}</span>
        <small>${escapeHtml(event.zone || 'zone unknown')} · ${escapeHtml(formatTime(event.updated_at || event.received_at))}</small>
      </div>
      <span class="incident-card__state${event.audio_state ? '' : ' incident-card__state--muted'}">${escapeHtml(stateLabel)}</span>
    </article>`;
  }).join('');
  listElement.querySelectorAll('.incident-card').forEach((card) => {
    card.addEventListener('click', () => selectEvent(card.dataset.eventId));
    card.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); selectEvent(card.dataset.eventId); }
    });
  });
}

function selectEvent(eventId) {
  state.selectedId = eventId;
  const event = state.events.get(eventId);
  if (!event) return;
  const priority = priorityFor(event);
  document.getElementById('detail-title').textContent = readableType(event);
  document.getElementById('detail-index').textContent = priority.label;
  emptyDetailElement.hidden = true;
  detailElement.hidden = false;
  detailElement.innerHTML = `<div class="detail-hero">
    <div class="detail-hero__type"><span>${priority.label} / ${escapeHtml(event.audio_state || 'structured')}</span><span>${escapeHtml(formatTime(event.updated_at || event.received_at))}</span></div>
    <h3>${escapeHtml(event.transcript || 'No transcript attached')}</h3>
    <p>Received through the local BLE relay network. This record is available to the control room for triage and response coordination.</p>
  </div>
  <div class="detail-grid">
    <div class="detail-field"><small>Zone</small><strong>${escapeHtml(event.zone || 'Unknown')}</strong></div>
    <div class="detail-field"><small>Room</small><strong>${escapeHtml(event.room || 'Unassigned')}</strong></div>
    <div class="detail-field"><small>Coordinates</small><strong>${escapeHtml(formatLocation(event))}</strong></div>
    <div class="detail-field"><small>Accuracy</small><strong>${event.accuracy_m == null ? '—' : `${escapeHtml(event.accuracy_m)}m`}</strong></div>
    <div class="detail-field"><small>Voice evidence</small><strong>${escapeHtml(event.audio_state || 'Not attached')}</strong></div>
    <div class="detail-field"><small>Event ID</small><strong>${escapeHtml(String(event.event_id).slice(0, 12))}</strong></div>
  </div>
  <div class="relay-path">
    <div class="relay-path__title"><span>Relay path</span><span>${escapeHtml(event.hops ?? 0)} hops · ${event.relay_latency_ms == null ? 'latency unknown' : `${escapeHtml(event.relay_latency_ms)}ms`}</span></div>
    <div class="relay-line" aria-label="Source phone through relay nodes to gateway"><span class="relay-node"><i></i><span>source</span></span><span class="relay-node"><i></i><span>relay 01</span></span><span class="relay-node"><i></i><span>relay 02</span></span><span class="relay-node"><i></i><span>gateway</span></span></div>
  </div>`;
  renderList();
}

function applySnapshot(events) {
  (Array.isArray(events) ? events : []).forEach((event) => {
    if (event?.event_id) state.events.set(event.event_id, event);
  });
  renderList();
  if (state.selectedId && state.events.has(state.selectedId)) selectEvent(state.selectedId);
}

async function loadEvents() {
  try {
    const response = await fetch('/api/events', { headers: { accept: 'application/json' } });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    applySnapshot(await response.json());
  } catch (error) {
    document.getElementById('queue-state').textContent = 'Gateway API unavailable · waiting for local relay traffic';
  }
}

function connect() {
  setConnection('connecting');
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const socket = new WebSocket(`${protocol}//${location.host}/ws`);
  socket.onopen = () => { setConnection('live'); document.getElementById('queue-state').innerHTML = 'Listening for relay traffic <span class="loading-rule" aria-hidden="true"></span>'; };
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.type === 'snapshot') applySnapshot(message.data);
    if (message.type === 'event') applySnapshot([message.data]);
  };
  socket.onclose = () => { setConnection('offline'); window.setTimeout(connect, 3000); };
  socket.onerror = () => socket.close();
}

document.getElementById('priority-filter').addEventListener('change', (event) => {
  state.filter = event.target.value;
  renderList();
});
document.getElementById('refresh-button').addEventListener('click', loadEvents);

loadEvents();
connect();
