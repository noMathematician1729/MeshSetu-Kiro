export default function Arrow({ diagonal = false }) {
  return <span className={`arrow ${diagonal ? 'arrow--diagonal' : ''}`} aria-hidden="true">↗</span>;
}
