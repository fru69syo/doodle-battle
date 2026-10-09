import type { z } from "zod";
import { ErrorCode, fail } from "./errors";

/** Parses callable input with zod; any mismatch is INVALID_ARGUMENT. */
export function parseInput<T extends z.ZodType>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data);
  if (!r.success) {
    const where = r.error.issues
      .slice(0, 3)
      .map((i) => i.path.join(".") || "(root)")
      .join(", ");
    fail(ErrorCode.INVALID_ARGUMENT, `invalid argument: ${where}`);
  }
  return r.data;
}
