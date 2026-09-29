// [[リンク先]] と [[リンク先|表示名]] を、ノートを開くリンクに変える（Obsidian と同じ書き方）。
//
// コードや数式の中の [[...]] はリンクにしない。markdown-it はコードスパンと数式を
// それぞれの規則で先に取り込むので、この規則が見るのはそれ以外の場所だけになる。

import type { MarkdownIt, StateInline } from "markdown-it";

import { openURL } from "../links.js";

export function wikilink(md: MarkdownIt): void {
  md.inline.ruler.before("link", "wikilink", (state: StateInline, silent: boolean) => {
    const { src, pos } = state;
    if (src.charCodeAt(pos) !== 0x5b || src.charCodeAt(pos + 1) !== 0x5b) return false;

    const end = src.indexOf("]]", pos + 2);
    if (end < 0) return false;
    const inner = src.slice(pos + 2, end);
    if (inner.length === 0 || inner.includes("\n") || inner.includes("[")) return false;

    const parsed = parseWikilink(inner);
    if (parsed === null) return false;

    if (!silent) {
      const open = state.push("link_open", "a", 1);
      open.attrSet("href", openURL(parsed.target));
      open.attrSet("class", "wikilink");
      open.attrSet("data-target", parsed.target);
      const text = state.push("text", "", 0);
      text.content = parsed.label;
      state.push("link_close", "a", -1);
    }
    state.pos = end + 2;
    return true;
  });
}

export interface Wikilink {
  target: string;
  label: string;
}

/** `リンク先|表示名` を分ける。表の中で使う `\|` も区切りとして扱う。 */
export function parseWikilink(inner: string): Wikilink | null {
  const separator = inner.search(/\\?\|/);
  const rawTarget = separator < 0 ? inner : inner.slice(0, separator);
  const rawLabel = separator < 0 ? undefined : inner.slice(separator).replace(/^\\?\|/, "");

  const target = rawTarget.trim().replace(/\\+$/, "");
  if (target.length === 0) return null;
  const label = rawLabel?.trim() || target;
  return { target, label };
}
