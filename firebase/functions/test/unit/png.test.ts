import { describe, expect, it } from "vitest";
import { codeOf } from "../../src/lib/errors";
import { decodePng } from "../../src/lib/png";
import { makePng } from "../helpers/png";

function codeFor(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (e) {
    return codeOf(e);
  }
  return undefined;
}

describe("decodePng", () => {
  it("accepts a ≤512px PNG", () => {
    const d = decodePng(makePng(512, 300).toString("base64"));
    expect([d.width, d.height]).toEqual([512, 300]);
  });
  it("rejects larger dimensions", () => {
    expect(codeFor(() => decodePng(makePng(513, 10).toString("base64")))).toBe("IMAGE_TOO_LARGE");
  });
  it("rejects tiny images", () => {
    expect(codeFor(() => decodePng(makePng(8, 8).toString("base64")))).toBe("IMAGE_INVALID");
  });
  it("rejects oversized payloads before decoding", () => {
    expect(codeFor(() => decodePng(makePng(100, 100, 700 * 1024).toString("base64")))).toBe("IMAGE_TOO_LARGE");
  });
  it("rejects non-PNG and non-base64 data", () => {
    expect(codeFor(() => decodePng(Buffer.from("GIF89a-not-a-png-at-all-xxxxxxxxxxxxxxxx").toString("base64")))).toBe(
      "IMAGE_INVALID",
    );
    expect(codeFor(() => decodePng("data:image/png;base64,AAAA"))).toBe("IMAGE_INVALID");
    expect(codeFor(() => decodePng(""))).toBe("IMAGE_INVALID");
  });
});
