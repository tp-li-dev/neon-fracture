// NEON FRACTURE desktop launcher (Bun).
//   bun native/desktop.ts            dev run
//   bun build --compile ...          single-file executable (see build-desktop.ts)
//
// Serves the embedded game on 127.0.0.1 and opens it in a chromeless
// "app mode" window using an installed Chrome / Edge / Chromium with a
// private profile. Falls back to the default browser if none is found.
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { assets } from "./assets";

const BASE_PORT = 47820; // fixed so localStorage (saves) keeps the same origin
const args = new Set(process.argv.slice(2));
const noWindow = args.has("--no-window");
const fullscreen = args.has("--fullscreen");

function dataDir(): string {
  const home = homedir();
  const dir =
    process.platform === "win32" ? join(process.env.APPDATA ?? join(home, "AppData", "Roaming"), "NeonFracture")
    : process.platform === "darwin" ? join(home, "Library", "Application Support", "NeonFracture")
    : join(process.env.XDG_DATA_HOME ?? join(home, ".local", "share"), "neon-fracture");
  mkdirSync(dir, { recursive: true });
  return dir;
}

function startServer() {
  const fetch = (req: Request) => {
    const path = new URL(req.url).pathname;
    const a = assets[path];
    if (!a) return new Response("Not found", { status: 404 });
    return new Response(Bun.file(a.file), {
      headers: { "content-type": a.type, "cache-control": "no-store" },
    });
  };
  const preferred = Number(process.env.NEON_PORT) || BASE_PORT;
  for (let port = preferred; port < preferred + 20; port++) {
    try {
      const server = Bun.serve({ hostname: "127.0.0.1", port, fetch });
      if (port !== preferred) console.warn(`[neon-fracture] port ${preferred} busy; using ${port} (saves are per-port)`);
      return server;
    } catch (e: any) {
      if (e?.code !== "EADDRINUSE") throw e;
    }
  }
  throw new Error("no free port");
}

function findBrowser(): string | null {
  const env = process.env.NEON_BROWSER;
  if (env) return env;
  const p = process.platform;
  const cands: string[] = [];
  if (p === "win32") {
    const roots = [process.env["PROGRAMFILES"], process.env["PROGRAMFILES(X86)"], process.env.LOCALAPPDATA].filter(Boolean) as string[];
    for (const r of roots) {
      cands.push(join(r, "Microsoft", "Edge", "Application", "msedge.exe"));
      cands.push(join(r, "Google", "Chrome", "Application", "chrome.exe"));
      cands.push(join(r, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"));
    }
  } else if (p === "darwin") {
    for (const n of ["Google Chrome", "Microsoft Edge", "Brave Browser", "Chromium"])
      cands.push(`/Applications/${n}.app/Contents/MacOS/${n}`);
  } else {
    for (const n of ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge", "brave-browser"]) {
      const w = Bun.which(n);
      if (w) cands.push(w);
    }
  }
  return cands.find((c) => existsSync(c)) ?? null;
}

function openDefaultBrowser(url: string) {
  const cmd = process.platform === "win32" ? ["cmd", "/c", "start", "", url]
    : process.platform === "darwin" ? ["open", url] : ["xdg-open", url];
  try { Bun.spawn(cmd, { stdio: ["ignore", "ignore", "ignore"] }); } catch {}
}

const server = startServer();
const url = `http://127.0.0.1:${server.port}/`;
console.log(`NEON FRACTURE running at ${url}`);

if (noWindow) {
  // server only (useful for tests / remote play)
} else {
  const browser = findBrowser();
  if (browser) {
    const proc = Bun.spawn([
      browser,
      `--app=${url}`,
      `--user-data-dir=${join(dataDir(), "profile")}`,
      "--no-first-run",
      "--no-default-browser-check",
      "--window-size=1280,720",
      "--autoplay-policy=no-user-gesture-required",
      ...(fullscreen ? ["--start-fullscreen"] : []),
      ...(process.env.NEON_BROWSER_ARGS?.split(" ").filter(Boolean) ?? []),
    ], { stdio: ["ignore", "ignore", "ignore"] });
    await proc.exited; // window closed -> quit
    server.stop(true);
    process.exit(0);
  } else {
    console.log("Chrome/Edge not found; opening default browser. Press Ctrl+C to quit.");
    openDefaultBrowser(url);
  }
}
