// renderer を 1 つの JS と CSS にまとめ、Swift パッケージのリソースとして書き出す。
// KaTeX のフォントは CSS に埋め込む（アプリのリソースは平らに置かれるため）。

import { cp, mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const outdir = fileURLToPath(
  new URL("../Packages/SundeskKit/Sources/SundeskRenderer/Resources/Renderer/", import.meta.url),
);

await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });

await build({
  entryPoints: { renderer: "src/main.ts" },
  outdir,
  bundle: true,
  format: "iife",
  target: "safari18",
  minify: true,
  legalComments: "linked",
  loader: { ".woff2": "dataurl", ".woff": "empty", ".ttf": "empty" },
  logLevel: "info",
});

await cp("src/index.html", `${outdir}index.html`);
