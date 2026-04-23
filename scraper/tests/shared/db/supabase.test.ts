// tests/shared/db/supabase.test.ts
import { describe, it, expect } from "vitest";
import { throwIfError } from "@/shared/db/supabase.js";
import type { PostgrestError } from "@supabase/supabase-js";

function fakeSuccess<T extends object>(data: T) {
  return { ...data, error: null } as typeof data & { error: null };
}

function fakeError(message: string) {
  const err = { message, details: "", hint: "", code: "PGRST000", name: "PostgrestError", toJSON() { return this; } } as PostgrestError;
  return { data: null, error: err };
}

describe("throwIfError", () => {
  it("passes through the result when error is null (success branch)", async () => {
    const result = await throwIfError(Promise.resolve(fakeSuccess({ data: [{ id: 1 }] })));
    expect(result.data).toEqual([{ id: 1 }]);
    expect(result.error).toBeNull();
  });

  it("passes through a non-Promise (direct value) result when error is null", async () => {
    // Simulates fake-supabase which returns synchronous-looking resolved objects
    const direct = fakeSuccess({ data: "ok" });
    const result = await throwIfError(direct);
    expect(result.data).toBe("ok");
  });

  it("throws with the error message when error is present (error branch)", async () => {
    await expect(
      throwIfError(Promise.resolve(fakeError("duplicate key value"))),
    ).rejects.toThrow("supabase: duplicate key value");
  });

  it("includes the full supabase error message in the thrown Error", async () => {
    await expect(
      throwIfError(Promise.resolve(fakeError("permission denied for table graded_cards"))),
    ).rejects.toThrow("permission denied for table graded_cards");
  });
});
