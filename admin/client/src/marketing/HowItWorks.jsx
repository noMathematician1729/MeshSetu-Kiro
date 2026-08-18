import { steps } from './content.js';
import SectionLabel from './SectionLabel';

export default function HowItWorks() {
  return (
    <section className="how section-yellow" id="how-it-works">
      <div className="container"><div className="section-heading section-heading--split"><div><SectionLabel>From SOS to response</SectionLabel><h2>A local path to help, <em>one device</em> at a time.</h2></div><p>Every participating phone can become part of the path. The system keeps the essential message moving, even as optional layers gracefully fall away.</p></div>
        <div className="steps-grid">{steps.map((step, index) => <article className="step-card" key={step.number}><div className="step-top"><span className="step-number">{step.number}</span>{index < steps.length - 1 && <span className="step-arrow" aria-hidden="true">→</span>}</div><h3>{step.title}</h3><p>{step.text}</p></article>)}</div>
        <div className="annotation"><span className="annotation-mark">!</span><strong>Structured SOS first.</strong> Voice evidence and routine messages follow.</div>
      </div>
    </section>
  );
}
