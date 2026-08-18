import SectionLabel from './SectionLabel';

export default function Trust() {
  return <section className="trust section-teal"><div className="container trust-grid"><div><SectionLabel light>Local by default</SectionLabel><h2>Emergency context should travel only as far as necessary.</h2><p className="lead">MeshSetu authenticates and encrypts complete application objects before they are fragmented for relay. Event and Room scope control where messages belong, while expiry, size limits, and short retention reduce unnecessary exposure.</p></div><div className="trust-points"><div><span>01</span><strong>Authenticated, encrypted objects</strong></div><div><span>02</span><strong>Event- and role-scoped access</strong></div><div><span>03</span><strong>Expiring, bounded relay</strong></div><div><span>04</span><strong>Short retention for voice evidence</strong></div></div></div></section>;
}
