(() => {
  'use strict';

  const toggle = document.querySelector('#nav-toggle');
  const menu = document.querySelector('#nav-menu');
  if (!toggle || !menu) return;

  function closeMenu({ restoreFocus = false } = {}) {
    if (!menu.classList.contains('is-open')) return;
    menu.classList.remove('is-open');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.setAttribute('aria-label', 'Open navigation');
    if (restoreFocus) toggle.focus();
  }

  toggle.addEventListener('click', () => {
    const opening = !menu.classList.contains('is-open');
    if (!opening) {
      closeMenu({ restoreFocus: true });
      return;
    }
    menu.classList.add('is-open');
    toggle.setAttribute('aria-expanded', 'true');
    toggle.setAttribute('aria-label', 'Close navigation');
    menu.querySelector('a')?.focus({ preventScroll: true });
  });

  menu.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => closeMenu()));

  document.addEventListener('pointerdown', (event) => {
    if (!menu.classList.contains('is-open')) return;
    if (menu.contains(event.target) || toggle.contains(event.target)) return;
    closeMenu();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !menu.classList.contains('is-open')) return;
    event.preventDefault();
    closeMenu({ restoreFocus: true });
  });

  window.addEventListener('resize', () => {
    if (window.matchMedia('(min-width: 821px)').matches) closeMenu();
  });
})();
