import { inflateSync } from "node:zlib";

/** Decoded 8-bit RGBA pixels (row-major, 4 bytes per pixel). */
export interface RgbaImage {
  width: number;
  height: number;
  rgba: Uint8Array;
}

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
/** Channels per colour type we decode (8-bit, non-interlaced). */
const CHANNELS: Record<number, number> = { 0: 1, 2: 3, 4: 2, 6: 4 };

function paeth(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

/**
 * Minimal PNG pixel decoder for the server-side plausibility checks (docs/TRUST.md §8):
 * 8-bit greyscale / RGB / grey+alpha / RGBA, non-interlaced (what the app's cut-out encoder
 * writes). Returns null for anything else or for a malformed file: callers treat "cannot decode"
 * as "not plausible" (fail-safe), never as an error for the child. `maxPixels` bounds the work
 * (the callables already cap the PNG at 512×512).
 */
export function decodePngPixels(bytes: Buffer, maxPixels = 512 * 512): RgbaImage | null {
  try {
    if (bytes.length < 33 || !bytes.subarray(0, 8).equals(SIGNATURE)) return null;
    let off = 8;
    let width = 0;
    let height = 0;
    let channels = 0;
    const idat: Buffer[] = [];
    while (off + 8 <= bytes.length) {
      const len = bytes.readUInt32BE(off);
      const type = bytes.toString("ascii", off + 4, off + 8);
      const data = bytes.subarray(off + 8, off + 8 + len);
      if (data.length !== len) return null;
      if (type === "IHDR") {
        width = data.readUInt32BE(0);
        height = data.readUInt32BE(4);
        const depth = data[8];
        const colour = data[9] ?? -1;
        const interlace = data[12];
        if (depth !== 8 || interlace !== 0 || !(colour in CHANNELS)) return null;
        channels = CHANNELS[colour] ?? 0;
      } else if (type === "IDAT") {
        idat.push(data);
      } else if (type === "IEND") {
        break;
      }
      off += 12 + len;
    }
    if (width < 1 || height < 1 || width * height > maxPixels || channels === 0 || idat.length === 0) return null;
    const stride = width * channels;
    const raw = inflateSync(Buffer.concat(idat), { maxOutputLength: (stride + 1) * height });
    if (raw.length !== (stride + 1) * height) return null;
    const cur = new Uint8Array(stride);
    const prev = new Uint8Array(stride);
    const rgba = new Uint8Array(width * height * 4);
    for (let y = 0; y < height; y++) {
      const filter = raw[y * (stride + 1)];
      const row = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
      for (let i = 0; i < stride; i++) {
        const x = row[i] ?? 0;
        const a = i >= channels ? (cur[i - channels] ?? 0) : 0;
        const b = prev[i] ?? 0;
        const c = i >= channels ? (prev[i - channels] ?? 0) : 0;
        let v: number;
        switch (filter) {
          case 0: v = x; break;
          case 1: v = x + a; break;
          case 2: v = x + b; break;
          case 3: v = x + ((a + b) >> 1); break;
          case 4: v = x + paeth(a, b, c); break;
          default: return null;
        }
        cur[i] = v & 0xff;
      }
      for (let px = 0; px < width; px++) {
        const s = px * channels;
        const d = (y * width + px) * 4;
        if (channels <= 2) {
          const g = cur[s] ?? 0;
          rgba[d] = g;
          rgba[d + 1] = g;
          rgba[d + 2] = g;
          rgba[d + 3] = channels === 2 ? (cur[s + 1] ?? 0) : 255;
        } else {
          rgba[d] = cur[s] ?? 0;
          rgba[d + 1] = cur[s + 1] ?? 0;
          rgba[d + 2] = cur[s + 2] ?? 0;
          rgba[d + 3] = channels === 4 ? (cur[s + 3] ?? 0) : 255;
        }
      }
      prev.set(cur);
    }
    return { width, height, rgba };
  } catch {
    return null;
  }
}
