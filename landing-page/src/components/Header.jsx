import { useState } from 'react';
import Arrow from './Arrow';
import Logo from './Logo';

export default function Header() {
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = () => setMenuOpen(false);

  return (
    <header className="site-header">
      <div className="container header-inner">
        <Logo />
        <button className="menu-toggle" aria-expanded={menuOpen} aria-controls="site-nav" onClick={() => setMenuOpen((open) => !open)}>
          <span>{menuOpen ? 'Close' : 'Menu'}</span><span className="menu-lines" aria-hidden="true"><i /><i /></span>
        </button>
        <nav id="site-nav" className={`site-nav ${menuOpen ? 'site-nav--open' : ''}`} aria-label="Main navigation">
          <a href="#how-it-works" onClick={closeMenu}>How it works</a>
          <a href="#capabilities" onClick={closeMenu}>Capabilities</a>
          {/* <a href="#safety" onClick={closeMenu}>Safety</a> */}
          <a href="#tech-stack" onClick={closeMenu}>Tech stack</a>
          <a href="#architecture" onClick={closeMenu}>Architecture</a>
          <a href="#prototype" onClick={closeMenu}>Prototype</a>
          <a className="button button--small button--dark" href="#demo" onClick={closeMenu}>View demo <Arrow /></a>
        </nav>
      </div>
    </header>
  );
}
