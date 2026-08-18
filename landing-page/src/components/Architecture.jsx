export default function Architecture() {
  return <section className="architecture" id="architecture">
    <div className="container">
      <div className="section-heading section-heading--split"><div><p className="section-label">System design</p><h2>Architecture</h2></div><p>A full technical architecture will live here. This placeholder maps the main layers of the MeshSetu system.</p></div>
      <div className="architecture__graph" aria-label="Architecture diagram placeholder">
        <span className="architecture__node architecture__node--phone">Mobile app</span>
        <span className="architecture__node architecture__node--mesh">BLE mesh</span>
        <span className="architecture__node architecture__node--gateway">Gateway</span>
        <span className="architecture__node architecture__node--admin">Admin dashboard</span>
        <i className="architecture__line architecture__line--one" /><i className="architecture__line architecture__line--two" /><i className="architecture__line architecture__line--three" />
        <small>ARCHITECTURE PLACEHOLDER</small>
      </div>
    </div>
  </section>;
}
