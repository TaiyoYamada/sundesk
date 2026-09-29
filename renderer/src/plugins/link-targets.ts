// 通常のリンクと画像の参照先を、アプリ内で開ける URL に書き換える。
//
// - 相対パスのリンク（`../数学/ベクトル.md`）: そのファイルをアプリのタブで開く
// - 相対パスの画像（`../資料/図.png`）: Vault から読み込む
// - http: などのリンク: そのまま（Swift 側で既定のブラウザに渡す）

import type { Env, MarkdownIt, RendererRule, Token } from "markdown-it";

import { hasScheme, openURL, resolveVaultPath, vaultURL } from "../links.js";

export interface LinkEnv extends Env {
  notePath?: string;
}

export function linkTargets(md: MarkdownIt): void {
  const fallback: RendererRule = (tokens, idx, options, _env, self) => self.renderToken(tokens, idx, options);

  const defaultLinkOpen = md.renderer.rules.link_open ?? fallback;
  md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const href = attribute(token, "href");
    if (token && href && attribute(token, "class") !== "wikilink" && !href.startsWith("#") && !hasScheme(href)) {
      const path = resolveVaultPath(notePath(env), href);
      if (path !== null) token.attrSet("href", openURL(path, { exact: true }));
    }
    return defaultLinkOpen(tokens, idx, options, env, self);
  };

  const defaultImage = md.renderer.rules.image ?? fallback;
  md.renderer.rules.image = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const src = attribute(token, "src");
    if (token && src && !hasScheme(src)) {
      const path = resolveVaultPath(notePath(env), src);
      if (path !== null) token.attrSet("src", vaultURL(path));
    }
    token?.attrSet("loading", "lazy");
    return defaultImage(tokens, idx, options, env, self);
  };
}

function attribute(token: Token | undefined, name: string): string | null {
  const value = token?.attrGet(name);
  return value === null || value === undefined ? null : String(value);
}

function notePath(env: Env | undefined): string {
  return (env as LinkEnv | undefined)?.notePath ?? "";
}
