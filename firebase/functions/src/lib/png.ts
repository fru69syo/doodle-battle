import { LIMITS } from "../config";
import { ErrorCode, fail } from "./errors";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

export interface DecodedPng {
  bytes: Buffer;
  width: number;
  height: number;
}

/**
 * Decodes and validates a base64 PNG: size cap, PNG signature, IHDR chunk and
 * dimensions. The bytes are only kept in memory by callers.
 */
export function decodePng(base64: string): DecodedPng {
  // Cheap pre-check before decoding: base64 is 4/3 of the binary size.
  if (base64.length > Math.ceil((LIMITS.maxPngBytes * 4) / 3) + 4) {
    fail(ErrorCode.IMAGE_TOO_LARGE, "image too large");
  }
  if (base64.length < 8 || base64.length % 4 !== 0 || !BASE64_RE.test(base64)) {
    fail(ErrorCode.IMAGE_INVALID, "image must be base64 PNG");
  }
  const bytes = Buffer.from(base64, "base64");
  if (bytes.length > LIMITS.maxPngBytes) fail(ErrorCode.IMAGE_TOO_LARGE, "image too large");
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    fail(ErrorCode.IMAGE_INVALID, "not a PNG");
  }
  if (bytes.toString("ascii", 12, 16) !== "IHDR") fail(ErrorCode.IMAGE_INVALID, "missing IHDR");
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  const max = LIMITS.maxPngSide;
  const min = LIMITS.minPngSide;
  if (width > max || height > max) fail(ErrorCode.IMAGE_TOO_LARGE, `image larger than ${max}px`);
  if (width < min || height < min) fail(ErrorCode.IMAGE_INVALID, "image too small");
  return { bytes, width, height };
}
