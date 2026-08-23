// Single-origin service: one Bun process serves the static SPA and /api/*.
// One artifact, one origin, no CORS (PRD §5.2). Deliberately thin — the
// thinness is the product demo, not a placeholder for more.
import index from "./index.html";

export const server = Bun.serve({
  port: Number(process.env.PORT ?? 3000),
  routes: {
    "/api/hello": () =>
      Response.json({ message: "hello from {{cookiecutter.service_name}}", ts: new Date().toISOString() }),
    "/api/healthz": () => new Response("ok"),
    "/*": index,
  },
});

console.log(`listening on :${server.port}`);
