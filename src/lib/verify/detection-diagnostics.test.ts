
import { describe, expect, it } from "vitest";
import { safeDatabaseCode, safeDiagnosticErrorCode, safeDiagnosticErrorType, safeProviderRequestId } from "./detection-diagnostics";

describe("diagnostic allowlist normalization", () => {
  it.each(["sk-proj-synthetic", "Bearer synthetic", "private transcript phrase", "https://example.invalid/?token=x", "/private/file", "C:\\private\\file", "unknown_identifier", "a".repeat(129)])("drops unapproved content %s", (value) => {
    expect(safeDiagnosticErrorType(value)).toBeNull();
    expect(safeDiagnosticErrorCode(value)).toBeNull();
    expect(safeProviderRequestId(value)).toBeNull();
    expect(safeDatabaseCode(value)).toBeNull();
  });
  it("retains approved identifiers and normalizes non-SQLSTATE errors", () => {
    expect(safeDiagnosticErrorType("connection_error")).toBe("connection_error");
    expect(safeDiagnosticErrorCode("invalid_api_key")).toBe("invalid_api_key");
    expect(safeDatabaseCode("42501")).toBe("42501");
    expect(safeDatabaseCode("PGRST301")).toBeNull();
  });
});
