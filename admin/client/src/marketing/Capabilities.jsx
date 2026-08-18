import { capabilities } from './content.js';
import DemoLoop from './DemoLoop';
import SectionLabel from './SectionLabel';

export default function Capabilities() {
  return <section className="capabilities section-paper" id="capabilities"><div className="container"><div className="section-heading"><SectionLabel>Built for graceful degradation</SectionLabel><h2>The essential <em>message survives.</em></h2><p>MeshSetu is designed around a strict priority order: preserve the actionable SOS, then add context when the path allows it.</p></div><div className="capability-grid">{capabilities.map((item) => <article className={`capability-card capability-card--${item.tone}`} key={item.number}><span className="card-number">{item.number}</span><span className="capability-shape" aria-hidden="true" /><h3>{item.title}</h3><p>{item.text}</p><span className="card-corner" aria-hidden="true">↗</span></article>)}</div><DemoLoop /></div></section>;
}
