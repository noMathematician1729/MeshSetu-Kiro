# MeshSetu Web Landing Page Structure

## 1. Page Purpose

This page introduces MeshSetu to hackathon judges, emergency-response stakeholders,
technical evaluators, and potential pilot partners. A visitor should understand the
problem, solution, operating model, and current prototype status in under two minutes.

This brief is based on `overview.md`, the MeshSetu Technical Development Bible v1.1,
and the repository's current implementation. Product-vision copy and current-build
claims are deliberately separated below.

The page should communicate one central idea:

> When conventional networks fail, nearby phones can still carry an emergency message
> toward help.

Primary conversion: **View the demo**  
Secondary conversion: **Explore how it works**  
Technical conversion: **Read the technical overview / View source**

Use real links when available. Until then, scroll CTAs to the relevant page section;
do not show dead buttons.

---

## 2. Message Hierarchy

### Product name

**MeshSetu**

### One-line description

**Offline emergency communication, relayed phone to phone.**

### Short explanation

MeshSetu is an Android-first emergency communication system that uses a
store-and-forward Bluetooth Low Energy overlay. It carries structured SOS messages,
short voice evidence, and scoped updates across nearby participating phones, even
when internet and cellular networks are unavailable.

### Three ideas to remember

1. **Works without internet:** Local emergency communication continues during a
   network outage.
2. **Every phone can extend the path:** Participating devices receive, store, and
   forward messages toward responders.
3. **SOS stays first:** Emergency metadata is prioritized over room chat and voice
   transfer, with graceful fallback when optional features fail.

---

## 3. Recommended Page Flow

### A. Header

Keep the navigation short and persistent.

- Logo: `MeshSetu`
- Links: `How It Works`, `Capabilities`, `Safety`, `Prototype`
- Primary CTA: `View Demo`

On mobile, use a compact menu and keep the demo CTA visible.

### B. Hero

**Eyebrow**  
`OFFLINE-FIRST DISASTER RESPONSE`

**Headline**  
`When networks go down, the message still gets through.`

**Supporting copy**  
`MeshSetu turns nearby Android phones into a store-and-forward emergency network,
carrying prioritized SOS messages toward responders without relying on internet or
cellular service.`

**Primary CTA**  
`View the demo`

**Secondary CTA**  
`See how it works`

**Proof strip**  
`No internet required` | `Phone-to-phone relay` | `SOS-first delivery` |
`Local control-room view`

**Hero visual direction**  
Show a clear, animated route from a citizen phone through one or two relay phones to
a gateway and local control-room dashboard. Use pulsing message packets and hop
states rather than a generic map or decorative phone mockup. The visual must make
store-and-forward behavior understandable without text.

### C. Problem

**Section label**  
`THE COMMUNICATION GAP`

**Heading**  
`Emergencies do not wait for connectivity.`

**Body**  
`Crowded venues and disaster zones can overwhelm or lose cellular and internet
coverage. People still need a way to report danger, responders need structured
information, and control rooms need a reliable local picture.`

Use three short problem cards:

- `Infrastructure can fail` - Internet and cellular service may be unavailable or
  congested.
- `Critical context gets lost` - Unstructured reports slow down assessment and
  response.
- `Responders need local visibility` - Incidents, zones, urgency, and delivery state
  must remain visible without a cloud dependency.

Avoid sensational disaster photography. Prefer an abstract network-outage diagram or
a restrained real-world venue visual with a technical overlay.

### D. How It Works

**Section label**  
`FROM SOS TO RESPONSE`

**Heading**  
`A local path to help, one device at a time.`

Present this as a four-step horizontal journey on desktop and a vertical sequence on
mobile.

1. **Join the local event**  
   `Enter a Mesh Code or scan a QR to load the event and the Rooms available to your
   role.`
2. **Create an SOS**  
   `Send a typed report or a short voice clip. The SOS is saved locally before
   transmission.`
3. **Relay across nearby phones**  
   `Encrypted message fragments are stored and forwarded over BLE. Duplicate
   suppression, expiry, and retries keep the flow bounded.`
4. **Reach the control room**  
   `An optional gateway phone bridges verified incidents to a laptop dashboard on a
   local network. Internet is not required.`

Add one persistent annotation to the diagram:

> Structured SOS first. Voice evidence and routine messages follow.

### E. Core Capabilities

**Section label**  
`BUILT FOR GRACEFUL DEGRADATION`

**Heading**  
`The essential message survives.`

Use six capability cards. Each card should pair one benefit with one precise product
behavior.

- **Offline BLE relay**  
  `Participating phones form an application-layer, store-and-forward BLE overlay.`
- **Structured SOS and priority**  
  `Incident type, urgency, hazards, zone, and available evidence travel ahead of
  lower-priority traffic.`
- **Short voice evidence**  
  `Bounded voice notes are compressed, chunked, relayed, reassembled, and played
  after integrity checks. This is not live voice streaming.`
- **Scoped Rooms**  
  `Public alerts, zones, medical teams, and responders communicate through
  role-aware channels.`
- **Local intelligence**  
  `The product architecture supports on-device speech-to-text and conservative
  incident triage, with visible uncertainty and manual fallback.`
- **Local control-room dashboard**  
  `Operators can see priority, transcript status, zone, hop count, relay latency,
  and voice completeness.`

### F. Safety by Design

**Section label**  
`SAFETY INVARIANTS`

**Heading**  
`Designed to fail safely, not silently.`

Use a high-contrast rules panel rather than ordinary feature cards.

- `A manual SOS is never blocked by speech or triage failure.`
- `SOS metadata always outranks chat and voice chunks.`
- `Uncertainty in transcription, triage, and location remains visible.`
- `Incomplete voice never prevents the structured SOS from being actionable.`
- `AI recommends; human authorities make the final decision.`
- `Messages expire, deduplicate, and stop relaying when their hop limits are reached.`

### G. Two Interfaces, One Local System

**Section label**  
`FIELD TO CONTROL ROOM`

**Heading**  
`Simple for the sender. Actionable for the responder.`

Use a split-screen product showcase.

**Mobile app panel**

- Mesh Code / QR join
- Large, immediate SOS action
- Typed or short voice input
- Delivery and relay status
- Scoped Rooms and received alerts

**Dashboard panel**

- Priority-sorted incident feed
- Transcript and original voice evidence status
- Logical zone with uncertainty
- Hop count, latency, retries, and delivery state
- Operator acknowledgement, dispatch, and responder updates as the target workflow

Use real product screenshots once stable. Until then, clearly label polished visuals
as `Interface concept` rather than presenting them as implemented screens.

### H. Privacy and Trust

**Section label**  
`LOCAL BY DEFAULT`

**Heading**  
`Emergency context should travel only as far as necessary.`

**Body**  
`MeshSetu authenticates and encrypts complete application objects before they are
fragmented for relay. Event and Room scope control where messages belong, while
expiry, size limits, and short retention reduce unnecessary exposure.`

Show four compact trust points:

- Authenticated, encrypted application objects
- Event- and role-scoped access
- Expiring messages and bounded relay
- Short retention for sensitive voice evidence

Do not claim end-to-end encryption, anonymity, regulatory compliance, or
production-grade enrollment unless those properties are implemented and verified.

### I. Prototype Status

**Section label**  
`CURRENT BUILD`

**Heading**  
`A working foundation, moving toward physical field validation.`

Use two clearly separated columns.

**Implemented and locally verified**

- Flutter/Dart Android-first application architecture
- BLE discovery, GATT transport, framing, fragmentation, reassembly, and relay logic
- Encryption/authentication envelope, priority scheduling, ACK/retry, deduplication,
  and expiry
- Durable inbox/outbox, Mesh Code / QR flow, Rooms, SOS, bounded voice packaging,
  gateway bridge, and local dashboard
- Automated protocol, transport, application, and dashboard tests

**Integration work still required**

- Multi-phone physical BLE relay acceptance and full two-hop demo validation
- Real offline speech-to-text engine and measured on-device benchmark
- Learned triage classifier; deterministic safety rules and fallback exist
- Zone visualization and precursor scoring integration
- Production enrollment, key lifecycle, fixed relay, and field hardening

Add the label `Hackathon prototype - not a certified emergency service` near this
section or in the footer.

### J. Closing CTA

**Headline**  
`Keep the path to help open.`

**Body**  
`See how MeshSetu carries a prioritized SOS from a disconnected phone to a local
control room.`

**Primary CTA**  
`View the demo`

**Secondary CTA**  
`Read the technical overview`

Use a simplified reprise of the relay path behind the CTA, ending with a clear
delivered state.

### K. Footer

- MeshSetu wordmark and one-line description
- Links: `How It Works`, `Technical Overview`, `Source Code`, `Team`
- Status: `Android-first hackathon prototype`
- Disclaimer: `MeshSetu is an application-layer BLE overlay. It is not Bluetooth SIG
  Mesh certified and is not yet a production emergency service.`

---

## 4. Visual Direction

The page should feel like dependable civic infrastructure, not a consumer chat app or
a dystopian disaster campaign.

- **Art direction:** resilient networks, field operations, and calm urgency.
- **Palette:** warm off-white or light sand base; deep navy for trust; signal orange
  or vermilion for SOS; teal/green only for confirmed delivery.
- **Typography:** a distinctive, sturdy display face paired with a highly legible
  humanist sans-serif. Avoid generic startup typography and futuristic sci-fi fonts.
- **Graphic language:** nodes, routes, packet states, zone labels, and dashboard data.
  Use subtle grid or topographic patterns to create depth.
- **Motion:** animate one meaningful SOS journey on page load and reveal its four
  stages on scroll. Respect `prefers-reduced-motion` and never make critical copy
  dependent on animation.
- **Imagery:** prioritize real devices, the real dashboard, and field-tested flows.
  Avoid stock images of distressed victims, military command centers, satellites, or
  globally connected maps that misrepresent the product.

---

## 5. Web and Responsive Requirements

- Build mobile-first and support common phone, tablet, laptop, and wide desktop
  widths.
- Keep the hero promise and primary CTA visible within the first mobile viewport.
- Convert horizontal relay diagrams into numbered vertical steps on narrow screens.
- Maintain WCAG AA contrast, visible focus states, keyboard navigation, semantic
  headings, and descriptive alt text.
- Keep motion lightweight and optional; optimize screenshots and diagrams for fast
  loading on constrained connections.
- Use semantic HTML and progressively enhance the relay animation. The core story
  must remain understandable with JavaScript disabled.
- Recommended maximum content width: `1200px`; body-copy measure: `60-72ch`.

---

## 6. Content Guardrails

Use these rules for every design and copy review.

### Say

- `Offline-first emergency communication`
- `Application-layer BLE store-and-forward overlay`
- `Short voice note` or `voice evidence`
- `On-device speech-to-text` only when describing the intended product architecture;
  label the current real engine as pending until integrated and benchmarked
- `Approximate logical zone`
- `AI-assisted triage with human authority`
- `Prototype`, `locally verified`, or `planned field pilot`

### Do not say

- `Bluetooth Mesh certified` or `Bluetooth SIG Mesh`
- `Live voice`, `voice calling`, or `streaming audio`
- `Guaranteed delivery`, `always works`, or `works on every phone`
- `Exact location`, `exact crowd count`, or `predicts disasters`
- `Autonomous dispatch` or `AI decides who gets help`
- `Production ready`, `military grade`, or `unbreakable encryption`
- `Clinically validated`, `government approved`, or `regulation compliant`
- Anything about Text-to-Speech; MeshSetu does not include a TTS feature

---

## 7. Page Metadata

**Browser title**  
`MeshSetu | Offline Emergency Communication Over BLE`

**Meta description**  
`MeshSetu relays prioritized SOS messages, short voice evidence, and local updates
across nearby Android phones when internet and cellular networks are unavailable.`

**Suggested social headline**  
`When networks go down, the message still gets through.`

**Suggested social description**  
`An Android-first, store-and-forward emergency communication prototype built around
nearby phones, prioritized SOS delivery, and a local control-room dashboard.`

---

## 8. Required Assets

The design team should request or produce only assets that demonstrate the actual
system.

- MeshSetu logo/wordmark in SVG
- Mobile screenshots: event join, SOS compose, relay status, Rooms
- Dashboard screenshot: incident list with delivery metrics
- One system-flow diagram: phone -> relay phones -> gateway -> local dashboard
- One short demo video or looping clip with internet disabled
- Test metrics once physical validation is complete: delivery rate, relay latency,
  hop count, voice transfer size/time, and STT latency

Do not publish placeholder performance numbers. Replace the metrics area only with
measurements produced by the final tested build.
