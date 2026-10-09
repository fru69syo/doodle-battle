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
