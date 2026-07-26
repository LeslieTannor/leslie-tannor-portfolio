(() => {
  'use strict';

const root = document.documentElement;
const THEME_KEY = 'leslie-theme-clean-v16';
const RAIN_KEY = 'leslie-rain-spatial-v1';
const isBrowserAudit = new URLSearchParams(window.location.search).has('browser-audit');

const qs = (selector, scope = document) => scope.querySelector(selector);
const qsa = (selector, scope = document) => [...scope.querySelectorAll(selector)];

const rainLayer = qs('#rain-layer');
const themeToggle = qs('#theme-toggle');
const rainToggle = qs('#rain-toggle');
const navToggle = qs('#nav-toggle');
const navMenu = qs('#nav-menu');
const uiStatus = qs('#ui-status');
const marqueeToggle = qs('#marquee-toggle');
const marqueeTrack = qs('.marquee-track');

const heroSection = qs('.hero-section');
const heroDeviceWrap = qs('#hero-device-wrap');
const heroDevice = qs('#hero-device');
const heroBootState = qs('#hero-boot-state');
const heroLogoState = qs('#hero-logo-state');
const heroGallery = qs('#hero-gallery');
const heroGalleryUi = qs('.hero-gallery-ui');
const heroCloseCover = qs('#hero-close-cover');
const heroSlides = qsa('.hero-slide');
const heroDots = qsa('.hero-dot');

const revealItems = qsa('.reveal');
const navSections = qsa('main section[data-nav]');
const navLinks = qsa('.nav-menu a[href^="#"]');

const form = qs('.contact-form');
const formSuccess = qs('#form-success');

const workspaceStage = qs('#workspace-stage');
const workspaceDevice = qs('#workspace-device');
const workspaceLaptop = qs('#workspace-laptop');
const workspaceTurnOn = qs('#workspace-turn-on');
const workspacePower = qs('#workspace-power');

const projectWindow = qs('#project-window');
const projectTitle = qs('#project-window-title');
const projectKicker = qs('#project-window-kicker');
const projectAddress = qs('#project-browser-address');
const projectFrame = qs('#project-frame');
const browserOverlay = qs('#browser-overlay');
const browserOverlayTitle = qs('#browser-overlay-title');
const browserOverlayCopy = qs('#browser-overlay-copy');
const browserFallbackLink = qs('#browser-fallback-link');
const browserOpenButton = qs('#project-browser-open');
const browserReloadButton = qs('#project-browser-reload');

const projectClose = qs('#project-window-close');
const projectMinimize = qs('#project-window-minimize');
const projectExpand = qs('#project-window-expand');

const desktopIcons = qsa('.desktop-icon');
const dockItems = qsa('.dock-item');
const projectLaunchers = [...desktopIcons, ...dockItems].filter((button) => button.dataset.project);
const caseStudyCards = qsa('.real-work-card-trigger');
const realWorkType = qs('#real-work-type');
const realWorkTitle = qs('#real-work-title');
const realWorkSummary = qs('#real-work-summary');
const realWorkFeel = qs('#real-work-feel');
const realWorkWhy = qs('#real-work-why');
const realWorkDecisions = qs('#real-work-decisions');
const realWorkChips = qs('#real-work-chips');
const realWorkFeatured = qs('#real-work-featured');
const realWorkFeaturedImage = qs('#real-work-featured-image');
const realWorkFeaturedLabel = qs('#real-work-featured-label');
const realWorkFeaturedCaption = qs('#real-work-featured-caption');
const realWorkDetail = qs('#real-work-detail');
const realWorkDetailClose = qs('#real-work-detail-close');
const realWorkCarouselLabel = qs('#real-work-carousel-label');
const realWorkImageCounter = qs('#real-work-image-counter');
const realWorkProgressFill = qs('#real-work-progress-fill');
const realWorkLiveLink = qs('#real-work-live-link');
const realWorkPrev = qs('#real-work-prev');
const realWorkNext = qs('#real-work-next');
const galleryLightbox = qs('#gallery-lightbox');
const galleryLightboxImage = qs('#gallery-lightbox-image');
const galleryLightboxCaption = qs('#gallery-lightbox-caption');
const galleryLightboxClose = qs('#gallery-lightbox-close');
const galleryLightboxPrev = qs('#gallery-lightbox-prev');
const galleryLightboxNext = qs('#gallery-lightbox-next');


let heroTimer = null;
let heroSlideIndex = 0;
let workspacePowered = false;
let activeProjectKey = 'akwaaba';
let overlayTimer = null;
let activeCaseStudyKey = null;
let activeCaseStudyImageIndex = 0;
let caseStudyReturnFocus = null;
let lightboxReturnFocus = null;
let projectReturnFocus = null;
let scrollTicking = false;
let resizeTimer = null;
let activeNavKey = null;
let motionEnhanced = false;

const tabletModeQuery = window.matchMedia('(max-width: 820px)');
const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
const isTabletMode = () => tabletModeQuery.matches;

const safeStorage = {
  get(key, fallback) {
    try {
      return window.localStorage.getItem(key) ?? fallback;
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // The preference still applies for the current page when storage is unavailable.
    }
  }
};

const projects = {
  akwaaba: {
    title: 'Akwaaba House',
    kicker: 'Live project preview',
    url: 'https://akwaabahouse.netlify.app/'
  },
  goldbar: {
    title: 'GoldBar Fitness',
    kicker: 'Live project preview',
    url: 'https://goldbarfitness.netlify.app/'
  },
  wealthwise: {
    title: 'WealthWise',
    kicker: 'Live project preview',
    url: 'https://wealthwiselt.netlify.app/'
  }
};


const caseStudies = {
  akwaaba: {
    title: 'Akwaaba House',
    cardKicker: 'Restaurant Brand Website',
    summary: 'I shaped Akwaaba House to feel like the digital version of walking into a premium Ghanaian dining space: warm, intentional, polished, and easy to trust. The experience leans on deep green and gold tones, confident typography, and rich imagery so the atmosphere does as much work as the copy.',
    feel: 'I wanted visitors to feel welcomed immediately, but also reassured that the brand was premium, culturally grounded, and worth exploring further.',
    why: 'That is why the hero is spacious, the type is editorial, and the layout avoids clutter. For a hospitality product, mood and appetite matter, so I let the imagery breathe and gave the primary actions clear visual priority.',
    decisions: 'I broke the journey into story, space, highlights, menu, people, and contact so users can either browse at leisure or move directly toward a booking decision. The structure balances emotional storytelling with conversion clarity.',
    chips: ['Hospitality UX', 'Brand storytelling', 'Conversion journey', 'Premium visual system'],
    images: [
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House.png',
        width: 1275,
        height: 1248,
        alt: 'Akwaaba House homepage hero',
        label: 'Homepage hero',
        caption: 'A premium first impression built around atmosphere, large type, and a fast route into menu exploration or booking.'
      },
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House2.png',
        width: 1283,
        height: 803,
        alt: 'Akwaaba House story section',
        label: 'Story-led introduction',
        caption: 'The story section explains the brand through atmosphere, interior quality, and warmth instead of using dense copy blocks.'
      },
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House3.png',
        width: 1273,
        height: 817,
        alt: 'Akwaaba House gallery section',
        label: 'Gallery and space preview',
        caption: 'I used a scrollable gallery format so users can understand the restaurant experience visually before they ever arrive on-site.'
      },
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House4.png',
        width: 1261,
        height: 902,
        alt: 'Akwaaba House highlights section',
        label: 'Highlights section',
        caption: 'This section turns menu personality into quick-scan cards so the food feels premium while still staying easy to browse.'
      },
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House5.png',
        width: 1225,
        height: 710,
        alt: 'Akwaaba House menu exploration',
        label: 'Menu exploration',
        caption: 'I kept menu browsing card-based and visual so decision-making feels faster and more appetising on first contact.'
      },
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House6.png',
        width: 1244,
        height: 924,
        alt: 'Akwaaba House people and testimonials section',
        label: 'Trust and human connection',
        caption: 'Introducing the people behind the experience helps the restaurant feel credible, personal, and service-led rather than anonymous.'
      },
      {
        src: 'images/Akwaaba%20House/Akwaaba%20House7.png',
        width: 1248,
        height: 690,
        alt: 'Akwaaba House contact section',
        label: 'Contact and booking close',
        caption: 'The closing section gathers address, opening times, and booking actions together so intent can convert without friction.'
      }
    ]
  },
  goldbar: {
    title: 'GoldBar Fitness',
    cardKicker: 'Fitness Brand + Product Ecosystem',
    summary: 'I designed GoldBar Fitness as a premium performance brand that feels aspirational but still actionable. The system stretches across landing pages, membership flows, class browsing, app promotion, coaching credibility, and ecommerce so the brand can convert from multiple entry points.',
    feel: 'I wanted users to feel energised, motivated, and part of something premium rather than like they were looking at another generic gym website.',
    why: 'That drove the black-and-gold visual language, bold stat-led hero, strong contrast, and distinct routes into membership, classes, coaching, shop, and app touchpoints.',
    decisions: 'I balanced aspiration with utility: visitors can explore training options, compare plans, shop essentials, review coaches, and understand the value proposition without losing momentum.',
    chips: ['Fitness UX', 'Conversion system', 'Membership funnel', 'Cross-platform brand'],
    images: [
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness%20Dark.png',
        width: 1911,
        height: 1218,
        alt: 'GoldBar Fitness dark homepage hero',
        label: 'Homepage hero',
        caption: 'The hero uses motion, stats, and strong contrast to communicate premium positioning and training momentum straight away.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness2%20Dark.png',
        width: 1537,
        height: 1235,
        alt: 'GoldBar Fitness founder and brand story in the dark theme',
        label: 'Dark brand story',
        caption: 'The dark-theme brand story introduces the founder and supporting credentials while keeping the premium visual language consistent.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness%20Light.png',
        width: 1234,
        height: 1066,
        alt: 'GoldBar Fitness about section light theme',
        label: 'Brand story and credibility',
        caption: 'This lighter layout introduces the founder and the brand promise so the experience has a human anchor behind the premium styling.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness%20Light1.png',
        width: 1241,
        height: 640,
        alt: 'GoldBar Fitness light hero variant',
        label: 'Light hero variation',
        caption: 'I explored a lighter hero direction to test how the same value proposition performs in a brighter, more editorial presentation.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness%20Light2.png',
        width: 1241,
        height: 618,
        alt: 'GoldBar Fitness shop landing page',
        label: 'Shop landing page',
        caption: 'The shop entry keeps product messaging clean and direct so branded essentials feel like part of the overall membership ecosystem.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness%20Shop.png',
        width: 1269,
        height: 1003,
        alt: 'GoldBar Fitness ecommerce product grid',
        label: 'Product grid',
        caption: 'Product cards are designed to stay premium but practical, keeping pricing and purchase actions easy to scan.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness3%20Dark.png',
        width: 1583,
        height: 1254,
        alt: 'GoldBar Fitness training options section',
        label: 'Training categories',
        caption: 'I used a grid of training goals to help different users self-identify quickly and move toward the right offering.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness4%20Dark.png',
        width: 2536,
        height: 672,
        alt: 'GoldBar Fitness membership benefits strip',
        label: 'Member experience strip',
        caption: 'This section condenses benefits into a quick comparison format so the promise is visible before pricing appears.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness5%20Dark.png',
        width: 1551,
        height: 1021,
        alt: 'GoldBar Fitness experience gallery',
        label: 'Experience gallery',
        caption: 'The gallery gives spatial proof of the premium experience, reducing doubt around the actual gym environment.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness6%20Dark.png',
        width: 1312,
        height: 618,
        alt: 'GoldBar Fitness mobile app concept',
        label: 'App teaser',
        caption: 'I introduced an app teaser to show that the product can extend beyond the physical gym into habit tracking and convenience.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness7%20Dark.png',
        width: 1550,
        height: 993,
        alt: 'GoldBar Fitness coaches section',
        label: 'Coach credibility',
        caption: 'Featuring coaches adds proof, personality, and expertise to the journey, which is important for a trust-based fitness product.'
      },
      {
        src: 'images/GoldBar%20Fitness/GoldBar%20Fitness8%20Dark.png',
        width: 1251,
        height: 1139,
        alt: 'GoldBar Fitness pricing and contact section',
        label: 'Pricing and conversion',
        caption: 'The plans section is designed to make commitment levels clear and keep the enquiry path visible right beside the pricing.'
      }
    ]
  },
  wealthwise: {
    title: 'WealthWise',
    cardKicker: 'Fintech Dashboard Concept',
    summary: 'I designed WealthWise as a finance interface that reduces anxiety through structure. Instead of making money management feel cold or overwhelming, I used a deep-blue visual system, strong card hierarchy, and focused navigation so the product feels calm, trustworthy, and immediately legible.',
    feel: 'I wanted users to feel in control, informed, and guided rather than overwhelmed by numbers or financial jargon.',
    why: 'That is why the interface leans on modular cards, clear spacing, concentrated glows, and progressive disclosure from high-level overviews into more detailed planning screens.',
    decisions: 'I prioritised dashboard scannability, consistent component language, and straightforward information hierarchy so the product can support budgeting, savings, salary planning, home buying, and expenditure tracking without losing clarity.',
    chips: ['Fintech UX', 'Information hierarchy', 'Dashboard design', 'Trust-first product'],
    images: [
      {
        src: 'images/wealthwise/wealthwise.png',
        width: 2225,
        height: 1319,
        alt: 'WealthWise marketing landing page',
        label: 'Marketing overview',
        caption: 'The landing page quickly frames the product as practical and approachable, using clear value cards to reduce ambiguity.'
      },
      {
        src: 'images/wealthwise/wealthwise2.png',
        width: 1586,
        height: 992,
        alt: 'WealthWise landing hero with dashboard preview',
        label: 'Landing hero variant',
        caption: 'This version pulls the dashboard preview forward so users immediately understand the product before reading deeply.'
      },
      {
        src: 'images/wealthwise/wealthwise3.png',
        width: 1586,
        height: 992,
        alt: 'WealthWise login screen',
        label: 'Login and security',
        caption: 'The login screen uses glow, focus, and restrained fields to make the brand feel secure without becoming visually heavy.'
      },
      {
        src: 'images/wealthwise/wealthwise4.png',
        width: 1586,
        height: 992,
        alt: 'WealthWise home planning dashboard',
        label: 'Home planning dashboard',
        caption: 'I designed the dream-home flow to connect saving behaviour with a concrete aspiration, which makes the product feel more motivating.'
      },
      {
        src: 'images/wealthwise/wealthwise5.png',
        width: 1586,
        height: 992,
        alt: 'WealthWise savings and salary dashboard',
        label: 'Savings control center',
        caption: 'This view organises salary, monthly budgeting, and savings targets into a single dashboard so progress stays visible at a glance.'
      },
      {
        src: 'images/wealthwise/wealthwise6.png',
        width: 1586,
        height: 992,
        alt: 'WealthWise expenditure analytics dashboard',
        label: 'Expenditure analytics',
        caption: 'The expenditure screen breaks spending into categories and transactions so users can move from awareness to action quickly.'
      }
    ]
  }
};


function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function announce(message) {
  if (!uiStatus) return;
  uiStatus.textContent = '';
  window.setTimeout(() => {
    uiStatus.textContent = message;
  }, 40);
}

function updateToggleStates() {
  const theme = root.getAttribute('data-theme') || 'dark';
  const lightThemeActive = theme === 'light';
  const rainActive = rainLayer?.style.display !== 'none';
  themeToggle?.setAttribute('aria-pressed', String(lightThemeActive));
  themeToggle?.setAttribute('aria-label', lightThemeActive ? 'Use dark theme' : 'Use light theme');
  rainToggle?.setAttribute('aria-pressed', String(rainActive));
  rainToggle?.setAttribute('aria-label', rainActive ? 'Turn off rain effect' : 'Turn on rain effect');
}

function setTheme(theme, { announceChange = true } = {}) {
  root.setAttribute('data-theme', theme);
  safeStorage.set(THEME_KEY, theme);

  const icon = themeToggle?.querySelector('i');
  if (icon) {
    icon.className = theme === 'light' ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
  }

  updateToggleStates();
  if (announceChange) {
    announce(theme === 'light' ? 'Light theme enabled' : 'Dark theme enabled');
  }
}

function createRain(count = window.innerWidth < 768 ? 36 : 72) {
  if (!rainLayer) return;
  rainLayer.innerHTML = '';
  if (reducedMotionQuery.matches || rainLayer.style.display === 'none') return;

  for (let index = 0; index < count; index += 1) {
    const drop = document.createElement('span');
    drop.className = 'rain-drop';
    drop.style.left = `${Math.random() * 100}%`;
    drop.style.height = `${12 + Math.random() * 22}px`;
    drop.style.opacity = `${0.12 + Math.random() * 0.35}`;
    drop.style.animationDuration = `${0.9 + Math.random() * 1.4}s`;
    drop.style.animationDelay = `${Math.random() * 1.2}s`;
    rainLayer.appendChild(drop);
  }
}

function setRain(active, { announceChange = true } = {}) {
  if (!rainLayer) return;
  const shouldRun = active && !reducedMotionQuery.matches;
  rainLayer.style.display = shouldRun ? 'block' : 'none';
  if (shouldRun && !rainLayer.childElementCount) createRain();
  safeStorage.set(RAIN_KEY, shouldRun ? 'on' : 'off');
  updateToggleStates();
  if (announceChange) {
    announce(shouldRun ? 'Rain effect on' : 'Rain effect off');
  }
}

function showHeroSlide(index) {
  heroSlides.forEach((slide, slideIndex) => {
    slide.classList.toggle('is-active', slideIndex === index);
  });
  heroDots.forEach((dot, dotIndex) => {
    dot.classList.toggle('is-active', dotIndex === index);
  });
}

function startHeroSlideshow() {
  if (heroTimer || heroSlides.length < 2 || reducedMotionQuery.matches) return;
  heroTimer = window.setInterval(() => {
    heroSlideIndex = (heroSlideIndex + 1) % heroSlides.length;
    showHeroSlide(heroSlideIndex);
  }, 3200);
}

function stopHeroSlideshow() {
  if (!heroTimer) return;
  clearInterval(heroTimer);
  heroTimer = null;
}

function setMarqueePaused(paused, { announceChange = true } = {}) {
  marqueeTrack?.classList.toggle('is-paused', paused);
  marqueeToggle?.setAttribute('aria-pressed', String(paused));
  marqueeToggle?.setAttribute('aria-label', paused ? 'Resume scrolling portfolio themes' : 'Pause scrolling portfolio themes');
  const icon = marqueeToggle?.querySelector('i');
  if (icon) icon.className = paused ? 'fa-solid fa-play' : 'fa-solid fa-pause';
  if (announceChange) announce(paused ? 'Scrolling portfolio themes paused' : 'Scrolling portfolio themes resumed');
}

function setupMarquee() {
  if (!marqueeToggle || !marqueeTrack) return;
  setMarqueePaused(reducedMotionQuery.matches, { announceChange: false });
  marqueeToggle.addEventListener('click', () => {
    setMarqueePaused(!marqueeTrack.classList.contains('is-paused'));
  });
}

function updateHero() {
  if (!heroSection) return;

  if (isTabletMode() || reducedMotionQuery.matches) {
    if (heroBootState) {
      heroBootState.style.opacity = '0';
      heroBootState.style.visibility = 'hidden';
    }
    if (heroLogoState) {
      heroLogoState.style.opacity = '0';
      heroLogoState.style.visibility = 'hidden';
    }
    if (heroGallery) {
      heroGallery.style.opacity = '1';
      heroGallery.style.visibility = 'visible';
    }
    if (heroGalleryUi) {
      heroGalleryUi.style.opacity = '1';
      heroGalleryUi.style.visibility = 'visible';
    }
    if (heroCloseCover) {
      heroCloseCover.style.opacity = '0';
      heroCloseCover.style.transform = 'none';
    }
    if (heroDevice) {
      heroDevice.style.transform = 'none';
      heroDevice.classList.remove('is-closing', 'is-closed');
    }
    if (heroDeviceWrap) {
      heroDeviceWrap.style.opacity = '1';
      heroDeviceWrap.style.pointerEvents = 'auto';
    }
    root.style.setProperty('--hero-progress', '1');
    if (!reducedMotionQuery.matches) startHeroSlideshow();
    return;
  }

  const rect = heroSection.getBoundingClientRect();
  const total = Math.max(heroSection.offsetHeight - window.innerHeight, 1);
  const progress = clamp(-rect.top / total, 0, 1);

  const bootOut = clamp((progress - 0.18) / 0.14, 0, 1);
  const logoIn = clamp((progress - 0.28) / 0.12, 0, 1);
  const logoOut = clamp((progress - 0.44) / 0.12, 0, 1);
  const logoOpacity = logoIn * (1 - logoOut);
  const galleryIn = clamp((progress - 0.54) / 0.16, 0, 1);
  const closeProgress = clamp((progress - 0.84) / 0.1, 0, 1);
  const fadeOut = clamp((progress - 0.95) / 0.05, 0, 1);

  if (heroBootState) {
    const opacity = Math.max(0, 1 - bootOut) * (1 - closeProgress);
    heroBootState.style.opacity = opacity;
    heroBootState.style.visibility = opacity > 0.02 ? 'visible' : 'hidden';
    heroBootState.style.transform = `translateY(${bootOut * 10}px) scale(${1 - bootOut * 0.03})`;
  }

  if (heroLogoState) {
    heroLogoState.style.opacity = logoOpacity;
    heroLogoState.style.visibility = logoOpacity > 0.02 ? 'visible' : 'hidden';
    heroLogoState.style.transform = `translateY(${16 - logoIn * 16 + logoOut * 8}px) scale(${0.95 + logoIn * 0.06 - logoOut * 0.03})`;
  }

  if (heroGallery) {
    const opacity = galleryIn * (1 - closeProgress) * (1 - fadeOut * 0.9);
    heroGallery.style.opacity = opacity;
    heroGallery.style.visibility = opacity > 0.02 ? 'visible' : 'hidden';

    if (opacity > 0.08) {
      startHeroSlideshow();
    } else {
      stopHeroSlideshow();
      heroSlideIndex = 0;
      showHeroSlide(0);
    }
  }

  if (heroGalleryUi) {
    const opacity = clamp((galleryIn - 0.08) / 0.22, 0, 1) * (1 - closeProgress) * (1 - fadeOut * 0.9);
    heroGalleryUi.style.opacity = opacity;
    heroGalleryUi.style.visibility = opacity > 0.02 ? 'visible' : 'hidden';
  }

  if (heroDevice) {
    const translateY = 20 - galleryIn * 12 + closeProgress * 8 + fadeOut * 36;
    const scale = 0.98 + galleryIn * 0.02 - fadeOut * 0.06;
    heroDevice.style.transform = `translateY(${translateY}px) scale(${scale})`;
    heroDevice.classList.toggle('is-closing', closeProgress > 0.02);
    heroDevice.classList.toggle('is-closed', closeProgress > 0.92);
  }

  if (heroCloseCover) {
    const travel = -108 + closeProgress * 108;
    const angle = -96 + closeProgress * 96;
    heroCloseCover.style.transform = `perspective(1800px) translateY(${travel}%) rotateX(${angle}deg)`;
    heroCloseCover.style.opacity = closeProgress > 0.02 ? 1 : 0;
  }

  if (heroDeviceWrap) {
    heroDeviceWrap.style.opacity = 1 - fadeOut;
    heroDeviceWrap.style.pointerEvents = fadeOut > 0.96 ? 'none' : 'auto';
  }
}

function setActiveNav(currentNavKey) {
  if (activeNavKey === currentNavKey) return;
  activeNavKey = currentNavKey;
  navLinks.forEach((link) => {
    const targetNavKey = link.dataset.nav || link.getAttribute('href').replace('#', '');
    const active = Boolean(currentNavKey) && targetNavKey === currentNavKey;
    link.classList.toggle('is-active', active);

    if (active) {
      link.setAttribute('aria-current', 'location');
    } else {
      link.removeAttribute('aria-current');
    }
  });
}

function updateActiveNav() {
  if (!navSections.length) return;
  const headerHeight = qs('.site-header')?.offsetHeight || 88;
  const focusLine = headerHeight + 32;
  const getLayoutTop = (element) => {
    let top = 0;
    let current = element;
    while (current) {
      top += current.offsetTop || 0;
      current = current.offsetParent;
    }
    return top;
  };
  const passedSections = navSections.filter((section) => getLayoutTop(section) <= window.scrollY + focusLine);
  const atPageEnd = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2;
  const currentSection = atPageEnd ? navSections.at(-1) : (passedSections.at(-1) || null);
  setActiveNav(currentSection?.dataset.nav || null);
}

function setupActiveNavigation() {
  updateActiveNav();
}

function setupReveal() {
  if (reducedMotionQuery.matches || !('IntersectionObserver' in window)) {
    revealItems.forEach((item) => item.classList.add('is-visible'));
    return;
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.14, rootMargin: '0px 0px -40px 0px' });

  revealItems.forEach((item) => observer.observe(item));
}

function setLauncherState(projectKey) {
  activeProjectKey = projectKey;
  projectLaunchers.forEach((launcher) => {
    launcher.classList.toggle('is-active', launcher.dataset.project === projectKey);
  });
}


function setCaseStudyCardState(projectKey) {
  activeCaseStudyKey = projectKey || null;
  caseStudyCards.forEach((card) => {
    const active = Boolean(projectKey) && card.dataset.caseStudy === projectKey;
    card.closest('.real-work-card')?.classList.toggle('is-active', active);
    card.setAttribute('aria-expanded', String(active));
  });
}

function showCaseStudyDetail() {
  if (!realWorkDetail) return;
  realWorkDetail.hidden = false;
  realWorkDetail.setAttribute('aria-hidden', 'false');
}

function hideCaseStudyDetail({ clearSelection = false, announceMessage = false, restoreFocus = false } = {}) {
  if (clearSelection) {
    window.scrollTo({ top: window.scrollY, behavior: 'auto' });
  }

  if (realWorkDetail) {
    realWorkDetail.hidden = true;
    realWorkDetail.setAttribute('aria-hidden', 'true');
  }

  if (clearSelection) {
    activeCaseStudyKey = null;
    setCaseStudyCardState(null);
  }

  if (announceMessage) {
    announce('Case study hidden');
  }

  if (restoreFocus && caseStudyReturnFocus?.isConnected) {
    caseStudyReturnFocus.focus();
  }

  if (clearSelection) {
    caseStudyReturnFocus = null;
  }

  window.PortfolioMotion?.refresh?.();
}

function stepCaseStudyImage(direction = 1) {
  const study = caseStudies[activeCaseStudyKey];
  if (!study?.images?.length) return;
  const total = study.images.length;
  const nextIndex = (activeCaseStudyImageIndex + direction + total) % total;
  setFeaturedCaseStudyImage(activeCaseStudyKey, nextIndex);
}

function setFeaturedCaseStudyImage(projectKey, imageIndex) {
  const study = caseStudies[projectKey];
  const image = study?.images?.[imageIndex];
  if (!study || !image) return;

  activeCaseStudyImageIndex = imageIndex;

  if (realWorkFeatured && !reducedMotionQuery.matches) {
    realWorkFeatured.classList.remove('is-switching');
    void realWorkFeatured.offsetWidth;
    realWorkFeatured.classList.add('is-switching');
    window.setTimeout(() => realWorkFeatured.classList.remove('is-switching'), 520);
  }

  if (realWorkFeaturedImage) {
    realWorkFeaturedImage.src = image.src;
    realWorkFeaturedImage.alt = image.alt;
    realWorkFeaturedImage.width = image.width;
    realWorkFeaturedImage.height = image.height;
  }

  if (realWorkFeaturedLabel) realWorkFeaturedLabel.textContent = image.label;
  if (realWorkFeaturedCaption) realWorkFeaturedCaption.textContent = image.caption;
  if (realWorkCarouselLabel) realWorkCarouselLabel.textContent = image.label;
  if (realWorkImageCounter) realWorkImageCounter.textContent = `${imageIndex + 1} / ${study.images.length}`;
  if (realWorkProgressFill) {
    realWorkProgressFill.style.setProperty('--image-progress', `${((imageIndex + 1) / study.images.length) * 100}%`);
    realWorkProgressFill.parentElement?.style.setProperty('--image-progress', `${((imageIndex + 1) / study.images.length) * 100}%`);
  }
  if (realWorkPrev) realWorkPrev.setAttribute('aria-label', `Show previous ${study.title} project image`);
  if (realWorkNext) realWorkNext.setAttribute('aria-label', `Show next ${study.title} project image`);

  if (galleryLightbox?.open) {
    updateLightboxImage(study, image);
  }
}

function updateLightboxImage(study, image) {
  if (galleryLightboxImage) {
    galleryLightboxImage.src = image.src;
    galleryLightboxImage.alt = image.alt;
    galleryLightboxImage.width = image.width;
    galleryLightboxImage.height = image.height;
  }
  if (galleryLightboxCaption) {
    galleryLightboxCaption.textContent = `${study.title} — ${image.label}. ${image.caption}`;
  }
  galleryLightboxPrev?.setAttribute('aria-label', `Show previous ${study.title} project image`);
  galleryLightboxNext?.setAttribute('aria-label', `Show next ${study.title} project image`);
}

function openGalleryLightbox(projectKey = activeCaseStudyKey, imageIndex = activeCaseStudyImageIndex) {
  const study = caseStudies[projectKey];
  const image = study?.images?.[imageIndex];
  if (!study || !image || !galleryLightbox) return;

  lightboxReturnFocus = realWorkFeatured;
  setFeaturedCaseStudyImage(projectKey, imageIndex);
  updateLightboxImage(study, image);
  if (typeof galleryLightbox.showModal === 'function') {
    galleryLightbox.showModal();
  } else {
    galleryLightbox.setAttribute('open', '');
  }
  galleryLightboxClose?.focus();
}

function closeGalleryLightbox({ announceMessage = false } = {}) {
  if (!galleryLightbox?.open && !galleryLightbox?.hasAttribute('open')) return;
  if (typeof galleryLightbox.close === 'function') {
    galleryLightbox.close();
  } else {
    galleryLightbox.removeAttribute('open');
  }
  if (announceMessage) announce('Expanded project image closed');
  if (lightboxReturnFocus?.isConnected) lightboxReturnFocus.focus();
  lightboxReturnFocus = null;
}

function renderCaseStudy(projectKey) {
  const study = caseStudies[projectKey];
  if (!study) return;

  showCaseStudyDetail();
  setCaseStudyCardState(projectKey);

  if (realWorkType) realWorkType.textContent = study.cardKicker;
  if (realWorkTitle) realWorkTitle.textContent = study.title;
  if (realWorkSummary) realWorkSummary.textContent = study.summary;
  if (realWorkFeel) realWorkFeel.textContent = study.feel;
  if (realWorkWhy) realWorkWhy.textContent = study.why;
  if (realWorkDecisions) realWorkDecisions.textContent = study.decisions;

  if (realWorkChips) {
    realWorkChips.innerHTML = study.chips
      .map((chip) => `<span class="real-work-chip">${chip}</span>`)
      .join('');
  }

  const project = projects[projectKey];
  if (realWorkLiveLink && project) {
    realWorkLiveLink.href = project.url;
    realWorkLiveLink.setAttribute('aria-label', `Open the ${project.title} live website in a new tab`);
  }

  setFeaturedCaseStudyImage(projectKey, 0);
  setLauncherState(projectKey);
  window.PortfolioMotion?.refresh?.();

  window.requestAnimationFrame(() => {
    if (activeCaseStudyKey !== projectKey || realWorkDetail?.hidden) return;
    realWorkDetail?.scrollIntoView({ behavior: reducedMotionQuery.matches ? 'auto' : 'smooth', block: 'start' });
    realWorkTitle?.focus({ preventScroll: true });
  });
}

function setupCaseStudies() {
  setCaseStudyCardState(null);
  hideCaseStudyDetail({ clearSelection: false, announceMessage: false });

  caseStudyCards.forEach((card) => {
    card.addEventListener('click', () => {
      const projectKey = card.dataset.caseStudy;
      if (!projectKey) return;

      if (projectKey === activeCaseStudyKey && realWorkDetail && !realWorkDetail.hidden) {
        hideCaseStudyDetail({ clearSelection: true, announceMessage: true });
        return;
      }

      caseStudyReturnFocus = card;
      renderCaseStudy(projectKey);
      announce(`${caseStudies[projectKey].title} case study opened`);
    });
  });

  realWorkDetailClose?.addEventListener('click', () => {
    hideCaseStudyDetail({ clearSelection: true, announceMessage: true, restoreFocus: true });
  });

  realWorkPrev?.addEventListener('click', () => {
    stepCaseStudyImage(-1);
  });

  realWorkNext?.addEventListener('click', () => {
    stepCaseStudyImage(1);
  });

  realWorkFeatured?.addEventListener('click', () => {
    if (!activeCaseStudyKey) return;
    openGalleryLightbox(activeCaseStudyKey, activeCaseStudyImageIndex);
  });

  galleryLightbox?.addEventListener('click', (event) => {
    if (event.target === galleryLightbox) {
      closeGalleryLightbox({ announceMessage: true });
    }
  });

  galleryLightbox?.addEventListener('cancel', (event) => {
    event.preventDefault();
    closeGalleryLightbox({ announceMessage: true });
  });

  galleryLightboxClose?.addEventListener('click', () => closeGalleryLightbox({ announceMessage: true }));
  galleryLightboxPrev?.addEventListener('click', () => stepCaseStudyImage(-1));
  galleryLightboxNext?.addEventListener('click', () => stepCaseStudyImage(1));
}


function showBrowserOverlay(title, copy) {
  window.clearTimeout(overlayTimer);
  browserOverlayTitle && (browserOverlayTitle.textContent = title);
  browserOverlayCopy && (browserOverlayCopy.textContent = copy);
  browserOverlay?.classList.remove('is-hidden');

  overlayTimer = window.setTimeout(() => {
    if (!browserOverlay?.classList.contains('is-hidden')) {
      browserOverlayTitle && (browserOverlayTitle.textContent = 'Still loading?');
      browserOverlayCopy && (browserOverlayCopy.textContent = 'If the preview stays blank or a browser policy blocks embedding, open the project in a new tab with the button below.');
    }
  }, 3500);
}

function hideBrowserOverlay() {
  window.clearTimeout(overlayTimer);
  browserOverlay?.classList.add('is-hidden');
}

function closeProjectWindow({ announceMessage = true, restoreFocus = true } = {}) {
  const wasVisible = projectWindow?.classList.contains('is-visible');
  projectWindow?.classList.remove('is-visible', 'is-expanded', 'is-minimized');
  workspaceDevice?.classList.remove('has-open-project');
  projectWindow?.setAttribute('aria-hidden', 'true');
  projectExpand?.setAttribute('aria-pressed', 'false');
  if (announceMessage && wasVisible) announce('Project window closed');
  if (restoreFocus && wasVisible && projectReturnFocus?.isConnected) {
    projectReturnFocus.focus();
  }
  if (wasVisible) projectReturnFocus = null;
}

function setProject(projectKey, options = {}) {
  const project = projects[projectKey];
  if (!project || !workspacePowered) return;

  const { forceReload = false } = options;
  const nextUrl = project.url;
  const currentSrc = isBrowserAudit ? (projectFrame?.dataset.requestedSrc || '') : (projectFrame?.getAttribute('src') || '');

  setLauncherState(projectKey);
  if (projectTitle) projectTitle.textContent = project.title;
  if (projectKicker) projectKicker.textContent = project.kicker;
  if (projectAddress) projectAddress.textContent = nextUrl;
  if (browserOpenButton) {
    browserOpenButton.href = nextUrl;
    browserOpenButton.setAttribute('aria-label', `Open the ${project.title} live website in a new tab`);
  }
  if (browserFallbackLink) {
    browserFallbackLink.href = nextUrl;
    browserFallbackLink.setAttribute('aria-label', `Open the ${project.title} live website in a new tab`);
  }
  if (projectFrame) projectFrame.title = `${project.title} live website preview`;

  projectWindow?.classList.remove('is-minimized');
  projectWindow?.classList.add('is-visible');
  workspaceDevice?.classList.add('has-open-project');
  projectWindow?.setAttribute('aria-hidden', 'false');

  const shouldLoad = Boolean(projectFrame && (forceReload || currentSrc !== nextUrl));

  if (shouldLoad) {
    showBrowserOverlay('Loading live preview…', 'If the preview takes too long or a site blocks embedding, use the button below to open the project directly.');
    if (isBrowserAudit) {
      projectFrame.dataset.requestedSrc = nextUrl;
      projectFrame.src = 'about:blank';
    } else {
      projectFrame.src = nextUrl;
    }
  } else {
    hideBrowserOverlay();
  }

  announce(`${project.title} opened`);
  projectClose?.focus();
}

function powerOffWorkspace({ restoreFocus = true } = {}) {
  workspacePowered = false;
  workspaceDevice?.classList.remove('is-powered');
  workspaceTurnOn?.setAttribute('aria-pressed', 'false');
  workspacePower?.setAttribute('aria-pressed', 'false');
  closeProjectWindow({ announceMessage: false, restoreFocus: false });
  announce('Live project browser turned off');
  if (restoreFocus) workspaceTurnOn?.focus();
}

function powerOnWorkspace() {
  if (!workspaceDevice?.classList.contains('is-ready')) return;
  workspacePowered = true;
  workspaceDevice?.classList.add('is-powered');
  workspaceTurnOn?.setAttribute('aria-pressed', 'true');
  workspacePower?.setAttribute('aria-pressed', 'true');
  closeProjectWindow({ announceMessage: false, restoreFocus: false });
  setLauncherState(activeProjectKey);
  announce('Live project browser turned on');
}

function setupWorkspace() {
  projectLaunchers.forEach((button) => {
    button.addEventListener('click', () => {
      if (!workspacePowered || !button.dataset.project) return;
      projectReturnFocus = button;
      setProject(button.dataset.project);
    });
  });

  workspaceTurnOn?.addEventListener('click', powerOnWorkspace);
  workspacePower?.addEventListener('click', () => powerOffWorkspace());

  projectMinimize?.addEventListener('click', () => {
    projectWindow?.classList.add('is-minimized');
    projectWindow?.setAttribute('aria-hidden', 'true');
    workspaceDevice?.classList.remove('has-open-project');
    announce('Project window minimized');
    if (projectReturnFocus?.isConnected) projectReturnFocus.focus();
  });

  projectExpand?.addEventListener('click', () => {
    projectWindow?.classList.toggle('is-expanded');
    const expanded = projectWindow?.classList.contains('is-expanded');
    projectExpand.setAttribute('aria-pressed', String(Boolean(expanded)));
    announce(expanded ? 'Project window expanded' : 'Project window restored');
  });

  projectClose?.addEventListener('click', () => {
    closeProjectWindow({ announceMessage: true, restoreFocus: true });
  });

  browserReloadButton?.addEventListener('click', () => {
    if (!activeProjectKey) return;
    setProject(activeProjectKey, { forceReload: true });
    announce('Project reloaded');
  });

  projectFrame?.addEventListener('load', () => {
    hideBrowserOverlay();
    announce('Live preview loaded');
  });
}

function updateWorkspace() {
  if (!workspaceStage || !workspaceLaptop || !workspaceDevice) return;

  if (isTabletMode()) {
    workspaceLaptop.style.setProperty('--open', '1');
    workspaceLaptop.style.setProperty('--scale', '1');
    workspaceLaptop.style.setProperty('--spin', '0deg');
    workspaceLaptop.style.setProperty('--y', '0px');

    workspaceDevice.classList.add('is-open', 'is-ready');
    workspaceDevice.classList.toggle('is-powered', workspacePowered);
    return;
  }

  const rect = workspaceStage.getBoundingClientRect();
  const total = Math.max(workspaceStage.offsetHeight - window.innerHeight, 1);
  const raw = clamp(-rect.top / total, 0, 1);

  let open = 0;
  if (raw < 0.28) open = raw / 0.28;
  else if (raw > 0.78) open = Math.max(0, 1 - (raw - 0.78) / 0.22);
  else open = 1;

  const scale = 0.7 + open * 0.38;
  const spin = -10 + open * 10;
  const y = 72 - open * 72;

  workspaceLaptop.style.setProperty('--open', open.toFixed(3));
  workspaceLaptop.style.setProperty('--scale', scale.toFixed(3));
  workspaceLaptop.style.setProperty('--spin', `${spin.toFixed(2)}deg`);
  workspaceLaptop.style.setProperty('--y', `${y.toFixed(1)}px`);

  const isOpen = open > 0.72;
  const ready = open > 0.9;

  workspaceDevice.classList.toggle('is-open', isOpen);
  workspaceDevice.classList.toggle('is-ready', ready);
  workspaceDevice.classList.toggle('is-powered', ready && workspacePowered);

  if (!ready && workspacePowered) {
    powerOffWorkspace({ restoreFocus: false });
  }
}

function setupMobileNav() {
  if (!navToggle || !navMenu) return;

  const closeMenu = ({ restoreFocus = false } = {}) => {
    if (!navMenu.classList.contains('is-open')) return;
    navMenu.classList.remove('is-open');
    navToggle.setAttribute('aria-expanded', 'false');
    navToggle.setAttribute('aria-label', 'Open navigation');
    if (restoreFocus) navToggle.focus();
  };

  navToggle.addEventListener('click', () => {
    const wasOpen = navMenu.classList.contains('is-open');
    if (wasOpen) {
      closeMenu({ restoreFocus: true });
      return;
    }

    navMenu.classList.add('is-open');
    const open = true;
    navToggle.setAttribute('aria-expanded', String(open));
    navToggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    navMenu.querySelector('a')?.focus({ preventScroll: true });
  });

  navMenu.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => {
      closeMenu();
      const target = qs(link.getAttribute('href'));
      window.setTimeout(() => target?.focus({ preventScroll: true }), reducedMotionQuery.matches ? 0 : 450);
    });
  });

  document.addEventListener('pointerdown', (event) => {
    if (!navMenu.classList.contains('is-open')) return;
    if (navMenu.contains(event.target) || navToggle.contains(event.target)) return;
    closeMenu();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && navMenu.classList.contains('is-open')) {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeMenu({ restoreFocus: true });
    }
  });
}

function setupForm() {
  if (!form || !formSuccess) return;

  const nameField = qs('#contact-name', form);
  const emailField = qs('#contact-email', form);
  const typeField = qs('#contact-project-type', form);
  const messageField = qs('#contact-message', form);
  const requiredFields = [nameField, emailField, messageField].filter(Boolean);

  const setFieldError = (field, message = '') => {
    const error = qs(`#${field.id}-error`, form);
    field.setAttribute('aria-invalid', String(Boolean(message)));
    field.closest('.form-field')?.classList.toggle('has-error', Boolean(message));
    if (error) error.textContent = message;
    return !message;
  };

  const validateField = (field) => {
    const value = field.value.trim();
    if (!value) return setFieldError(field, 'This field is required.');
    if (field.type === 'email' && field.validity.typeMismatch) {
      return setFieldError(field, 'Enter a valid email address.');
    }
    if (field === messageField && value.length < 10) {
      return setFieldError(field, 'Add at least 10 characters so Leslie has enough context.');
    }
    return setFieldError(field);
  };

  requiredFields.forEach((field) => {
    field.addEventListener('blur', () => validateField(field));
    field.addEventListener('input', () => {
      if (field.getAttribute('aria-invalid') === 'true') validateField(field);
      formSuccess.hidden = true;
      formSuccess.classList.remove('is-visible');
    });
  });

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const results = requiredFields.map(validateField);
    if (results.some((valid) => !valid)) {
      requiredFields.find((field) => field.getAttribute('aria-invalid') === 'true')?.focus();
      announce('Please correct the highlighted contact form fields');
      return;
    }

    const senderName = nameField.value.trim();
    const senderEmail = emailField.value.trim();
    const projectType = typeField?.value || 'Portfolio enquiry';
    const message = messageField.value.trim();
    const subject = `${projectType} — portfolio enquiry from ${senderName}`;
    const body = `Name: ${senderName}\nEmail: ${senderEmail}\nProject type: ${projectType}\n\n${message}`;

    formSuccess.hidden = false;
    formSuccess.classList.add('is-visible');
    announce('Opening your email application with the completed draft');
    window.location.href = `mailto:asamoah.leslie@gmail.com?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  });
}

function handleScroll() {
  updateHero();
  updateWorkspace();
}

function requestScrollUpdate() {
  updateActiveNav();
  if (scrollTicking) return;
  scrollTicking = true;
  window.requestAnimationFrame(() => {
    handleScroll();
    scrollTicking = false;
  });
}

function init() {
  const storedTheme = safeStorage.get(THEME_KEY, 'dark');
  const storedRain = safeStorage.get(RAIN_KEY, 'off');

  setTheme(storedTheme, { announceChange: false });
  setRain(storedRain === 'on', { announceChange: false });
  showHeroSlide(0);
  motionEnhanced = Boolean(window.PortfolioMotion?.init?.());
  if (!motionEnhanced) setupReveal();
  setupMarquee();
  setupCaseStudies();
  setupWorkspace();
  setupMobileNav();
  setupActiveNavigation();
  setupForm();
  setLauncherState(activeProjectKey);

  workspacePowered = false;
  handleScroll();

  themeToggle?.addEventListener('click', () => {
    setTheme(root.getAttribute('data-theme') === 'light' ? 'dark' : 'light');
  });

  rainToggle?.addEventListener('click', () => {
    setRain(rainLayer?.style.display === 'none');
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      if (navMenu?.classList.contains('is-open')) return;

      if (galleryLightbox?.open) {
        event.preventDefault();
        closeGalleryLightbox({ announceMessage: true });
        return;
      }

      if (realWorkDetail && !realWorkDetail.hidden) {
        event.preventDefault();
        hideCaseStudyDetail({ clearSelection: true, announceMessage: true, restoreFocus: true });
        return;
      }

      if (projectWindow?.classList.contains('is-visible')) {
        event.preventDefault();
        closeProjectWindow({ announceMessage: true, restoreFocus: true });
      }
      return;
    }

    const galleryKeyboardActive = galleryLightbox?.open || realWorkDetail?.contains(document.activeElement);
    if (galleryKeyboardActive) {
      if (event.key === 'ArrowRight') {
        event.preventDefault();
        stepCaseStudyImage(1);
      } else if (event.key === 'ArrowLeft') {
        event.preventDefault();
        stepCaseStudyImage(-1);
      }
    }
  });

  reducedMotionQuery.addEventListener?.('change', (event) => {
    window.PortfolioMotion?.destroy?.();
    motionEnhanced = false;
    if (event.matches) {
      stopHeroSlideshow();
      setMarqueePaused(true, { announceChange: false });
      setRain(false, { announceChange: false });
    } else {
      motionEnhanced = Boolean(window.PortfolioMotion?.init?.());
      setMarqueePaused(false, { announceChange: false });
    }
    updateHero();
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stopHeroSlideshow();
    else updateHero();
  });
}

if (document.readyState === 'loading') {
  window.addEventListener('DOMContentLoaded', init, { once: true });
} else {
  init();
}

window.addEventListener('scroll', requestScrollUpdate, { passive: true });
window.addEventListener('resize', () => {
  if (window.innerWidth > 820 && navMenu?.classList.contains('is-open')) {
    navMenu.classList.remove('is-open');
    navToggle?.setAttribute('aria-expanded', 'false');
    navToggle?.setAttribute('aria-label', 'Open navigation');
  }

  window.clearTimeout(resizeTimer);
  resizeTimer = window.setTimeout(createRain, 140);
  window.PortfolioMotion?.refresh?.();
  requestScrollUpdate();
}, { passive: true });

})();
