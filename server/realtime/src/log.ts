/**
 * Structured logging for Cloud Run.
 *
 * Cloud Run sends every stdout line to Cloud Logging. A line that is a JSON object becomes a
 * `jsonPayload`; the `severity` and `message` fields are understood by Cloud Logging. The
 * log-based metrics in infra/terraform/modules/monitoring/logs.tf filter on `event`.
 *
 * Never log tokens, drawings or names typed by children. uids are pseudonymous (anonymous auth).
 */
export type Severity = "DEBUG" | "INFO" | "WARNING" | "ERROR";

const ORDER: Record<Severity, number> = { DEBUG: 0, INFO: 1, WARNING: 2, ERROR: 3 };

export type LogFields = Record<string, unknown>;

export interface Logger {
  debug(message: string, fields?: LogFields): void;
  info(message: string, fields?: LogFields): void;
  warn(message: string, fields?: LogFields): void;
  error(message: string, fields?: LogFields): void;
}

export interface LoggerOptions {
  level?: Severity;
  /** Human-readable single lines for local development. */
  pretty?: boolean;
  /** Where lines go (tests capture them). Defaults to stdout. */
  sink?: (line: string) => void;
}

function errorFields(fields: LogFields | undefined): LogFields | undefined {
  if (!fields) return fields;
  const out: LogFields = {};
  for (const [k, v] of Object.entries(fields)) {
    out[k] = v instanceof Error ? { name: v.name, message: v.message, stack: v.stack } : v;
  }
  return out;
}

export function createLogger(opts: LoggerOptions = {}): Logger {
  const min = ORDER[opts.level ?? "INFO"];
  const sink = opts.sink ?? ((line: string) => process.stdout.write(line + "\n"));
  const emit = (severity: Severity, message: string, fields?: LogFields) => {
    if (ORDER[severity] < min) return;
    const f = errorFields(fields);
    if (opts.pretty) {
      sink(`${new Date().toISOString()} ${severity.padEnd(7)} ${message}${f ? " " + JSON.stringify(f) : ""}`);
      return;
    }
    sink(JSON.stringify({ severity, message, ...f, time: new Date().toISOString() }));
  };
  return {
    debug: (m, f) => { emit("DEBUG", m, f); },
    info: (m, f) => { emit("INFO", m, f); },
    warn: (m, f) => { emit("WARNING", m, f); },
    error: (m, f) => { emit("ERROR", m, f); },
  };
}

export function parseSeverity(v: string | undefined): Severity {
  switch ((v ?? "").toLowerCase()) {
    case "debug":
      return "DEBUG";
    case "warn":
    case "warning":
      return "WARNING";
    case "error":
      return "ERROR";
    default:
      return "INFO";
  }
}

/** A logger that drops everything (tests). */
export const silentLogger: Logger = { debug() {}, info() {}, warn() {}, error() {} };
