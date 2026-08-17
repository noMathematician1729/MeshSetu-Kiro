export default function SectionLabel({ children, light = false, className = '' }) {
  return <p className={`section-label ${light ? 'section-label--light' : ''} ${className}`}>{children}</p>;
}
