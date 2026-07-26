# Leslie Tannor Portfolio

A responsive UI/UX portfolio presenting Leslie Tannor's work, design direction, experience, and contact information. The site is built as a static HTML, CSS, and JavaScript project with no build step.

## Featured projects

- **Akwaaba House** — a Ghanaian restaurant brand website and seven-screen case study.
- **GoldBar Fitness** — a fitness brand and product ecosystem presented across twelve screens.
- **WealthWise** — a fintech dashboard concept presented across six screens.

Each project includes a written case-study breakdown, uncropped screen gallery, previous/next controls, an enlarged-image dialog, and a link to the live website.

## Main features

- Scroll-led portfolio introduction and continuously looping themes ticker
- Desktop laptop presentation with an embedded live-project browser
- Direct live-project links on mobile and tablet layouts
- Responsive case-study cards and project-image navigation
- Dark/light theme and optional rain controls
- Contact form that opens the visitor's email application
- Separate design-process page

## Accessibility considerations

- Semantic landmarks, logical headings, descriptive page titles, and a skip link
- Keyboard-operable controls with visible focus indicators
- Focus management for mobile navigation, case studies, project windows, and the enlarged-image dialog
- Escape-key support for open navigation and image/case-study views
- Accessible names, live status announcements, image alternatives, and descriptive iframe titles
- Reduced-motion handling and a pause control for the scrolling ticker
- Protected external links using `noopener noreferrer`

The included browser audit checks both themes with axe-core and exercises the responsive interactions. Automated checks support, but do not replace, manual accessibility review.

## Local usage

Open `index.html` directly in a modern browser, or serve this folder with any local static-file server. No package installation or compilation is required.

On Windows, the included validation commands are:

```powershell
.\scripts\validate.ps1
.\scripts\browser-smoke.ps1
```

The browser audit uses an installed Microsoft Edge browser and writes ignored screenshots to `reports/`.

## Deployment

The project is made entirely of static files and can be deployed to a static host. No portfolio hosting-provider configuration was present in the source at the time of publication.

Live project destinations:

- [Akwaaba House](https://akwaabahouse.netlify.app/)
- [GoldBar Fitness](https://goldbarfitness.netlify.app/)
- [WealthWise](https://wealthwiselt.netlify.app/)
