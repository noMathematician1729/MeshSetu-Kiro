const layers = ['Mobile app', 'Backend layer', 'Admin dashboard'];

export default function TechStack() {
  return <section className="tech-stack" id="tech-stack">
    <div className="container">
      <div className="section-heading section-heading--split"><div><p className="section-label">Product foundation</p><h2>Tech stack</h2></div><div><p>Cutting Edge, Modern and Reliable</p><p>Three connected layers, ready to deliver.</p></div></div>
      <div className="tech-stack__grid">{layers.map((layer, index) => <article className="tech-stack__card" key={layer}>
        <span className="tech-stack__number">{String(index + 1).padStart(2, '0')}</span><h3>{layer}</h3>
        <div className="tech-stack__tools">{Array.from({ length: 8 }, (_, toolIndex) => <span key={toolIndex}>Technology</span>)}</div>
      </article>)}</div>
    </div>
  </section>;
}
