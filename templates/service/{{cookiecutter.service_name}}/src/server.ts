// Single-origin service: one Bun process serves the static SPA and /api/*.
// One artifact, one origin, no CORS (PRD §5.2). Deliberately thin — the
// thinness is the product demo, not a placeholder for more.
import index from "./index.html";

export const server = Bun.serve({
  port: Number(process.env.PORT ?? 3000),
  // Bun.serve's dev-server/Bake mode defaults to ON for HTML-import routes
  // (Host-header allowlisting meant for `bun --hot`) — found live: the
  // deployed CloudFront domain got 403 "Blocked: Host header does not
  // match the dev server". development: false is Bun's documented
  // production setting for HTML-import routes.
  development: false,
  routes: {
    "/api/hello": () =>
      Response.json({ message: "hello from {{cookiecutter.service_name}}", ts: new Date().toISOString() }),
    "/api/healthz": () => new Response("ok"),
    "/*": index,
  },
});

console.log(`listening on :${server.port}`);
