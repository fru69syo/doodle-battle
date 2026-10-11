/**
 * Who is connecting? The first WebSocket message carries a Firebase ID token (anonymous sign-in)
 * and an App Check token. Both are JWTs signed by Google; firebase-admin checks the signature
 * against Google's public keys, the audience (our project) and the expiry. No IAM role is needed.
 */
import type { App } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";

export type AuthFailure = "UNAUTHENTICATED" | "APP_CHECK_FAILED";

export class AuthError extends Error {
  constructor(
    readonly code: AuthFailure,
    message: string,
  ) {
    super(message);
    this.name = "AuthError";
  }
}

export interface Verifier {
  /** Returns the uid or throws AuthError. */
  verify(idToken: string, appCheckToken: string | undefined): Promise<{ uid: string }>;
}

export class FirebaseVerifier implements Verifier {
  constructor(
    private readonly app: App,
    private readonly requireAppCheck: boolean,
  ) {}

  async verify(idToken: string, appCheckToken: string | undefined): Promise<{ uid: string }> {
    if (this.requireAppCheck || appCheckToken !== undefined) {
      if (appCheckToken === undefined) throw new AuthError("APP_CHECK_FAILED", "missing app check token");
      try {
        await getAppCheck(this.app).verifyToken(appCheckToken);
      } catch {
        throw new AuthError("APP_CHECK_FAILED", "invalid app check token");
      }
    }
    try {
      // checkRevoked=false: revocation needs an extra Auth API call per connection; anonymous
      // accounts are deleted (deleteMyData), which also stops token refresh within an hour.
      const decoded = await getAuth(this.app).verifyIdToken(idToken, false);
      return { uid: decoded.uid };
    } catch {
      throw new AuthError("UNAUTHENTICATED", "invalid id token");
    }
  }
}

/**
 * LOCAL DEVELOPMENT ONLY: accepts `dev:<uid>` as the ID token. Refused when NODE_ENV=production
 * (see config.ts), so it can never be enabled on Cloud Run by accident.
 */
export class InsecureDevVerifier implements Verifier {
  verify(idToken: string): Promise<{ uid: string }> {
    const m = /^dev:([A-Za-z0-9_-]{1,64})$/.exec(idToken);
    if (!m?.[1]) return Promise.reject(new AuthError("UNAUTHENTICATED", "dev tokens look like dev:<uid>"));
    return Promise.resolve({ uid: m[1] });
  }
}
