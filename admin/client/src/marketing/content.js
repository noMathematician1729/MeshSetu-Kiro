export const capabilities = [
  { number: '01', title: 'Offline BLE relay', text: 'An application-layer, store-and-forward BLE overlay lets participating phones extend the path.', tone: 'red' },
  { number: '02', title: 'Structured SOS + priority', text: 'Incident type, urgency, hazards, zone, and evidence travel ahead of lower-priority traffic.', tone: 'yellow' },
  { number: '03', title: 'Short voice evidence', text: 'Bounded voice notes are compressed, chunked, relayed, and checked before playback.', tone: 'teal' },
  { number: '04', title: 'Scoped Rooms', text: 'Public alerts, zones, medical teams, and responders communicate through role-aware channels.', tone: 'cream' },
  { number: '05', title: 'Local intelligence', text: 'On-device speech-to-text and conservative triage support responders, with visible uncertainty.', tone: 'blue' },
  { number: '06', title: 'Control-room view', text: 'Operators can see priority, transcript state, zone, hop count, latency, and voice completeness.', tone: 'orange' },
];

export const steps = [
  { number: '01', title: 'Join the local event', text: 'Enter a Mesh Code or scan a QR to load the event and Rooms available to your role.' },
  { number: '02', title: 'Create an SOS', text: 'Send a typed report or short voice clip. The SOS is saved locally before transmission.' },
  { number: '03', title: 'Relay nearby', text: 'Encrypted message fragments are stored and forwarded over BLE with bounded retries.' },
  { number: '04', title: 'Reach the control room', text: 'An optional gateway phone bridges verified incidents to a laptop on the local network.' },
];

export const safetyRules = [
  'A manual SOS is never blocked by speech or triage failure.',
  'SOS metadata always outranks chat and voice chunks.',
  'Uncertainty in transcription, triage, and location remains visible.',
  'Incomplete voice never prevents the structured SOS from being actionable.',
  'AI recommends; human authorities make the final decision.',
  'Messages expire, deduplicate, and stop relaying at their hop limit.',
];

export const demoStages = [
  { label: 'ORIGIN DEVICE', title: 'SOS saved locally', detail: 'The structured report is committed to the phone before it tries to travel.', color: 'red' },
  { label: 'NEARBY PHONE', title: 'BLE relay picks it up', detail: 'A participating device stores the encrypted object and carries it to the next hop.', color: 'yellow' },
  { label: 'GATEWAY DEVICE', title: 'Local handoff confirmed', detail: 'A gateway phone bridges the verified incident to the control-room dashboard.', color: 'teal' },
  { label: 'CONTROL ROOM', title: 'Responder sees the signal', detail: 'Priority, zone uncertainty, hop count, and delivery state become actionable context.', color: 'blue' },
];
