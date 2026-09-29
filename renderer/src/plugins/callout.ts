// Obsidian の注記（callout）: `> [!note] 見出し` で始まる引用を、色つきの枠にする。

import type { MarkdownIt, StateCore } from "markdown-it";

const LABELS: Record<string, string> = {
  note: "メモ",
  info: "情報",
  tip: "ヒント",
  important: "重要",
  warning: "注意",
  caution: "警告",
  danger: "危険",
  todo: "TODO",
  question: "疑問",
  example: "例",
  quote: "引用",
};

const MARKER = /^\[!([A-Za-z-]+)\][+-]?[ \t]*(.*)$/;

export function callout(md: MarkdownIt): void {
  md.core.ruler.after("inline", "callout", (state: StateCore) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length - 2; i++) {
      const open = tokens[i];
      const paragraph = tokens[i + 1];
      const inline = tokens[i + 2];
      if (open?.type !== "blockquote_open" || paragraph?.type !== "paragraph_open" || inline?.type !== "inline") {
        continue;
      }

      const firstLine = inline.content.split("\n", 1)[0] ?? "";
      const match = MARKER.exec(firstLine);
      if (match === null) continue;

      const kind = (match[1] ?? "note").toLowerCase();
      const title = (match[2] ?? "").trim() || LABELS[kind] || kind;
      open.attrJoin("class", `callout callout-${kind}`);
      open.attrSet("data-kind", kind);

      // 1 行目（[!kind] 見出し）を段落から取り除く
      const children = inline.children ?? [];
      const breakIndex = children.findIndex((child) => child.type === "softbreak" || child.type === "hardbreak");
      inline.children = breakIndex < 0 ? [] : children.slice(breakIndex + 1);
      inline.content = inline.content.split("\n").slice(1).join("\n");

      const titleToken = new state.Token("html_block", "", 0);
      titleToken.content = `<div class="callout-title">${md.utils.escapeHtml(title)}</div>\n`;
      tokens.splice(i + 1, 0, titleToken);

      // 見出しだけの注記なら、空になった段落を消す
      if (inline.children.length === 0) {
        tokens.splice(i + 2, 3);
      }
    }
  });
}
