import SectionLabel from './SectionLabel';

const cards = [
  ['01', 'Infrastructure can fail', 'Internet and cellular service may be unavailable or congested.'],
  ['02', 'Critical context gets lost', 'Unstructured reports slow down assessment and response.'],
  ['03', 'Responders need local visibility', 'Incidents, zones, urgency, and delivery state must stay visible without a cloud dependency.'],
];

export default function ProblemSection() {
  return (
    <section className="problem section-paper">
      <div className="container problem-grid">
        <div className="problem-visual" aria-hidden="true"><div className="problem-visual__title">THE<br /><span>GAP</span></div><div className="signal-bars"><i /><i /><i /><i /></div><div className="problem-visual__note">CONNECTION<br /><strong>LOST</strong></div><div className="problem-cross">×</div></div>
        <div className="problem-copy">
          <SectionLabel>The communication gap</SectionLabel><h2>Emergencies do not wait for connectivity.</h2><p className="lead">Crowded venues and disaster zones can overwhelm or lose cellular and internet coverage. People still need a way to report danger, responders need structured information, and control rooms need a reliable local picture.</p>
          <div className="problem-cards">{cards.map(([number, title, text]) => <article className="problem-card" key={number}><span className="card-number">{number}</span><h3>{title}</h3><p>{text}</p></article>)}</div>
        </div>
      </div>
    </section>
  );
}
