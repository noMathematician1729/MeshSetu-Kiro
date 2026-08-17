import { useState } from 'react';
import { demoStages } from '../content';
import Arrow from './Arrow';
import SectionLabel from './SectionLabel';

export default function DemoLoop() {
  const [activeStage, setActiveStage] = useState(0);
  const current = demoStages[activeStage];
  return (
    <section className="demo-loop section-dark" id="demo">
      <div className="container demo-loop-grid"><div className="demo-console"><div className="demo-console__top"><span>LOCAL PATH / DEMO01</span><span><i className="status-dot" /> {activeStage === 3 ? 'DELIVERED' : 'SIMULATION'}</span></div><div className="demo-console__body"><SectionLabel light>Run the local path</SectionLabel><h2>One message. <em>Four visible handoffs.</em></h2><p>Move the signal through the system and see what each device contributes. The path stays understandable even when the network does not.</p><button className="button button--signal demo-button" onClick={() => setActiveStage((stage) => stage === demoStages.length - 1 ? 0 : stage + 1)}>{activeStage === demoStages.length - 1 ? 'Run it again' : 'Advance the message'} <Arrow /></button></div><div className="demo-console__footer"><span>OFFLINE MODE</span><span>PACKET / SOS-P0</span><span>HOP {Math.min(activeStage + 1, 3)} / 3</span></div></div>
        <div className="demo-stages" aria-live="polite">{demoStages.map((stage, index) => <button className={`demo-stage ${index === activeStage ? 'demo-stage--active' : ''} demo-stage--${stage.color}`} key={stage.label} onClick={() => setActiveStage(index)}><span className="demo-stage__number">{String(index + 1).padStart(2, '0')}</span><span className="demo-stage__copy"><small>{stage.label}</small><strong>{stage.title}</strong>{index === activeStage && <span>{stage.detail}</span>}</span><span className="demo-stage__state">{index < activeStage ? '✓' : index === activeStage ? '●' : '○'}</span></button>)}<div className="demo-readout"><span className="readout-marker" /> CURRENT HANDOFF <strong>{current.label}</strong></div></div>
      </div>
    </section>
  );
}
