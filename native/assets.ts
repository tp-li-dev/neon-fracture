// Files embedded into the compiled desktop binary. index.html is the single
// source of truth shared with the browser/PWA build and is never modified.
import indexHtml from "../index.html" with { type: "file" };
import manifest from "../manifest.webmanifest" with { type: "file" };
import icon192 from "../icon-192.png" with { type: "file" };
import icon512 from "../icon-512.png" with { type: "file" };

export const assets: Record<string, { file: string; type: string }> = {
  "/": { file: indexHtml, type: "text/html; charset=utf-8" },
  "/index.html": { file: indexHtml, type: "text/html; charset=utf-8" },
  "/manifest.webmanifest": { file: manifest, type: "application/manifest+json" },
  "/icon-192.png": { file: icon192, type: "image/png" },
  "/icon-512.png": { file: icon512, type: "image/png" },
};
// Note: /sw.js is intentionally not served. The native app ships its own
// content, so the PWA service worker (and its stale-cache risk) is not needed.
