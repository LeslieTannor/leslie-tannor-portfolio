(() => {
  'use strict';

  const THEME_KEY = 'leslie-theme-clean-v17';
  const root = document.documentElement;
  const toggle = document.querySelector('#theme-toggle');
  const themeColor = document.querySelector('meta[name="theme-color"]');

  function readTheme() {
    try {
      return window.localStorage.getItem(THEME_KEY) === 'dark' ? 'dark' : 'light';
    } catch {
      return root.dataset.theme === 'dark' ? 'dark' : 'light';
    }
  }

  function announce(message) {
    let status = document.querySelector('#theme-status');
    if (!status) {
      status = document.createElement('div');
      status.id = 'theme-status';
      status.className = 'sr-only';
      status.setAttribute('aria-live', 'polite');
      document.body.append(status);
    }
    status.textContent = '';
    window.requestAnimationFrame(() => { status.textContent = message; });
  }

  function applyTheme(theme, shouldAnnounce = false) {
    root.dataset.theme = theme;
    root.style.colorScheme = theme;
    themeColor?.setAttribute('content', theme === 'dark' ? '#07090d' : '#ffffff');

    if (toggle) {
      const dark = theme === 'dark';
      toggle.setAttribute('aria-pressed', String(dark));
      toggle.setAttribute('aria-label', dark ? 'Use light theme' : 'Use dark theme');
      toggle.title = dark ? 'Use light theme' : 'Use dark theme';
      const icon = toggle.querySelector('i');
      if (icon) icon.className = dark ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
    }

    if (shouldAnnounce) announce(`${theme === 'dark' ? 'Dark' : 'Light'} theme enabled`);
  }

  applyTheme(readTheme());

  toggle?.addEventListener('click', () => {
    const theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
    try { window.localStorage.setItem(THEME_KEY, theme); } catch { /* Keep the current-page setting. */ }
    applyTheme(theme, true);
  });

  window.addEventListener('storage', (event) => {
    if (event.key === THEME_KEY && (event.newValue === 'dark' || event.newValue === 'light')) applyTheme(event.newValue);
  });
})();
