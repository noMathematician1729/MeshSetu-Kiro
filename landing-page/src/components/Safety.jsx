import { safetyRules } from '../content';
import SectionLabel from './SectionLabel';

export default function Safety() {
  return <section className="safety section-dark" id="safety"><div className="container safety-grid"><div className="safety-intro"><SectionLabel light>Safety invariants</SectionLabel><h2>Designed to fail safely, <em>not silently.</em></h2><p>Communication tools in an emergency need clear boundaries. MeshSetu keeps uncertainty visible and gives the human operator the final say.</p></div><div className="safety-rules">{safetyRules.map((rule, index) => <div className="safety-rule" key={rule}><span>{String(index + 1).padStart(2, '0')}</span><p>{rule}</p><i aria-hidden="true" /></div>)}</div></div></section>;
}
