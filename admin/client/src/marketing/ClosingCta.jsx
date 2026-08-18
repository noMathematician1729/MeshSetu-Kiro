import Arrow from './Arrow';
import SectionLabel from './SectionLabel';

export default function ClosingCta() {
  return <section className="closing section-red"><div className="closing-sun" aria-hidden="true" /><div className="container closing-inner"><div><SectionLabel light>Keep the path open</SectionLabel><h2>See how a prioritized SOS moves from a disconnected phone to a local control room.</h2><div className="closing-actions"><a className="button button--light" href="#demo">View the demo <Arrow /></a><a className="text-link text-link--light" href="#prototype">Read the technical overview <Arrow /></a></div></div><div className="closing-route" aria-hidden="true"><span className="closing-route__line" /><i className="closing-node closing-node--one">!</i><i className="closing-node closing-node--two">●</i><i className="closing-node closing-node--three">●</i><i className="closing-node closing-node--four">✓</i><small>DELIVERED LOCALLY</small></div></div></section>;
}
