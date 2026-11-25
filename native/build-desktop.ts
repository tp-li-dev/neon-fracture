// Builds single-file desktop executables.
//   bun native/build-desktop.ts          current platform
//   bun native/build-desktop.ts --all    Windows / macOS (x64+arm64) / Linux
import { mkdirSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const out = join(root, "build");
mkdirSync(out, { recursive: true });

const all = [
  { target: "bun-linux-x64", name: "neon-fracture-linux-x64" },
  { target: "bun-linux-arm64", name: "neon-fracture-linux-arm64" },
  { target: "bun-darwin-x64", name: "neon-fracture-macos-x64" },
  { target: "bun-darwin-arm64", name: "neon-fracture-macos-arm64" },
  { target: "bun-windows-x64", name: "neon-fracture-windows-x64.exe" },
];
const here = `bun-${process.platform === "win32" ? "windows" : process.platform}-${process.arch}`;
const targets = process.argv.includes("--all") ? all : all.filter((t) => t.target === here);
if (!targets.length) throw new Error(`unsupported host ${here}; use --all`);

for (const t of targets) {
  const res = await Bun.build({
    entrypoints: [join(root, "native/desktop.ts")],
    compile: {
      target: t.target as any,
      outfile: join(out, t.name),
      ...(t.target.includes("windows") ? { windows: { hideConsole: true, title: "NEON FRACTURE" } } : {}),
    } as any,
    minify: true,
  });
  if (!res.success) {
    console.error(res.logs.join("\n"));
    process.exit(1);
  }
  console.log("built", t.name);
}
