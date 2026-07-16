// Phlox landing host — mounts the cinematic composition and scrubs it by scroll.
// Self-hosted runtime only. Any failure leaves html without .cine-on, so the
// static page keeps showing.

import { createRenderer } from './cine-runtime.js';
import { Root, DUR } from './comp.js';

/* ---- host: scroll → frame, responsive sizing, graceful enable -------------- */
function boot() {
  try {
    const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce) return;

    const mount = document.getElementById('cine-root');
    if (!mount) return;

    const lang = (document.documentElement.lang || 'en').toLowerCase().startsWith('ja') ? 'ja' : 'en';
    let dim = { w: window.innerWidth, h: window.innerHeight };
    let frame = -1;
    let degraded = false;
    let raf = 0;
    let resizeTimer;
    let renderer = createRenderer(mount);
    let degrade;

    const compositionSize = () => ({
      vw: Math.max(320, Math.round(dim.w)),
      vh: Math.max(480, Math.round(dim.h)),
    });

    const renderAt = (f) => {
      if (degraded) return;
      try {
        const { vw, vh } = compositionSize();
        renderer.render(Root(f, vw, vh, { lang }));
        frame = f;
      } catch (err) {
        degrade(err);
      }
    };

    const seekToScroll = () => {
      if (degraded) return;
      const el = document.scrollingElement || document.documentElement;
      const max = el.scrollHeight - window.innerHeight;
      const p = max > 0 ? Math.min(1, Math.max(0, el.scrollTop / max)) : 0;
      const next = Math.round(p * (DUR - 1));
      if (next !== frame) renderAt(next);
      if (el.scrollTop > 4) document.documentElement.classList.add('scrolled');
    };

    const onResize = () => {
      if (degraded) return;
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        if (degraded) return;
        const next = { w: window.innerWidth, h: window.innerHeight };
        if (next.w === dim.w && next.h === dim.h) return;
        dim = next;
        renderer.remount();
        renderAt(frame < 0 ? 0 : frame);
        seekToScroll();
      }, 150);
    };

    const onScroll = () => {
      if (degraded) return;
      if (!raf) {
        raf = requestAnimationFrame(() => {
          raf = 0;
          seekToScroll();
        });
      }
    };

    degrade = (err) => {
      if (degraded) return;
      degraded = true;
      document.documentElement.classList.remove('cine-on');
      console.error('[phlox cine] disabled:', err);
      window.removeEventListener('resize', onResize);
      window.removeEventListener('scroll', onScroll);
      cancelAnimationFrame(raf);
      clearTimeout(resizeTimer);
    };

    window.addEventListener('resize', onResize);
    window.addEventListener('scroll', onScroll, { passive: true });

    renderAt(0);
    document.documentElement.classList.add('cine-on');
    window.scrollTo(0, 0);
    setTimeout(seekToScroll, 60);

    document.querySelectorAll('#cine-nav a[data-seek]').forEach((a) => {
      a.addEventListener('click', (e) => {
        e.preventDefault();
        const el = document.scrollingElement || document.documentElement;
        const target = parseFloat(a.getAttribute('data-seek')) * (el.scrollHeight - window.innerHeight);
        window.scrollTo({ top: target, behavior: 'smooth' });
      });
    });
    const skip = document.getElementById('skip-btn');
    if (skip) {
      skip.addEventListener('click', () => {
        document.documentElement.classList.remove('cine-on');
        window.scrollTo(0, 0);
      });
    }

    return () => {
      window.removeEventListener('resize', onResize);
      window.removeEventListener('scroll', onScroll);
      cancelAnimationFrame(raf);
      clearTimeout(resizeTimer);
    };
  } catch (err) {
    document.documentElement.classList.remove('cine-on');
    console.error('[phlox cine] disabled:', err);
  }
}
boot();
