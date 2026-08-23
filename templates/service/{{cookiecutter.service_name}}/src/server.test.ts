import { describe, expect, test } from "bun:test";

// PORT=0 → OS-assigned free port, so this doesn't collide with anything
// already listening on 3000 on the host running the test. Dynamic import so
// the env var is set before server.ts's top-level Bun.serve() call runs.
process.env.PORT = "0";
const { server } = await import("./server");

// ponytail: one smoke test per route, not a coverage target. Enough to fail
// CI if the server stops booting or a route breaks; add real cases when the
// service does something worth testing.
describe("server", () => {
  test("/api/hello returns json", async () => {
    const res = await fetch(`${server.url}api/hello`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.message).toContain("hello from");
  });

  test("/api/healthz returns ok", async () => {
    const res = await fetch(`${server.url}api/healthz`);
    expect(await res.text()).toBe("ok");
  });
});
