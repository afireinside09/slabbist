import { describe, it, expect, vi } from "vitest";
import { createLogger } from "@/shared/logger.js";

describe("createLogger", () => {
  it("emits structured JSON with level, msg, and fields", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger({ level: "info" });
    log.info("hello", { productId: 42 });
    expect(spy).toHaveBeenCalledOnce();
    const line = JSON.parse(spy.mock.calls[0]![0] as string);
    expect(line.level).toBe("info");
    expect(line.msg).toBe("hello");
    expect(line.productId).toBe(42);
    expect(typeof line.ts).toBe("string");
    spy.mockRestore();
  });

  it("suppresses debug when level is info", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger({ level: "info" });
    log.debug("skip");
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });
});
