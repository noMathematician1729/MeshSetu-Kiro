import { useState } from 'react';
import Arrow from './Arrow';
import Logo from './Logo';

export default function Header() {
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = () => setMenuOpen(false);
  const scrollToSection = (event) => {
    const target = event.currentTarget.getAttribute('href');
    if (!target?.startsWith('#')) {
      closeMenu();
      return;
    }
    event.preventDefault();
    event.currentTarget.getRootNode().querySelector(target)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    closeMenu();
  };

  return (
    <header className="site-header">
      <div className="container header-inner">
        <Logo />
        <button className="menu-toggle" aria-expanded={menuOpen} aria-controls="site-nav" onClick={() => setMenuOpen((open) => !open)}>
          <span>{menuOpen ? 'Close' : 'Menu'}</span><span className="menu-lines" aria-hidden="true"><i /><i /></span>
        </button>
        <nav id="site-nav" className={`site-nav ${menuOpen ? 'site-nav--open' : ''}`} aria-label="Main navigation">
          <a href="#how-it-works" onClick={scrollToSection}>How it works</a>
          <a href="#capabilities" onClick={scrollToSection}>Features</a>
          <a href="#tech-stack" onClick={scrollToSection}>Tech stack</a>
          <a href="#architecture" onClick={scrollToSection}>Architecture</a>
          <a className="button button--small button--nav-cta" href="/control-room" onClick={scrollToSection}>Control room <Arrow /></a>
        </nav>
      </div>
    </header>
  );
}
