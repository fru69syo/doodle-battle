import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

/**
 * Machine-readable error codes returned in `HttpsError.details.code`.
 * The app maps these to kid-friendly messages. Keep in sync with docs/BACKEND.md.
 */
export const ErrorCode = {
  UNAUTHENTICATED: "UNAUTHENTICATED",
  CONSENT_REQUIRED: "CONSENT_REQUIRED",
  INVALID_ARGUMENT: "INVALID_ARGUMENT",
  IMAGE_INVALID: "IMAGE_INVALID",
  IMAGE_TOO_LARGE: "IMAGE_TOO_LARGE",
  RATE_LIMITED: "RATE_LIMITED",
  AI_UNAVAILABLE: "AI_UNAVAILABLE",
  NOT_FOUND: "NOT_FOUND",
  NOT_OWNER: "NOT_OWNER",
  SNAPSHOT_NOT_ACTIVE: "SNAPSHOT_NOT_ACTIVE",
  NO_OPPONENT: "NO_OPPONENT",
  NOT_IN_MATCH: "NOT_IN_MATCH",
  MATCH_NOT_ACTIVE: "MATCH_NOT_ACTIVE",
  WRONG_TURN: "WRONG_TURN",
  ILLEGAL_ACTION: "ILLEGAL_ACTION",
  CANNOT_REPORT_SELF: "CANNOT_REPORT_SELF",
  NOT_SEEN_IN_MATCH: "NOT_SEEN_IN_MATCH",
  CONFIRMATION_REQUIRED: "CONFIRMATION_REQUIRED",
  INTERNAL: "INTERNAL",
} as const;
export type ErrorCode = (typeof ErrorCode)[keyof typeof ErrorCode];

const HTTPS_CODE: Record<ErrorCode, FunctionsErrorCode> = {
  UNAUTHENTICATED: "unauthenticated",
  CONSENT_REQUIRED: "permission-denied",
  INVALID_ARGUMENT: "invalid-argument",
  IMAGE_INVALID: "invalid-argument",
  IMAGE_TOO_LARGE: "invalid-argument",
  RATE_LIMITED: "resource-exhausted",
  AI_UNAVAILABLE: "unavailable",
  NOT_FOUND: "not-found",
  NOT_OWNER: "permission-denied",
  SNAPSHOT_NOT_ACTIVE: "failed-precondition",
  NO_OPPONENT: "unavailable",
  NOT_IN_MATCH: "permission-denied",
  MATCH_NOT_ACTIVE: "failed-precondition",
  WRONG_TURN: "failed-precondition",
  ILLEGAL_ACTION: "invalid-argument",
  CANNOT_REPORT_SELF: "invalid-argument",
  NOT_SEEN_IN_MATCH: "permission-denied",
  CONFIRMATION_REQUIRED: "invalid-argument",
  INTERNAL: "internal",
};

export function fail(code: ErrorCode, message: string = code): never {
  throw new HttpsError(HTTPS_CODE[code], message, { code });
}

export function codeOf(err: unknown): string | undefined {
  if (err instanceof HttpsError) {
    const d: unknown = err.details;
    if (d && typeof d === "object" && "code" in d && typeof d.code === "string") return d.code;
  }
  return undefined;
}
