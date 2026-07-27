# Leslie Tannor — spatial portfolio

A responsive, editorial portfolio for Leslie Tannor: a UI/UX designer in progress, Enterprise Support Engineer, and technical implementation specialist. It pairs an immediate semantic introduction with scroll-led project storytelling, detailed case-study galleries, and a live-site browser experience.

## Architecture decision

The redesign deliberately remains a static HTML, CSS, and JavaScript site. The product has one primary page, one small supporting page, no server state, no routing requirement, and a compact content model. Migrating it to React, Astro, Vite, or Next.js would add a build/runtime layer without solving a current product constraint.

Motion is the one focused dependency:

- GSAP 3.15.0 and ScrollTrigger are pinned from jsDelivr for coordinated timelines and scroll-linked transforms.
- `js/motion.js` owns enhancement-only motion behind one `window.PortfolioMotion` namespace.
- `js/main.js` owns content data, navigation, accessibility state, forms, case studies, and the live-project workspace.
- Native browser scrolling remains in control. There is no smooth-scroll wrapper, scroll-jacking, WebGL, or Three.js scene.
- If GSAP is unavailable, or the visitor requests reduced motion, all important content remains visible and usable.

CSS transforms provide the spatial device and card treatment. A WebGL dependency was rejected because the visual system needs restrained depth, not a continuously rendered 3D world.

## Experience map

- Immediate hero with name, role, positioning, primary actions, and real project imagery
- Scroll-led hero presentation with restrained depth and a visible motion fallback
- Three real project cards with project-specific art direction
- Guided case-study detail, uncropped screen navigation, progress, and an enlarged-image dialog
- Explicitly revealed desktop laptop workspace that opens, powers on, launches projects, and closes cleanly from its power control
- Direct, touch-friendly live-project links on mobile and tablet
- Process and experience sections built from the portfolio's existing claims
- Honest contact form that validates locally and opens a prefilled draft in the visitor's email application; the site does not send or store submissions
- Dark/light theme and a user-controlled ticker

## Featured work

- **Akwaaba House** — Ghanaian restaurant brand website with a seven-screen case study
- **GoldBar Fitness** — fitness brand and product ecosystem with twelve screens
- **WealthWise** — finance platform concept with six screens

Live destinations:

- [Akwaaba House](https://akwaabahouse.netlify.app/)
- [GoldBar Fitness](https://goldbarfitness.netlify.app/)
- [WealthWise](https://wealthwiselt.netlify.app/)

## Accessibility and motion

The site includes semantic landmarks, logical headings, a skip link, visible focus, descriptive alternatives, protected external links, labelled form controls, associated validation errors, dialog and focus-return behavior, Escape-key support, and at least 44 px primary touch controls. Active navigation follows native scroll position; the heavier device and hero calculations are requestAnimationFrame-throttled.

`prefers-reduced-motion: reduce` removes the sticky cinematic sequence, footer crossfade, looping ticker, transforms, and reveal delays. The ticker also has a persistent pause control for visitors who do not use the operating-system preference.

## Local usage

No package installation or compilation is required. Open `index.html` in a modern browser, or serve the directory with any static-file server. Network access enables the pinned GSAP enhancement, Font Awesome icons, web fonts, and live-site previews; the portfolio's core content and interactions progressively fall back when those resources are unavailable.

On Windows:

```powershell
.\scripts\validate.ps1
.\scripts\browser-smoke.ps1
```

The static audit checks HTML structure, local references, case-study counts, image metadata, external-link safety, merge markers, CSS structure, and the retained PSD signature. The Edge audit covers 320, 375, 430, 768, 1024, 1280, 1440, and 1920 px viewports plus a 200% reflow equivalent; it exercises navigation, menus, focus, forms, galleries, live-project controls, reduced motion, accessibility-tree semantics, and axe-core in both themes. Ignored screenshots and diagnostics are written to `reports/`.

## Deployment

The project is static-host ready. No hosting-provider configuration is currently committed. Keep the pinned third-party URLs under review, and test the three live sites after deployment because iframe display can also be affected by a destination site's own embedding policy.
