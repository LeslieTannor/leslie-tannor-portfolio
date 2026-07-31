(() => {
  'use strict';

  const MOTION_KEY = 'leslie-background-motion';
  const videos = [...document.querySelectorAll('video[autoplay]')];
  const toggles = [...document.querySelectorAll('.motion-toggle')];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  if (!videos.length) {
    toggles.forEach((toggle) => { toggle.hidden = true; });
    return;
  }

  const readPreference = () => {
    try { return window.localStorage.getItem(MOTION_KEY); } catch { return null; }
  };

  let paused = reducedMotion.matches || readPreference() === 'paused';

  function updateControls() {
    toggles.forEach((toggle) => {
      toggle.setAttribute('aria-pressed', String(paused));
      toggle.setAttribute('aria-label', paused ? 'Play background motion' : 'Pause background motion');
      toggle.title = paused ? 'Play background motion' : 'Pause background motion';
      const icon = toggle.querySelector('i');
      if (icon) icon.className = paused ? 'fa-solid fa-play' : 'fa-solid fa-pause';
    });
  }

  function applyMotion() {
    videos.forEach((video) => {
      if (paused || document.hidden) {
        video.pause();
      } else {
        video.play().catch(() => {
          // Autoplay may be blocked by the browser; the page remains usable.
        });
      }
    });
    updateControls();
  }

  toggles.forEach((toggle) => toggle.addEventListener('click', () => {
    paused = !paused;
    try { window.localStorage.setItem(MOTION_KEY, paused ? 'paused' : 'playing'); } catch { /* Current page still updates. */ }
    applyMotion();
  }));

  document.addEventListener('visibilitychange', applyMotion);
  reducedMotion.addEventListener?.('change', (event) => {
    if (event.matches) paused = true;
    applyMotion();
  });

  applyMotion();
})();
