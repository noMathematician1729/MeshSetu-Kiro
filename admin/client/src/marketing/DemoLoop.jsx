import { demoStages } from './content.js';

export default function DemoLoop() {
  return <div className="demo-flow" id="demo" aria-label="SOS message handoffs">{demoStages.map((stage, index) => <article className="demo-flow__card" key={stage.label}>
        <span className="demo-flow__top"><span className="demo-flow__number">{String(index + 1).padStart(2, '0')}</span></span>
        <span className="demo-flow__label">{stage.label}</span><strong>{stage.title}</strong><p>{stage.detail}</p>
      </article>)}</div>;
}
