import { describe, expect, it } from "vitest";
import { reportAiSuggestionHandler } from "../../src/callables/reportAiSuggestion";
import { deleteMyDataHandler } from "../../src/callables/deleteMyData";
import { COL, db } from "../../src/lib/firebase";
import { errorCode, req, seedUser, useEmulatorEnv } from "../helpers/emulator";

useEmulatorEnv();
const report = (uid: string | null, data: Record<string, unknown>) => reportAiSuggestionHandler(req(uid, data));

describe("reportAiSuggestion", () => {
  it("needs sign-in and the cloud-judge consent", async () => {
    const data = { kind: "name", text: "にゃんた", reasonCode: "mean" };
    expect(await errorCode(report(null, data))).toBe("UNAUTHENTICATED");
    await seedUser("kid", { cloudJudge: false, online: true });
    expect(await errorCode(report("kid", data))).toBe("CONSENT_REQUIRED");
  });

  it("stores preset-reason reports of AI suggestions for review", async () => {
    await seedUser("kid", { cloudJudge: true });
    expect(await report("kid", { kind: "name", text: "にゃんた", reasonCode: "mean" })).toEqual({ ok: true });
    expect(await report("kid", { kind: "special_move", text: "ねこびーむ", reasonCode: "scary" })).toEqual({ ok: true });
    const docs = (await db().collection(COL.aiSuggestionReports).get()).docs.map((d) => d.data());
    expect(docs).toHaveLength(2);
    expect(docs[0]).toMatchObject({ uid: "kid", state: "pending" });
  });

  it("accepts only kana suggestions and preset reasons (no free text)", async () => {
    await seedUser("kid", { cloudJudge: true });
    expect(await errorCode(report("kid", { kind: "name", text: "visit example.com", reasonCode: "mean" }))).toBe(
      "INVALID_ARGUMENT",
    );
    expect(await errorCode(report("kid", { kind: "name", text: "にゃんた", reasonCode: "because" }))).toBe(
      "INVALID_ARGUMENT",
    );
    expect(await errorCode(report("kid", { kind: "chat", text: "にゃんた", reasonCode: "mean" }))).toBe(
      "INVALID_ARGUMENT",
    );
  });

  it("is deleted with the account", async () => {
    await seedUser("kid", { cloudJudge: true });
    await report("kid", { kind: "name", text: "にゃんた", reasonCode: "strange" });
    await deleteMyDataHandler(req("kid", { confirm: "DELETE" }));
    expect((await db().collection(COL.aiSuggestionReports).get()).size).toBe(0);
  });
});
