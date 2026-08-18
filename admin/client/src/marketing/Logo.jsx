export default function Logo({ inverted = false }) {
  return (
    <a className={`logo ${inverted ? 'logo--inverted' : ''}`} href="#top" aria-label="MeshSetu home">
      <span className="logo-mark" aria-hidden="true"><i /><i /><i /></span>
      <span className="logo-word">MeshSetu</span>
    </a>
  );
}
