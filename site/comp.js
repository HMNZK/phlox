// Phlox cinematic composition — scenes + Root. Imported by app.js (host).
// Copy is language-agnostic: Root receives { lang } and threads the matching
// COPY table (T) into every scene.

import { h, AbsoluteFill, interpolate, Easing } from './cine-runtime.js';

// Resolve assets relative to THIS module (site/comp.js), not the host document,
// so images load whether the page is /, /ja/, or served from any root.
const ASSET = (p) => new URL(p, import.meta.url).href;

/* ---- timeline + palette ---------------------------------------------------- */
export const FPS = 30;
export const DUR = 720;                       // frames; mapped onto the scroll track length
const C = {
  bg: '#0d0b14', card: '#15121f', border: '#2a2440',
  text: '#ece9f5', muted: '#a39fb8',
  accent: '#8b5cf6', a1: '#a855f7', a2: '#ec4899',
  run: '#34d399', wait: '#f59e0b', idle: '#6f6a8a',
};
const GRAD = `linear-gradient(135deg, ${C.a1} 0%, ${C.a2} 100%)`;
const GRAD_TEXT = { background: GRAD, WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent' };
const SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Hiragino Sans", "Noto Sans JP", Roboto, Helvetica, Arial, sans-serif';
const MONO = 'ui-monospace, "SF Mono", Menlo, monospace';
const DL = 'https://github.com/HMNZK/phlox/releases/latest/download/Phlox.dmg';

/* ---- copy (en / ja) -------------------------------------------------------- */
const COPY = {
  en: {
    cta: 'Download for macOS',
    hero: {
      l1: 'Ask one agent.', l2: 'It runs the rest.',
      sub: 'Give one agent the job. From there, agents manage agents — no opening window after window, no copy-pasting between them.',
      req: 'macOS 14 Sonoma or later · Apple Silicon · Signed & notarized',
    },
    window: { eyebrow: 'One window' },
    problem: {
      eyebrow: 'Before and after.', h: 'The days of managing it all yourself are over.',
      pains: [
        ['Opening window after window, starting each AI by hand.', 'Ask one, and it calls in the other AIs and manages the rest.'],
        ['No idea which AI is working and which is waiting.', 'Every status at a glance — a heads-up the moment you’re needed.'],
        ['Watching the screen just to catch when something finishes.', 'The AI watches for you. You move on to something else.'],
      ],
    },
    agents: {
      eyebrow: 'What you can do', h: 'Agents that manage agents.',
      lead: 'You ask one. It calls in the others, instructs them, and waits — all you do is supervise.',
      chip: '“Ship the release flow.”',
      claude: { name: 'Claude Code', run: 'managing the rest', done: 'wrapped up' },
      codex: { name: 'Codex', wait: 'waiting…', run: 'building', done: 'done' },
      cursor: { name: 'Cursor', wait: 'waiting…', run: 'editing', done: 'done' },
      done: '✓ all done — you get a notification',
    },
    features: {
      eyebrow: 'Everything in reach', h: 'All you do is supervise.',
      items: [
        ['01', 'One window', 'Claude Code, Codex and Cursor each run in their own pane, at the same time.'],
        ['02', 'Delegate, then wait', 'Say what you want. Completion is detected automatically — so you can move on.'],
        ['03', 'Status, always', 'Working, idle, or stuck on a question — detected automatically, with a notification.'],
        ['04', 'Usage at a glance', 'Each AI’s usage across 5-hour, weekly and total limits.'],
        ['05', 'Make it yours', 'Group by project, filter AIs, switch view modes (⌃⌘G), toggle the sidebar (⌘B).'],
      ],
      usage: [['Claude · 5h', 51], ['Codex · wk', 63], ['Cursor', 16]],
    },
    start: {
      eyebrow: 'Getting started', h: 'Three steps. That’s it.',
      steps: [
        ['1', 'Download and open', 'Grab the macOS app, drop it in Applications, and launch. Signed and notarized.'],
        ['2', 'Call up an AI', 'Pick Claude Code, Codex, or Cursor and start it.'],
        ['3', 'Say what you want', 'That AI calls in the others it needs and runs with it.'],
      ],
      copyright: '© 2026 Phlox · ', privacy: 'Privacy Policy', privacyHref: '/privacy',
    },
  },
  ja: {
    cta: 'macOS版をダウンロード',
    hero: {
      l1: '頼むのは、ひとり。', l2: '動くのは、チーム。',
      sub: '1体の AI に頼むだけ。あとは AI が AI を呼び出して進めます。画面を何枚も開くことも、コピペで受け渡すことも、もうありません。',
      req: 'macOS 14 Sonoma 以降 · Apple Silicon · 署名・公証済み',
    },
    window: { eyebrow: 'ひとつの画面' },
    problem: {
      eyebrow: 'これまでと、これから。', h: '全てを人間が管理する時代は終わり。',
      pains: [
        ['画面を何枚も開いて、AI を一つずつ起動。', '一人に頼めば、その AI が他の AI を呼び出し、管理します。'],
        ['どの AI が動いていて、どれが待っているのか分からない。', 'すべての状態がひと目で。手が要るときは、知らせます。'],
        ['終わったか確かめるために、画面を見張りつづける。', '完了は AI が見届けます。あなたは、別のことを。'],
      ],
    },
    agents: {
      eyebrow: 'できること', h: 'AI が AI を管理する。',
      lead: '頼むのは、ひとりだけ。その AI がほかを呼び出し、指示し、待ちます。あなたは監督するだけ。',
      chip: '「リリースまで通して。」',
      claude: { name: 'Claude Code', run: '進行を管理中', done: '完了' },
      codex: { name: 'Codex', wait: '待機中…', run: '実装中', done: '完了' },
      cursor: { name: 'Cursor', wait: '待機中…', run: '編集中', done: '完了' },
      done: '✓ すべて完了 — 通知でお知らせ',
    },
    features: {
      eyebrow: '手の届くところに', h: 'あなたは監督するだけ。',
      items: [
        ['01', 'ひとつの画面', 'Claude Code・Codex・Cursor が、それぞれの画面で同時に動く。'],
        ['02', '頼んで、待つだけ', '「これをやって」と伝えるだけ。完了は自動で見分け、次の作業へ。'],
        ['03', 'つねに状態が見える', '動作中・待機中・入力待ち。自動で見分け、手が要れば通知。'],
        ['04', '残量がひと目で', '各 AI の使用量を、5時間・週・合計で。'],
        ['05', '自分仕様に', 'プロジェクトでまとめ、AI を絞り、表示を切替（⌃⌘G）、サイドバー開閉（⌘B）。'],
      ],
      usage: [['Claude · 5時間', 51], ['Codex · 週', 63], ['Cursor', 16]],
    },
    start: {
      eyebrow: 'はじめ方', h: '3ステップで、すぐに。',
      steps: [
        ['1', 'ダウンロードして開く', 'macOS 版をアプリケーションに入れて起動するだけ。署名・公証済み。'],
        ['2', 'AI を呼び出す', 'Claude Code・Codex・Cursor から選んで起動。'],
        ['3', 'やりたいことを伝える', 'あとは必要な AI を呼び出して進めます。終わったら通知。'],
      ],
      copyright: '© 2026 Phlox · ', privacy: 'プライバシーポリシー', privacyHref: '/ja/privacy',
    },
  },
};

const cl = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' };
const ease = { ...cl, easing: Easing.out(Easing.cubic) };
const px = (vw, min, f, max) => Math.max(min, Math.min(max, vw * f));
const fade = (f, a, b, c, d) => interpolate(f, [a, b, c, d], [0, 1, 1, 0], cl);
const seen = (f, s, e) => interpolate(f, [s, e], [0, 1], cl);
const rise = (f, s, e, d) => interpolate(f, [s, e], [d, 0], ease);

/* scene windows on the master timeline (in / hold / out) */
const SC = {
  hero:     [0, 16, 96, 124],
  window:   [112, 142, 214, 238],
  problem:  [226, 256, 340, 364],
  agents:   [352, 388, 470, 496],
  features: [486, 516, 600, 624],
  start:    [612, 648, 720, 720],
};

/* ---- small building blocks ------------------------------------------------- */
function Eyebrow({ text, vw, center }) {
  return h('div', {
    style: {
      display: 'inline-flex', alignItems: 'center', gap: 10, justifyContent: center ? 'center' : 'flex-start',
      font: `600 ${px(vw, 11, 0.0092, 13)}px ${MONO}`, letterSpacing: '0.22em', textTransform: 'uppercase',
      color: C.accent,
    },
  },
    h('span', { style: { width: 26, height: 1, background: GRAD, display: 'inline-block' } }),
    text,
  );
}
function H({ children, vw, max }) {
  return h('h2', {
    style: {
      margin: '12px 0 14px', font: `800 ${px(vw, 27, 0.045, max || 52)}px ${SANS}`,
      lineHeight: 1.12, letterSpacing: '-0.02em', color: C.text, textWrap: 'balance',
    },
  }, children);
}
function Lead({ children, vw }) {
  return h('p', {
    style: { margin: 0, color: C.muted, font: `400 ${px(vw, 15, 0.018, 19)}px ${SANS}`, lineHeight: 1.55, maxWidth: 620 },
  }, children);
}
function Cta({ vw, glow, label }) {
  return h('a', {
    href: DL,
    style: {
      display: 'inline-flex', alignItems: 'center', gap: 10, textDecoration: 'none',
      background: GRAD, color: '#fff', fontWeight: 700, font: `700 ${px(vw, 15, 0.013, 17)}px ${SANS}`,
      padding: '15px 28px', borderRadius: 999,
      boxShadow: `0 12px ${28 + glow * 22}px rgba(168,85,247,${0.34 + glow * 0.3})`,
    },
  }, label);
}
function Dot({ color, glow }) {
  return h('span', {
    style: { width: 8, height: 8, borderRadius: '50%', background: color, boxShadow: glow ? `0 0 10px ${color}` : 'none', display: 'inline-block', flex: 'none' },
  });
}
function Card({ children, style, lift }) {
  return h('div', {
    style: {
      background: 'linear-gradient(180deg, rgba(26,22,38,0.94), rgba(18,15,30,0.94))',
      border: `1px solid ${C.border}`, borderRadius: 18, position: 'relative',
      boxShadow: `0 ${18 + (lift || 0) * 20}px ${40 + (lift || 0) * 30}px -16px rgba(0,0,0,${0.5 + (lift || 0) * 0.15})`,
      ...style,
    },
  }, children);
}
const layer = (opacity, extra) => ({
  alignItems: 'center', justifyContent: 'center', opacity,
  paddingTop: 76, paddingBottom: 60,
  pointerEvents: opacity > 0.5 ? 'auto' : 'none', ...extra,
});
const wrap = (vw, maxw, style) => ({ width: '100%', maxWidth: Math.min(vw - (vw < 760 ? 40 : 48), maxw), ...style });

/* ---- evolving background (depth + continuity) ------------------------------ */
function Bg(f, vw, vh) {
  const drift = Math.sin(f / 90) * 30;
  const hue = interpolate(f, [0, DUR], [0, 26], cl);
  const a1 = `hsla(${276 + hue}, 70%, 56%, 0.20)`;
  const a2 = `hsla(${324 + hue}, 78%, 60%, 0.13)`;
  const y = interpolate(f, [0, DUR], [0, -8], cl);
  return AbsoluteFill({ style: { background: C.bg } },
    h('div', { style: { position: 'absolute', inset: 0, background: `radial-gradient(60% 50% at ${50 + drift / 40}% ${10 + y}%, ${a1}, transparent 70%)` } }),
    h('div', { style: { position: 'absolute', inset: 0, background: `radial-gradient(46% 40% at ${78 - drift / 30}% ${88}%, ${a2}, transparent 72%)` } }),
    AbsoluteFill({ style: { background: 'radial-gradient(120% 120% at 50% 50%, transparent 60%, rgba(0,0,0,0.45))' } }),
  );
}

/* ---- Scene 1 · Hero -------------------------------------------------------- */
function Hero(f, vw, vh, mob, T) {
  const o = fade(f, ...SC.hero);
  const exit = seen(f, SC.hero[2], SC.hero[3]);
  const iconS = interpolate(f, [0, 22], [0.62, 1], ease);
  const iconY = rise(f, 0, 22, 46) + Math.sin(f / 40) * 5;
  const iconBlur = interpolate(f, [0, 20], [12, 0], cl);
  const icon = px(vw, 76, 0.085, 112);
  return AbsoluteFill({ style: layer(o, { flexDirection: 'column', textAlign: 'center', transform: `translateY(${-exit * 60}px) scale(${1 - exit * 0.05})` }) },
    h('div', { style: wrap(vw, 760, { display: 'flex', flexDirection: 'column', alignItems: 'center' }) },
      h('img', {
        src: ASSET('assets/icon.png'), alt: '', width: icon, height: icon,
        style: {
          width: icon, height: icon, borderRadius: icon * 0.21, marginBottom: px(vw, 18, 0.02, 28),
          opacity: seen(f, 0, 16), transform: `translateY(${iconY}px) scale(${iconS})`, filter: `blur(${iconBlur}px)`,
          boxShadow: '0 24px 64px rgba(168,85,247,0.4)',
        },
      }),
      h('h1', { style: { margin: 0, font: `800 ${px(vw, 33, 0.056, 58)}px ${SANS}`, lineHeight: 1.1, letterSpacing: '-0.02em', color: C.text } },
        h('span', { style: { display: 'block', opacity: seen(f, 8, 28), transform: `translateY(${rise(f, 8, 30, 34)}px)` } }, T.hero.l1),
        h('span', { style: { display: 'block', opacity: seen(f, 18, 38), transform: `translateY(${rise(f, 18, 40, 34)}px)` } }, T.hero.l2),
      ),
      h('p', {
        style: {
          margin: `${px(vw, 16, 0.02, 22)}px auto 0`, maxWidth: 560, color: C.muted,
          font: `400 ${px(vw, 15.5, 0.017, 20)}px ${SANS}`, lineHeight: 1.6,
          opacity: seen(f, 38, 58), transform: `translateY(${rise(f, 38, 58, 22)}px)`,
        },
      }, T.hero.sub),
      h('div', { style: { marginTop: px(vw, 22, 0.025, 34), opacity: seen(f, 52, 72), transform: `translateY(${rise(f, 52, 72, 20)}px)` } },
        Cta({ vw, glow: 0.5 + Math.sin(f / 22) * 0.5, label: T.cta }),
      ),
      h('div', { style: { marginTop: 16, color: C.muted, font: `400 ${px(vw, 12.5, 0.011, 14)}px ${SANS}`, opacity: seen(f, 64, 84) } },
        T.hero.req,
      ),
    ),
  );
}

/* ---- Scene 2 · The product window ----------------------------------------- */
function Window(f, vw, vh, mob, T) {
  const o = fade(f, ...SC.window);
  const lf = f - SC.window[0];
  const inP = seen(lf, 0, 40);
  const rotX = interpolate(lf, [0, 40], [10, 0], ease);
  const y = rise(lf, 0, 40, 70) + Math.sin(f / 46) * 6;
  const scanX = interpolate(lf, [42, 96], [-30, 130], cl);
  const scanO = fade(lf, 42, 56, 84, 100);
  const w = Math.min(vw - (mob ? 32 : 80), 960);
  return AbsoluteFill({ style: layer(o, { flexDirection: 'column' }) },
    h('div', { style: { width: w, perspective: 1600, opacity: inP } },
      h('div', { style: { textAlign: 'center', marginBottom: px(vw, 14, 0.016, 20), opacity: seen(lf, 6, 26), transform: `translateY(${rise(lf, 6, 26, 16)}px)` } },
        Eyebrow({ text: T.window.eyebrow, vw, center: true }),
      ),
      h('div', {
        style: {
          position: 'relative', borderRadius: 16, overflow: 'hidden', border: `1px solid ${C.border}`,
          transform: `translateY(${y}px) rotateX(${rotX}deg)`, transformStyle: 'preserve-3d',
          boxShadow: '0 44px 110px -20px rgba(0,0,0,0.72), 0 22px 60px -34px rgba(168,85,247,0.55)',
          background: '#141121',
        },
      },
        h('img', { src: ASSET('assets/screenshot.webp'), alt: '', style: { display: 'block', width: '100%', height: 'auto' } }),
        h('div', { style: { position: 'absolute', inset: 0, pointerEvents: 'none', background: `linear-gradient(105deg, transparent ${scanX - 18}%, rgba(255,255,255,0.16) ${scanX}%, transparent ${scanX + 18}%)`, opacity: scanO } }),
        h('div', { style: { position: 'absolute', inset: 0, pointerEvents: 'none', borderRadius: 16, boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.06)' } }),
      ),
    ),
  );
}

/* ---- Scene 3 · Problem → Solution (state change) --------------------------- */
function Problem(f, vw, vh, mob, T) {
  const o = fade(f, ...SC.problem);
  const lf = f - SC.problem[0];
  const fs = px(vw, 14.5, 0.014, 17);
  return AbsoluteFill({ style: layer(o, { flexDirection: 'column' }) },
    h('div', { style: wrap(vw, 760) },
      h('div', { style: { opacity: seen(lf, 4, 22), transform: `translateY(${rise(lf, 4, 24, 22)}px)` } },
        Eyebrow({ text: T.problem.eyebrow, vw }),
        H({ children: T.problem.h, vw }),
      ),
      h('div', { style: { display: 'flex', flexDirection: 'column', gap: px(vw, 12, 0.012, 16), marginTop: 10 } },
        T.problem.pains.map((p, i) => {
          const t0 = 26 + i * 16;
          const flip = seen(lf, t0, t0 + 14);
          const appearO = seen(lf, t0 - 12, t0 - 2);
          return Card({
            lift: flip * 0.6,
            style: { padding: `${px(vw, 16, 0.018, 22)}px ${px(vw, 16, 0.018, 22)}px`, opacity: appearO, transform: `translateY(${rise(lf, t0 - 12, t0, 18)}px)`, overflow: 'hidden' },
            children: h('div', { style: { position: 'relative' } },
              h('div', { style: { display: 'flex', gap: 12, alignItems: 'center', opacity: 1 - flip, transform: `translateY(${-flip * 8}px)` } },
                h('span', { style: { width: 22, height: 22, borderRadius: '50%', flex: 'none', display: 'grid', placeItems: 'center', background: 'rgba(244,63,94,0.16)', color: '#fb7185', font: `700 12px ${MONO}` } }, '×'),
                h('span', { style: { color: C.muted, font: `400 ${fs}px ${SANS}`, lineHeight: 1.5 } }, p[0]),
              ),
              h('div', { style: { position: 'absolute', inset: 0, display: 'flex', gap: 12, alignItems: 'center', opacity: flip, transform: `translateY(${(1 - flip) * 8}px)` } },
                h('span', { style: { width: 22, height: 22, borderRadius: '50%', flex: 'none', display: 'grid', placeItems: 'center', background: 'rgba(52,211,153,0.18)', color: C.run, font: `700 12px ${MONO}` } }, '✓'),
                h('span', { style: { color: C.text, font: `500 ${fs}px ${SANS}`, lineHeight: 1.5 } }, p[1]),
              ),
            ),
          });
        }),
      ),
    ),
  );
}

/* ---- Scene 4 · Agents that manage agents (signature) ----------------------- */
function AgentNode({ name, role, color, state, glowOn, vw, w }) {
  return Card({
    lift: state === 'run' ? 0.8 : 0.2,
    style: {
      width: w, padding: `${px(vw, 12, 0.012, 15)}px ${px(vw, 13, 0.013, 17)}px`,
      borderColor: state === 'run' ? 'rgba(168,85,247,0.55)' : C.border,
    },
    children: h('div', null,
      h('div', { style: { display: 'flex', alignItems: 'center', gap: 8 } },
        Dot({ color, glow: glowOn }),
        h('span', { style: { color: C.text, font: `600 ${px(vw, 12.5, 0.012, 15)}px ${MONO}` } }, name),
      ),
      h('div', { style: { color: C.muted, font: `400 ${px(vw, 11, 0.0098, 12.5)}px ${SANS}`, marginTop: 5 } }, role),
    ),
  });
}
function Agents(f, vw, vh, mob, T) {
  const o = fade(f, ...SC.agents);
  const lf = f - SC.agents[0];
  const A = T.agents;
  const [claudeState, claudeGlow] = (() => { if (lf < 18) return ['idle', false]; if (lf < 70) return ['run', true]; return ['done', false]; })();
  const [codexState, codexGlow] = (() => { if (lf < 30) return ['idle', false]; if (lf < 44) return ['wait', true]; if (lf < 76) return ['run', true]; return ['done', false]; })();
  const [cursorState, cursorGlow] = (() => { if (lf < 36) return ['idle', false]; if (lf < 50) return ['wait', true]; if (lf < 80) return ['run', true]; return ['done', false]; })();
  const stColor = (s) => s === 'run' ? C.run : s === 'wait' ? C.wait : s === 'done' ? C.run : C.idle;
  const roleOf = (n, s) => s === 'wait' ? (n.wait || '') : s === 'done' ? n.done : (s === 'run' ? n.run : '');
  const childW = mob ? Math.min(vw - 60, 300) : 220;
  const flowPulse = (lf % 30) / 30;
  return AbsoluteFill({ style: layer(o, { flexDirection: 'column' }) },
    h('div', { style: wrap(vw, 720, { display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }) },
      h('div', { style: { opacity: seen(lf, 2, 20), transform: `translateY(${rise(lf, 2, 22, 20)}px)` } },
        Eyebrow({ text: A.eyebrow, vw, center: true }),
        H({ children: A.h, vw, max: 46 }),
        Lead({ children: A.lead, vw }),
      ),
      h('div', {
        style: {
          marginTop: px(vw, 22, 0.022, 30), opacity: seen(lf, 8, 22), transform: `translateY(${rise(lf, 8, 22, 16)}px)`,
          background: 'rgba(255,255,255,0.05)', border: `1px solid ${C.border}`, borderRadius: 999,
          padding: `9px ${px(vw, 14, 0.014, 18)}px`, color: C.text, font: `500 ${px(vw, 12.5, 0.012, 15)}px ${SANS}`,
        },
      }, A.chip),
      Connector(seen(lf, 18, 30), flowPulse, px(vw, 18, 0.02, 30)),
      h('div', { style: { opacity: seen(lf, 16, 30) } },
        AgentNode({ name: A.claude.name, role: claudeState === 'done' ? A.claude.done : A.claude.run, color: stColor(claudeState), state: claudeState, glowOn: claudeGlow, vw, w: mob ? Math.min(vw - 48, 320) : 260 }),
      ),
      Connector(seen(lf, 28, 40), flowPulse, px(vw, 16, 0.018, 26)),
      h('div', { style: { display: 'flex', flexDirection: mob ? 'column' : 'row', gap: px(vw, 12, 0.014, 18), alignItems: 'center', justifyContent: 'center', opacity: seen(lf, 30, 44) } },
        AgentNode({ name: A.codex.name, role: roleOf(A.codex, codexState), color: stColor(codexState), state: codexState, glowOn: codexGlow, vw, w: childW }),
        AgentNode({ name: A.cursor.name, role: roleOf(A.cursor, cursorState), color: stColor(cursorState), state: cursorState, glowOn: cursorGlow, vw, w: childW }),
      ),
      h('div', { style: { marginTop: px(vw, 16, 0.018, 22), color: C.run, font: `600 ${px(vw, 12, 0.011, 14)}px ${MONO}`, letterSpacing: '.06em', opacity: seen(lf, 78, 90) * (0.6 + 0.4 * Math.sin(lf / 8)) } },
        A.done,
      ),
    ),
  );
}
function Connector(op, pulse, ht) {
  return h('div', { style: { width: 2, height: ht, position: 'relative', background: 'linear-gradient(180deg, rgba(168,85,247,0.7), rgba(168,85,247,0.15))', opacity: op, margin: '8px 0' } },
    h('span', { style: { position: 'absolute', left: -2, top: `${pulse * 100}%`, width: 6, height: 6, borderRadius: '50%', background: C.a2, boxShadow: `0 0 8px ${C.a2}`, transform: 'translateY(-50%)' } }),
  );
}

/* ---- Scene 5 · Capabilities ------------------------------------------------ */
function Features(f, vw, vh, mob, T) {
  const o = fade(f, ...SC.features);
  const lf = f - SC.features[0];
  const F = T.features;
  const usageFill = seen(lf, 44, 82);
  const head = h('div', { style: { textAlign: 'center', opacity: seen(lf, 2, 20), transform: `translateY(${rise(lf, 2, 22, 20)}px)` } },
    Eyebrow({ text: F.eyebrow, vw, center: true }),
    H({ children: F.h, vw, max: 44 }),
  );

  if (mob) {
    return AbsoluteFill({ style: layer(o, { flexDirection: 'column' }) },
      h('div', { style: wrap(vw, 460, { display: 'flex', flexDirection: 'column' }) },
        head,
        h('div', { style: { display: 'flex', flexDirection: 'column', gap: 9, marginTop: 18 } },
          F.items.map((ft, i) => {
            const t0 = 16 + i * 8;
            return Card({
              lift: 0.2,
              style: { padding: '13px 15px', opacity: seen(lf, t0, t0 + 12), transform: `translateY(${rise(lf, t0, t0 + 12, 20)}px)` },
              children: h('div', { style: { display: 'flex', gap: 13, alignItems: 'flex-start' } },
                h('span', { style: { flex: 'none', width: 30, height: 30, borderRadius: 9, display: 'grid', placeItems: 'center', background: 'rgba(168,85,247,0.14)', border: `1px solid ${C.border}`, font: `800 13px ${MONO}`, ...GRAD_TEXT } }, ft[0]),
                h('div', null,
                  h('div', { style: { color: C.text, font: `700 15px ${SANS}`, letterSpacing: '-0.01em' } }, ft[1]),
                  h('div', { style: { color: C.muted, font: `400 13px ${SANS}`, lineHeight: 1.45, marginTop: 3 } }, ft[2]),
                ),
              ),
            });
          }),
        ),
      ),
    );
  }

  const cols = vw < 1040 ? 2 : 3;
  return AbsoluteFill({ style: layer(o, { flexDirection: 'column' }) },
    h('div', { style: wrap(vw, 1000) },
      head,
      h('div', { style: { display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: px(vw, 10, 0.012, 16), marginTop: px(vw, 18, 0.02, 28) } },
        F.items.map((ft, i) => {
          const t0 = 18 + i * 9;
          const op = seen(lf, t0, t0 + 14);
          const isUsage = ft[0] === '04';
          return Card({
            lift: 0.3,
            style: { padding: `${px(vw, 16, 0.016, 22)}px ${px(vw, 16, 0.016, 22)}px`, opacity: op, transform: `translateY(${rise(lf, t0, t0 + 14, 26)}px)` },
            children: h('div', null,
              h('div', { style: { font: `600 ${px(vw, 10.5, 0.0092, 12)}px ${MONO}`, letterSpacing: '.18em', color: C.accent } }, ft[0]),
              h('div', { style: { margin: '10px 0 7px', color: C.text, font: `700 ${px(vw, 16, 0.016, 20)}px ${SANS}`, letterSpacing: '-0.01em' } }, ft[1]),
              h('div', { style: { color: C.muted, font: `400 ${px(vw, 13, 0.0125, 14.5)}px ${SANS}`, lineHeight: 1.55 } }, ft[2]),
              isUsage ? h('div', { style: { marginTop: 14, display: 'flex', flexDirection: 'column', gap: 9 } },
                F.usage.map((u) => h('div', null,
                  h('div', { style: { display: 'flex', justifyContent: 'space-between', font: `600 ${px(vw, 10, 0.0088, 11.5)}px ${MONO}`, color: C.muted, marginBottom: 5 } },
                    h('span', null, u[0]),
                    h('b', { style: { color: C.text } }, `${u[1]}%`),
                  ),
                  h('div', { style: { height: 6, borderRadius: 999, background: 'rgba(255,255,255,0.07)', overflow: 'hidden' } },
                    h('div', { style: { height: '100%', width: `${u[1] * usageFill}%`, background: GRAD, borderRadius: 999 } }),
                  ),
                )),
              ) : null,
            ),
          });
        }),
      ),
    ),
  );
}

/* ---- Scene 6 · Get started + final CTA ------------------------------------- */
function Start(f, vw, vh, mob, T) {
  const o = seen(f, SC.start[0], SC.start[1]);
  const lf = f - SC.start[0];
  const S = T.start;
  const cols = vw < 760 ? 1 : 3;
  return AbsoluteFill({ style: layer(o, { flexDirection: 'column' }) },
    h('div', { style: wrap(vw, 940, { textAlign: 'center' }) },
      h('div', { style: { opacity: seen(lf, 2, 20), transform: `translateY(${rise(lf, 2, 22, 20)}px)` } },
        Eyebrow({ text: S.eyebrow, vw, center: true }),
        H({ children: S.h, vw, max: 46 }),
      ),
      h('div', { style: { display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: px(vw, 10, 0.012, 16), margin: `${px(vw, 18, 0.02, 28)}px 0`, textAlign: 'left' } },
        S.steps.map((s, i) => {
          const t0 = 16 + i * 12;
          return Card({
            style: { padding: `${px(vw, 18, 0.018, 26)}px ${px(vw, 18, 0.018, 24)}px`, opacity: seen(lf, t0, t0 + 14), transform: `translateY(${rise(lf, t0, t0 + 14, 24)}px)` },
            children: h('div', null,
              h('div', { style: { font: `800 ${px(vw, 20, 0.02, 24)}px ${MONO}`, ...GRAD_TEXT } }, s[0]),
              h('div', { style: { margin: '12px 0 7px', color: C.text, font: `700 ${px(vw, 16, 0.016, 19)}px ${SANS}` } }, s[1]),
              h('div', { style: { color: C.muted, font: `400 ${px(vw, 13, 0.0125, 14.5)}px ${SANS}`, lineHeight: 1.55 } }, s[2]),
            ),
          });
        }),
      ),
      h('div', { style: { opacity: seen(lf, 50, 66), transform: `scale(${interpolate(lf, [50, 70], [0.94, 1], ease)})` } },
        Cta({ vw, glow: 0.6 + Math.sin(lf / 18) * 0.4, label: T.cta }),
      ),
      h('div', { style: { marginTop: 26, color: C.muted, font: `400 12px ${SANS}`, opacity: seen(lf, 60, 74) } },
        S.copyright,
        h('a', { href: S.privacyHref, style: { color: C.muted } }, S.privacy),
      ),
    ),
  );
}

/* ---- composition root ------------------------------------------------------ */
export function Root(frame, vw, vh, props = {}) {
  const mob = vw < 760;
  const T = COPY[(props && props.lang) || 'en'] || COPY.en;
  return h('div', { style: { position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', background: C.bg, overflow: 'hidden' } },
    Bg(frame, vw, vh),
    Hero(frame, vw, vh, mob, T),
    Window(frame, vw, vh, mob, T),
    Problem(frame, vw, vh, mob, T),
    Agents(frame, vw, vh, mob, T),
    Features(frame, vw, vh, mob, T),
    Start(frame, vw, vh, mob, T),
  );
}
