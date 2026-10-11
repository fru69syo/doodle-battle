import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import Ajv2020 from "ajv/dist/2020";

/** Validator for ServerMessage from protocol.schema.json (the contract the app codes against). */
export function serverMessageValidator(): (msg: unknown) => boolean {
  const schema = JSON.parse(readFileSync(resolve(process.cwd(), "protocol.schema.json"), "utf8")) as object;
  const ajv = new Ajv2020({ strict: false });
  ajv.addSchema(schema, "protocol");
  const validate = ajv.getSchema("protocol#/$defs/ServerMessage");
  if (!validate) throw new Error("ServerMessage schema missing");
  return (msg: unknown) => validate(msg) === true;
}
