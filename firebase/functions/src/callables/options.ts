import type { CallableOptions } from "firebase-functions/v2/https";
import { ANTHROPIC_API_KEY } from "../config";

/** Every callable requires a valid App Check token (Play Integrity). */
export const BASE_CALLABLE: CallableOptions = {
  enforceAppCheck: true,
  memory: "256MiB",
  timeoutSeconds: 30,
};

/** Callables that talk to Claude. */
export const AI_CALLABLE: CallableOptions = {
  ...BASE_CALLABLE,
  secrets: [ANTHROPIC_API_KEY],
  memory: "512MiB",
  timeoutSeconds: 60,
};
