(() => {
  'use strict';

  const root = document.documentElement;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const desktop = window.matchMedia('(min-width: 821px)');
  const precisePointer = window.matchMedia('(hover: hover) and (pointer: fine)');
  let initialized = false;
  let context = null;

  function revealWithoutMotion() {
    document.querySelectorAll('.reveal').forEach((element) => element.classList.add('is-visible'));
  }

  function setupSectionReveals(gsap, ScrollTrigger) {
    document.querySelectorAll('.reveal').forEach((element) => {
      if (element.closest('.hero-section')) {
        element.classList.add('is-visible');
        return;
      }

      ScrollTrigger.create({
        trigger: element,
        start: 'top 88%',
        once: true,
        onEnter: () => {
          element.classList.add('is-visible');
          gsap.fromTo(element, { y: 42, opacity: 0 }, {
            y: 0,
            opacity: 1,
            duration: .72,
            ease: 'power3.out',
            clearProps: 'transform,opacity'
          });
        }
      });
    });
  }

  function setupOpeningSequence(gsap) {
    gsap.timeline({ delay: .72, defaults: { ease: 'power3.out' }, onComplete: () => root.classList.add('hero-intro-complete') })
      .to('.hero-copy .eyebrow', {
        x: 0,
        opacity: 1,
        duration: .52
      })
      .to('.hero-copy h1 span', {
        x: 0,
        opacity: 1,
        duration: .62,
        stagger: .18
      }, '>.06')
      .to('.hero-subtitle', {
        x: 0,
        opacity: 1,
        duration: .58
      }, '>.06')
      .to('.hero-role-list', {
        y: 0,
        opacity: 1,
        duration: .48
      }, '>.05')
      .to('.hero-actions', {
        y: 0,
        opacity: 1,
        duration: .48
      }, '>.04')
      .to('.hero-device-wrap', { opacity: 1, duration: .85 }, '>.08');
  }

  function setupDesktopDepth(gsap, ScrollTrigger) {
    ScrollTrigger.create({
      trigger: '.hero-section',
      start: 'top top',
      end: 'bottom bottom',
      onUpdate: ({ progress }) => root.style.setProperty('--hero-progress', progress.toFixed(4))
    });

    gsap.fromTo('.transition-lockup', { scale: .88, opacity: .35 }, {
      scale: 1,
      opacity: 1,
      ease: 'none',
      scrollTrigger: { trigger: '.transition-section', start: 'top bottom', end: 'center center', scrub: .65 }
    });

    gsap.to('.footer-word', {
      yPercent: -8,
      ease: 'none',
      scrollTrigger: { trigger: '.site-footer', start: 'top bottom', end: 'bottom bottom', scrub: .8 }
    });
  }

  function setupCardDepth(gsap) {
    document.querySelectorAll('.real-work-card').forEach((card) => {
      const reset = () => {
        gsap.to(card, {
          '--tilt-x': '0deg',
          '--tilt-y': '0deg',
          '--pointer-x': '50%',
          '--pointer-y': '50%',
          duration: .55,
          ease: 'power3.out',
          overwrite: true
        });
      };

      card.addEventListener('pointermove', (event) => {
        const bounds = card.getBoundingClientRect();
        const x = (event.clientX - bounds.left) / bounds.width;
        const y = (event.clientY - bounds.top) / bounds.height;
        gsap.to(card, {
          '--tilt-x': `${((.5 - y) * 3.5).toFixed(2)}deg`,
          '--tilt-y': `${((x - .5) * 4.5).toFixed(2)}deg`,
          '--pointer-x': `${(x * 100).toFixed(1)}%`,
          '--pointer-y': `${(y * 100).toFixed(1)}%`,
          duration: .24,
          ease: 'power2.out',
          overwrite: true
        });
      });
      card.addEventListener('pointerleave', reset);
      card.addEventListener('blur', reset, true);
    });
  }

  function setupVisibilityPause(gsap) {
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) gsap.ticker.sleep();
      else gsap.ticker.wake();
    });
  }

  function init() {
    if (initialized) return true;
    initialized = true;

    const gsap = window.gsap;
    const ScrollTrigger = window.ScrollTrigger;
    if (!gsap || !ScrollTrigger || reducedMotion.matches) {
      revealWithoutMotion();
      return false;
    }

    gsap.registerPlugin(ScrollTrigger);
    root.classList.add('motion-ready');

    context = gsap.context(() => {
      setupSectionReveals(gsap, ScrollTrigger);
      setupOpeningSequence(gsap);
      setupVisibilityPause(gsap);

      if (desktop.matches) setupDesktopDepth(gsap, ScrollTrigger);
      if (precisePointer.matches) setupCardDepth(gsap);
    });

    document.fonts?.ready.then(() => ScrollTrigger.refresh());
    return true;
  }

  function refresh() {
    window.ScrollTrigger?.refresh?.();
  }

  function destroy() {
    context?.revert();
    context = null;
    initialized = false;
    root.classList.remove('motion-ready');
    revealWithoutMotion();
  }

  window.PortfolioMotion = {
    init,
    refresh,
    destroy,
    get enhanced() { return Boolean(context); }
  };
})();
