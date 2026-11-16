// Canvas and frame callbacks shared by compiled programs on the single-window host.
class NativeAbortSignal {
  constructor() {
    this.aborted = false;
    this.reason = undefined;
    this.listeners = new Set();
  }
  addEventListener(type, cb) {
    if (type === "abort") this.listeners.add(cb);
  }
  removeEventListener(type, cb) {
    if (type === "abort") this.listeners.delete(cb);
  }
  throwIfAborted() {
    if (this.aborted) throw this.reason;
  }
}
globalThis.AbortSignal = NativeAbortSignal;
globalThis.AbortController = class {
  constructor() {
    this.signal = new NativeAbortSignal();
  }
  abort(reason = Error("Operation aborted")) {
    const signal = this.signal;
    if (signal.aborted) return;
    signal.aborted = true;
    signal.reason = reason;
    const event = { type: "abort", target: signal };
    if (signal.onabort) signal.onabort(event);
    for (const cb of signal.listeners) cb.call(signal, event);
  }
};
globalThis.self = globalThis.window = globalThis;
globalThis.performance = { now: __nativeNow };
globalThis.console = Object.fromEntries(
  ["log", "info", "warn", "error", "debug"].map((level) => [
    level,
    (...args) => __nativeLog(level, args.map(String).join(" ")),
  ]),
);

const listeners = new Map();
globalThis.addEventListener = (type, cb) => {
  if (!listeners.has(type)) listeners.set(type, new Set());
  listeners.get(type).add(cb);
};
globalThis.removeEventListener = (type, cb) => listeners.get(type)?.delete(cb);
globalThis.__nativeKey = (type, code, key, repeat) => {
  for (const cb of listeners.get(type) || []) cb({ type, code, key, repeat });
};
globalThis.devicePixelRatio = 1;
const frames = new Map();
let nextFrame = 0;
let dirty = false;
globalThis.requestAnimationFrame = (cb) => (
  frames.set(++nextFrame, cb),
  nextFrame
);
globalThis.cancelAnimationFrame = (id) => frames.delete(id);
globalThis.__nativeFrame = (time) => {
  const pending = Array.from(frames.keys());
  for (const id of pending) {
    const cb = frames.get(id);
    if (cb) {
      frames.delete(id);
      cb(time);
    }
  }
  if (context) context.endFrameEXP();
  const present = dirty;
  dirty = false;
  return present;
};
let width = 300,
  height = 150,
  context;
function dimension(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0 || n > 16384)
    throw RangeError("Canvas dimensions must be integers from 1 to 16384");
  dirty = true;
  return n;
}
class NativeCanvas {
  constructor() {
    this.style = {};
  }
  get width() {
    return width;
  }
  get height() {
    return height;
  }
  get clientWidth() {
    return width;
  }
  get clientHeight() {
    return height;
  }
  set width(value) {
    width = __nativeResize(dimension(value), height)[0];
    if (context) context.drawingBufferWidth = width;
  }
  set height(value) {
    height = __nativeResize(width, dimension(value))[1];
    if (context) context.drawingBufferHeight = height;
  }
  getContext(type, options = {}) {
    if (type !== "webgl2") return null;
    if (context) return context;
    context = __nativeContext(options);
    context.canvas = this;
    // Only swap a window after drawing. A static scene must survive idle frames.
    for (const name of [
      "clear",
      "clearBufferfv",
      "clearBufferiv",
      "clearBufferuiv",
      "clearBufferfi",
      "drawArrays",
      "drawElements",
      "drawRangeElements",
      "drawArraysInstanced",
      "drawElementsInstanced",
      "blitFramebuffer",
    ]) {
      const draw = context[name];
      if (draw)
        context[name] = function (...args) {
          dirty = true;
          return draw.apply(context, args);
        };
    }
    const pixelStore = context.pixelStorei.bind(context);
    const parameter = context.getParameter.bind(context);
    let conversion = context.BROWSER_DEFAULT_WEBGL;
    context.pixelStorei = (pname, value) => {
      if (pname === context.UNPACK_PREMULTIPLY_ALPHA_WEBGL) {
        if (value)
          throw Error(
            "Premultiplying image uploads is unsupported on this host",
          );
        return;
      }
      if (pname === context.UNPACK_COLORSPACE_CONVERSION_WEBGL) {
        if (value !== context.NONE && value !== context.BROWSER_DEFAULT_WEBGL)
          throw Error("Invalid color space conversion");
        conversion = value;
        return; // The host accepts raw pixel buffers, which have no browser color profile.
      }
      return pixelStore(pname, value);
    };
    context.getParameter = (pname) =>
      pname === context.UNPACK_COLORSPACE_CONVERSION_WEBGL
        ? conversion
        : parameter(pname);
    return context;
  }
  setAttribute(name, value) {
    this[name] = String(value);
  }
  addEventListener(...args) {
    addEventListener(...args);
  }
  removeEventListener(...args) {
    removeEventListener(...args);
  }
}
globalThis.HTMLCanvasElement = NativeCanvas;
const canvas = new NativeCanvas();
function createElement(tag) {
  if (tag === "canvas") return canvas;
  throw Error("Unsupported native DOM element <" + tag + ">");
}
globalThis.document = {
  createElement,
  createElementNS: (_, tag) => createElement(tag),
  querySelector: (selector) =>
    selector === "canvas" || (canvas.id && selector === "#" + canvas.id)
      ? canvas
      : null,
  getElementById: (id) => (id === canvas.id ? canvas : null),
  body: {
    appendChild(element) {
      if (element !== canvas)
        throw Error("Only the application canvas can be attached");
      return element;
    },
  },
};
globalThis.__nativeCanvas = canvas;
