'use strict';

const cvStatus = document.querySelector('#cv-status');
const printButton = document.querySelector('#cv-print');
const filterButtons = [...document.querySelectorAll('[data-skill-filter]')];
const skills = [...document.querySelectorAll('[data-skill-category]')];
const roleCards = [...document.querySelectorAll('.cv-role-card')];
const cvStats = [...document.querySelectorAll('[data-stat]')];
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function announceCv(message) {
  if (!cvStatus) return;
  cvStatus.textContent = '';
  window.requestAnimationFrame(() => { cvStatus.textContent = message; });
}

printButton?.addEventListener('click', () => window.print());

filterButtons.forEach((button) => {
  button.addEventListener('click', () => {
    const category = button.dataset.skillFilter;
    filterButtons.forEach((item) => {
      const active = item === button;
      item.classList.toggle('is-active', active);
      item.setAttribute('aria-pressed', String(active));
    });
    let visibleCount = 0;
    skills.forEach((skill) => {
      const categories = skill.dataset.skillCategory.split(' ');
      const visible = category === 'all' || categories.includes(category);
      skill.hidden = !visible;
      if (visible) visibleCount += 1;
    });
    announceCv(`${visibleCount} ${category === 'all' ? '' : category} skills shown`);
  });
});

roleCards.forEach((role) => {
  role.addEventListener('toggle', () => {
    if (!role.open) return;
    roleCards.forEach((other) => { if (other !== role) other.open = false; });
  });
});

function showFinalStats() {
  cvStats.forEach((stat) => {
    if (stat.dataset.stat === 'count') stat.textContent = `${stat.dataset.final}${stat.dataset.suffix || ''}`;
    if (stat.dataset.stat === 'ordinal') stat.textContent = '2nd';
    stat.classList.add('is-stat-visible');
    stat.querySelectorAll('i').forEach((part) => part.classList.add('is-stat-part-visible'));
  });
}

function animateCvStats() {
  if (!cvStats.length || reducedMotion) {
    showFinalStats();
    return;
  }

  cvStats.forEach((stat, statIndex) => {
    const startDelay = 420 + (statIndex * 220);
    window.setTimeout(() => stat.classList.add('is-stat-visible'), startDelay);

    if (stat.dataset.stat === 'count') {
      const finalValue = Number(stat.dataset.final);
      for (let value = 0; value <= finalValue; value += 1) {
        window.setTimeout(() => {
          stat.textContent = `${value}${value === finalValue ? stat.dataset.suffix || '' : ''}`;
          stat.animate([{ opacity: .2, transform: 'translateY(.35rem)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 260, easing: 'ease-out' });
        }, startDelay + (value * 260));
      }
    }

    if (stat.dataset.stat === 'ordinal') {
      window.setTimeout(() => {
        stat.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 180, fill: 'forwards' }).finished.then(() => {
          stat.textContent = '2nd';
          stat.animate([{ opacity: 0, transform: 'translateY(.35rem)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 320, easing: 'ease-out', fill: 'forwards' });
        });
      }, startDelay + 520);
    }

    if (stat.dataset.stat === 'ratio') {
      stat.querySelectorAll('i').forEach((part, partIndex) => {
        window.setTimeout(() => part.classList.add('is-stat-part-visible'), startDelay + (partIndex * 280));
      });
    }
  });
}

animateCvStats();
