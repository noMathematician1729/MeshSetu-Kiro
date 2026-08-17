import DashboardMockup from './DashboardMockup';
import PhoneMockup from './PhoneMockup';
import SectionLabel from './SectionLabel';

export default function Interfaces() {
  return <section className="interfaces section-paper"><div className="container"><div className="section-heading section-heading--split"><div><SectionLabel>Field to control room</SectionLabel><h2>Simple for the sender. <em>Actionable</em> for the responder.</h2></div><p>One local system, two focused surfaces. These are interface concepts for the experience currently being built.</p></div><div className="interfaces-grid"><article className="interface-panel interface-panel--phone"><div className="interface-panel__head"><span>FIELD DEVICE</span><span className="concept-tag">INTERFACE CONCEPT</span></div><PhoneMockup /><div className="interface-features"><span>Mesh Code / QR join</span><span>Immediate SOS action</span><span>Relay status + Rooms</span></div></article><article className="interface-panel interface-panel--dashboard"><div className="interface-panel__head"><span>LOCAL CONTROL ROOM</span><span className="concept-tag">INTERFACE CONCEPT</span></div><DashboardMockup /><div className="interface-features"><span>Priority-sorted feed</span><span>Zone + delivery state</span><span>Hop count + latency</span></div></article></div></div></section>;
}
