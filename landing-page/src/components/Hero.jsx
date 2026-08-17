import Arrow from './Arrow';
import SectionLabel from './SectionLabel';

export default function Hero() {
  return (
    <section className="hero" id="top">
      <div className="hero-ornament" aria-hidden="true">M</div>
      <div className="container hero-inner">
        <div className="hero-copy">
          <SectionLabel className="hero-eyebrow">MeshSetu / Offline emergency relay</SectionLabel>
          <h1>WHEN THE<br />NETWORK <em>FALLS,</em><br />THE MESSAGE<br /><span>MOVES</span><b>.</b></h1>
          <div className="hero-actions">
            <a className="button button--signal" href="#demo">Trace the relay <Arrow /></a>
            <a className="text-link" href="#how-it-works">How it works <Arrow /></a>
          </div>
        </div>
        <p className="hero-description">MeshSetu uses nearby Android phones to carry a structured SOS, short voice evidence, and scoped updates across a store-and-forward Bluetooth Low Energy overlay when internet and cellular service are unavailable.</p>
      </div>
      <div className="container hero-metrics" aria-label="MeshSetu system principles">
        <div className="hero-metric hero-metric--signal"><strong>OFFLINE</strong><span>Internet is optional</span></div>
        <div className="hero-metric"><strong>BLE</strong><span>Phone-to-phone relay</span></div>
        <div className="hero-metric"><strong>SOS</strong><span>Priority before routine traffic</span></div>
        <div className="hero-metric"><strong>LOCAL</strong><span>Gateway to control room</span></div>
      </div>
      <div className="hero-edge" aria-hidden="true"><span>01 / FIELD NETWORK</span><span>MESSAGE IN MOTION</span><span>SCROLL TO EXPLORE</span></div>
    </section>
  );
}
