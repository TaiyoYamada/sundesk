// 見出しに h-0, h-1, … の id を振り、目次を env.headings に集める。
// 日本語の見出しでも衝突しないよう、文字列からではなく出現順で id を決める。

import type { Env, MarkdownIt, StateCore, Token } from "markdown-it";

export interface Heading {
  level: number;
  text: string;
  id: string;
}

export interface HeadingEnv extends Env {
  headings?: Heading[];
}

export function headingIds(md: MarkdownIt): void {
  md.core.ruler.push("heading_ids", (state: StateCore) => {
    const env = state.env as HeadingEnv;
    const headings: Heading[] = [];
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (token?.type !== "heading_open") continue;
      const inline = tokens[i + 1];
      const id = `h-${headings.length}`;
      token.attrSet("id", id);
      headings.push({
        level: Number(token.tag.slice(1)),
        text: plainText(inline?.children ?? []),
        id,
      });
    }
    env.headings = headings;
  });
}

function plainText(children: readonly Token[]): string {
  return children
    .map((child) => (child.type === "text" || child.type === "code_inline" ? child.content : ""))
    .join("")
    .trim();
}
