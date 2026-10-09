/**
 * らくがきバトル Cloud Functions (v2, asia-northeast1).
 * See docs/BACKEND.md for contracts, data model and deployment.
 */
import "./config";

export { judgeDrawing } from "./callables/judgeDrawing";
export { registerCharacter } from "./callables/registerCharacter";
export { setDisplayName } from "./callables/setDisplayName";
export { joinQueue, leaveQueue } from "./callables/matchmaking";
export { submitAction, pollMatch } from "./callables/battle";
export { reportCharacter } from "./callables/reportCharacter";
export { deleteMyData } from "./callables/deleteMyData";
export { sweepMatches } from "./scheduled/sweep";
export { onUserConsentChanged } from "./triggers/consent";
