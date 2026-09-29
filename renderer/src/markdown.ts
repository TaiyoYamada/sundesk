// markdown-it の組み立て。数式、脚注、タスクリスト、ノート間リンク、注記に対応する。

import { footnote } from "@mdit/plugin-footnote";
import { katex } from "@mdit/plugin-katex";
import { tasklist } from "@mdit/plugin-tasklist";
import MarkdownIt, { type MarkdownIt as MarkdownItInstance } from "markdown-it";

import type { Highlighter } from "./highlight.js";
import { callout } from "./plugins/callout.js";
import { type Heading, type HeadingEnv, headingIds } from "./plugins/heading-ids.js";
import { type LinkEnv, linkTargets } from "./plugins/link-targets.js";
import { wikilink } from "./plugins/wikilink.js";

export type { Heading };

export interface MarkdownResult {
  html: string;
  headings: Heading[];
}

export function createMarkdown(highlighter?: Highlighter): MarkdownItInstance {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    highlight: highlighter ? (code, language) => highlighter.highlight(code, language || "text") : null,
  });
  md.use(katex, {
    delimiters: "dollars",
    mathFence: true,
    throwOnError: false,
    // KaTeX の警告（日本語の文字が数式の中にある、など）で描画を止めない
    logger: () => "ignore" as const,
  });
  md.use(footnote);
  md.use(tasklist, { disabled: true });
  md.use(wikilink);
  md.use(callout);
  md.use(linkTargets);
  md.use(headingIds);
  return md;
}

/** `notePath` は Vault のルートからのパス。相対リンクと画像の解決に使う。 */
export function renderMarkdown(md: MarkdownItInstance, source: string, notePath: string): MarkdownResult {
  const env: HeadingEnv & LinkEnv = { notePath };
  const html = md.render(escapeWikilinkPipesInTables(stripFrontmatter(source)), env);
  return { html, headings: env.headings ?? [] };
}

/**
 * 表の行の中にある `[[リンク先|表示名]]` の `|` を `\|` にする。
 * そのままだと `|` が表の列の区切りとして読まれ、リンクが壊れる（Obsidian では `\|` と書く決まり）。
 */
export function escapeWikilinkPipesInTables(source: string): string {
  return source
    .split("\n")
    .map((line) => (/^\s*\|/.test(line) ? line.replace(/\[\[([^\]\n]*?)(?<!\\)\|([^\]\n]*?)\]\]/g, "[[$1\\|$2]]") : line))
    .join("\n");
}

/** 先頭の `---` で囲まれたフロントマターを取り除く（内容はインスペクタに出す）。 */
export function stripFrontmatter(source: string): string {
  const match = /^---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/.exec(source);
  return match ? source.slice(match[0].length) : source;
}
