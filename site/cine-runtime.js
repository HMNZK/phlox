// Self-hosted cinematic runtime — interpolate, easing, vnode DOM, patch renderer.

/* ---- interpolate + easing (Remotion-compatible subset) -------------------- */
function clampSegment(input, inputRange, outputRange, easing) {
  let t = (input - inputRange[0]) / (inputRange[1] - inputRange[0]);
  if (easing) t = easing(t);
  return outputRange[0] + t * (outputRange[1] - outputRange[0]);
}

export function interpolate(input, inputRange, outputRange, options = {}) {
  const left = options.extrapolateLeft || 'extend';
  const right = options.extrapolateRight || 'extend';
  const easing = options.easing;

  if (inputRange.length !== outputRange.length || inputRange.length < 2) {
    throw new Error('inputRange and outputRange must have the same length (>= 2)');
  }

  if (input <= inputRange[0]) {
    if (left === 'clamp') return outputRange[0];
    return clampSegment(input, [inputRange[0], inputRange[1]], [outputRange[0], outputRange[1]], easing);
  }
  if (input >= inputRange[inputRange.length - 1]) {
    const n = inputRange.length - 1;
    if (right === 'clamp') return outputRange[n];
    return clampSegment(input, [inputRange[n - 1], inputRange[n]], [outputRange[n - 1], outputRange[n]], easing);
  }

  for (let i = 0; i < inputRange.length - 1; i++) {
    if (input >= inputRange[i] && input <= inputRange[i + 1]) {
      return clampSegment(input, [inputRange[i], inputRange[i + 1]], [outputRange[i], outputRange[i + 1]], easing);
    }
  }
  return outputRange[outputRange.length - 1];
}

export const Easing = {
  cubic: (t) => t * t * t,
  out: (fn) => (t) => 1 - fn(1 - t),
};

/* ---- vnode + DOM ----------------------------------------------------------- */
function flattenChildren(children) {
  const out = [];
  for (const c of children) {
    if (c == null || c === false) continue;
    if (Array.isArray(c)) out.push(...flattenChildren(c));
    else out.push(c);
  }
  return out;
}

export function h(tag, props, ...children) {
  if (typeof tag === 'function') return tag(props, ...children);
  return { tag, props: props || {}, children: flattenChildren(children) };
}

const FILL_STYLE = {
  position: 'absolute',
  top: 0,
  left: 0,
  right: 0,
  bottom: 0,
  display: 'flex',
  flexDirection: 'column',
};

export function AbsoluteFill(props, ...children) {
  const p = props || {};
  return h('div', {
    ...p,
    style: { ...FILL_STYLE, ...(p.style || {}) },
  }, ...children);
}

function resolveTag(tag) {
  return typeof tag === 'string' ? tag.toLowerCase() : 'div';
}

// React CSSProperty.isUnitlessNumber と同等の集合
const UNITLESS_STYLE = new Set([
  'animationIterationCount', 'aspectRatio', 'borderImageOutset', 'borderImageSlice',
  'borderImageWidth', 'boxFlex', 'boxFlexGroup', 'boxOrdinalGroup', 'columnCount',
  'columns', 'flex', 'flexGrow', 'flexPositive', 'flexShrink', 'flexNegative',
  'flexOrder', 'gridArea', 'gridRow', 'gridRowEnd', 'gridRowSpan', 'gridRowStart',
  'gridColumn', 'gridColumnEnd', 'gridColumnSpan', 'gridColumnStart',
  'fontWeight', 'lineClamp', 'lineHeight', 'opacity', 'order', 'orphans', 'tabSize',
  'widows', 'zIndex', 'zoom', 'fillOpacity', 'floodOpacity', 'stopOpacity',
  'strokeDasharray', 'strokeDashoffset', 'strokeMiterlimit', 'strokeOpacity', 'strokeWidth',
]);

function styleCSSValue(key, value) {
  if (typeof value === 'number' && Number.isFinite(value) && !UNITLESS_STYLE.has(key)) {
    return `${value}px`;
  }
  return value;
}

function setStyleProp(el, key, value) {
  if (value == null) {
    el.style.removeProperty(key.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`));
  } else {
    el.style[key] = styleCSSValue(key, value);
  }
}

function applyProp(el, key, val) {
  if (key === 'style' && val && typeof val === 'object') {
    for (const [k, v] of Object.entries(val)) setStyleProp(el, k, v);
    return;
  }
  if (key === 'className') {
    el.className = val;
    return;
  }
  if (key.startsWith('on') && typeof val === 'function') {
    const ev = key.slice(2).toLowerCase();
    el[`__${ev}`] = val;
    el.addEventListener(ev, val);
    return;
  }
  if (val == null) el.removeAttribute(key);
  else el.setAttribute(key, val);
}

function updateProps(el, oldProps, newProps) {
  const o = oldProps || {};
  const n = newProps || {};
  const keys = new Set([...Object.keys(o), ...Object.keys(n)]);
  for (const key of keys) {
    if (key === 'style') {
      const prev = o.style || {};
      const next = n.style || {};
      const sk = new Set([...Object.keys(prev), ...Object.keys(next)]);
      for (const k of sk) setStyleProp(el, k, next[k]);
    } else if (key.startsWith('on') && o[key] !== n[key]) {
      const ev = key.slice(2).toLowerCase();
      const prev = el[`__${ev}`];
      if (prev) el.removeEventListener(ev, prev);
      applyProp(el, key, n[key]);
    } else if (o[key] !== n[key]) {
      applyProp(el, key, n[key]);
    }
  }
}

function createElement(vnode) {
  if (typeof vnode === 'string' || typeof vnode === 'number') {
    return document.createTextNode(String(vnode));
  }
  if (!vnode || typeof vnode !== 'object') return document.createTextNode('');

  const tag = resolveTag(vnode.tag);
  const el = tag === 'img' ? document.createElement('img') : document.createElement(tag);
  for (const [key, val] of Object.entries(vnode.props || {})) applyProp(el, key, val);
  for (const child of vnode.children || []) {
    const node = createElement(child);
    if (node) el.appendChild(node);
  }
  return el;
}

function patch(oldVNode, newVNode, parent, el) {
  if (newVNode == null || newVNode === false) {
    if (el) el.remove();
    return null;
  }

  if (typeof newVNode === 'string' || typeof newVNode === 'number') {
    const text = String(newVNode);
    if (!el) {
      const node = document.createTextNode(text);
      parent.appendChild(node);
      return node;
    }
    if (el.nodeType === Node.TEXT_NODE) {
      if (el.textContent !== text) el.textContent = text;
      return el;
    }
    const node = document.createTextNode(text);
    el.replaceWith(node);
    return node;
  }

  if (!el || el.nodeType !== Node.ELEMENT_NODE) {
    const node = createElement(newVNode);
    if (el) el.replaceWith(node);
    else parent.appendChild(node);
    return node;
  }

  const want = resolveTag(newVNode.tag);
  if (el.tagName.toLowerCase() !== want) {
    const node = createElement(newVNode);
    el.replaceWith(node);
    return node;
  }

  updateProps(el, oldVNode?.props, newVNode.props);

  const oldKids = oldVNode?.children || [];
  const newKids = newVNode.children || [];

  while (el.childNodes.length > newKids.length) {
    el.lastChild?.remove();
  }

  for (let i = 0; i < newKids.length; i++) {
    patch(oldKids[i], newKids[i], el, el.childNodes[i] || null);
  }
  return el;
}

export function createRenderer(container) {
  let prevTree = null;
  return {
    render(tree) {
      if (!prevTree) {
        container.replaceChildren();
        patch(null, tree, container, null);
      } else {
        patch(prevTree, tree, container, container.firstChild);
      }
      prevTree = tree;
    },
    remount() {
      container.replaceChildren();
      prevTree = null;
    },
  };
}
