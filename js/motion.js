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
    const targets = [
      '.hero-copy .eyebrow',
      '.hero-copy h1 span',
      '.hero-subtitle',
      '.hero-role-list',
      '.hero-actions'
    ];

    gsap.timeline({ defaults: { ease: 'power3.out' } })
      .from(targets, { y: 28, opacity: 0, duration: .72, stagger: .07, clearProps: 'transform,opacity' })
      .from('.hero-device-wrap', { y: 44, opacity: 0, rotationX: 5, duration: .9, clearProps: 'transform,opacity' }, '-=.52');
  }

  function setupDesktopDepth(gsap, ScrollTrigger) {
    gsap.to('.hero-copy', {
      yPercent: -12,
      scale: .965,
      opacity: .34,
      ease: 'none',
      scrollTrigger: {
        trigger: '.hero-section',
        start: 'top top',
        end: 'bottom bottom',
        scrub: .7
      }
    });

    gsap.to('.hero-device-wrap', {
      yPercent: -5,
      rotationY: -2.5,
      transformOrigin: '50% 50%',
      ease: 'none',
      scrollTrigger: {
        trigger: '.hero-section',
        start: 'top top',
        end: 'bottom bottom',
        scrub: .75
      }
    });

    gsap.to('.hero-orbit-card--left', {
      yPercent: -65,
      xPercent: -8,
      rotation: -14,
      ease: 'none',
      scrollTrigger: { trigger: '.hero-section', start: 'top top', end: 'bottom bottom', scrub: .8 }
    });

    gsap.to('.hero-orbit-card--right', {
      yPercent: 48,
      xPercent: 10,
      rotation: 13,
      ease: 'none',
      scrollTrigger: { trigger: '.hero-section', start: 'top top', end: 'bottom bottom', scrub: .8 }
    });

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
