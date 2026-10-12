import { crc32, deflateSync } from "node:zlib";

/** Builds a minimal PNG-shaped buffer (signature + IHDR + IEND) of the given size. */
export function makePng(width: number, height: number, padTo = 0): Buffer {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(25);
  ihdr.writeUInt32BE(13, 0);
  ihdr.write("IHDR", 4, "ascii");
  ihdr.writeUInt32BE(width, 8);
  ihdr.writeUInt32BE(height, 12);
  ihdr.writeUInt8(8, 16); // bit depth
  ihdr.writeUInt8(6, 17); // RGBA
  const iend = Buffer.from([0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);
  const body = Buffer.concat([sig, ihdr, iend]);
  return padTo > body.length ? Buffer.concat([body, Buffer.alloc(padTo - body.length)]) : body;
}

export function pngBase64(width = 256, height = 256): string {
  return makePng(width, height).toString("base64");
}

/**
 * Encodes a real 8-bit RGBA PNG (non-interlaced). `filter` selects the PNG row filter
 * (0 none, 1 sub, 2 up, 3 average, 4 paeth) so the decoder's filters are all exercised.
 */
export function encodeRgbaPng(width: number, height: number, rgba: Uint8Array, filter: 0 | 1 | 2 | 3 | 4 = 0): Buffer {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  const paeth = (a: number, b: number, c: number) => {
    const p = a + b - c;
    const pa = Math.abs(p - a);
    const pb = Math.abs(p - b);
    const pc = Math.abs(p - c);
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
  };
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = filter;
    for (let i = 0; i < stride; i++) {
      const x = rgba[y * stride + i] ?? 0;
      const a = i >= 4 ? (rgba[y * stride + i - 4] ?? 0) : 0;
      const b = y > 0 ? (rgba[(y - 1) * stride + i] ?? 0) : 0;
      const c = y > 0 && i >= 4 ? (rgba[(y - 1) * stride + i - 4] ?? 0) : 0;
      const pred = filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? (a + b) >> 1 : paeth(a, b, c);
      raw[y * (stride + 1) + 1 + i] = (x - pred) & 0xff;
    }
  }
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** Deterministic PRNG for test pictures. */
function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Ink box [l, t, r, b] (canvas units) and the cut-out size it produces at scale 0.4 + 4 px margins. */
export const CANVAS_TEST_BOX: [number, number, number, number] = [200, 150, 800, 950];
export const CANVAS_TEST_SIZE = { width: 600 * 0.4 + 8, height: 800 * 0.4 + 8 };

/**
 * A cut-out like the in-app canvas produces: thick round strokes in palette colours, crayon
 * grain (specks mixed with paper) and anti-aliased edges, on a transparent background.
 */
export function canvasLikePng(colors: readonly number[], seed = 1): Buffer {
  const { width, height } = CANVAS_TEST_SIZE;
  const rgba = new Uint8Array(width * height * 4);
  const rnd = rng(seed);
  const put = (x: number, y: number, rgb: readonly number[], mix: number) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const i = (y * width + x) * 4;
    for (let c = 0; c < 3; c++) rgba[i + c] = Math.round((rgb[c] ?? 0) * mix + 255 * (1 - mix));
    rgba[i + 3] = 255;
  };
  const strokes = 14;
  for (let s = 0; s < strokes; s++) {
    const argb = colors[s % colors.length] ?? 0xff1f1a1a;
    const rgb = [(argb >>> 16) & 0xff, (argb >>> 8) & 0xff, argb & 0xff];
    const r = 3 + Math.floor(rnd() * 4);
    let x = 6 + rnd() * (width - 12);
    let y = 6 + rnd() * (height - 12);
    for (let p = 0; p < 40; p++) {
      x = Math.min(width - 6, Math.max(6, x + (rnd() - 0.5) * 10));
      y = Math.min(height - 6, Math.max(6, y + (rnd() - 0.5) * 10));
      for (let dy = -r - 1; dy <= r + 1; dy++) {
        for (let dx = -r - 1; dx <= r + 1; dx++) {
          const d = Math.hypot(dx, dy);
          if (d > r + 1) continue;
          const edge = d > r ? 0.5 : rnd() < 0.15 ? 0.45 : 1; // anti-aliasing / crayon grain
          put(Math.round(x + dx), Math.round(y + dy), rgb, edge);
        }
      }
    }
  }
  // The crop touches the ink on every side (like encodeCutout): mark the corners' margin rows.
  put(4, 4, [0x1f, 0x1a, 0x1a], 1);
  put(width - 5, height - 5, [0x1f, 0x1a, 0x1a], 1);
  return encodeRgbaPng(width, height, rgba);
}

/** A glossy "digital" picture of the same size: smooth gradients and shading, fully opaque. */
export function gradientPng(filter: 0 | 1 | 2 | 3 | 4 = 0): Buffer {
  const { width, height } = CANVAS_TEST_SIZE;
  const rgba = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const shade = 0.35 + 0.65 * (1 - Math.hypot(x - width / 3, y - height / 3) / Math.hypot(width, height));
      rgba[i] = Math.round((120 + (100 * x) / width) * shade);
      rgba[i + 1] = Math.round((60 + (150 * y) / height) * shade);
      rgba[i + 2] = Math.round((200 - (120 * x) / width) * shade);
      rgba[i + 3] = 255;
    }
  }
  return encodeRgbaPng(width, height, rgba, filter);
}
