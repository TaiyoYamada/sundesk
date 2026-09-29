import { beforeAll, describe, expect, it } from "vitest";

import { type Highlighter, createHighlighter } from "../src/highlight.js";
import { resolveVaultPath } from "../src/links.js";
import { createMarkdown, renderMarkdown, stripFrontmatter } from "../src/markdown.js";
import { parseWikilink } from "../src/plugins/wikilink.js";

const md = createMarkdown();
const render = (source: string, notePath = "量子計算/量子ビット.md") => renderMarkdown(md, source, notePath);

describe("ノート間リンク", () => {
  it("[[リンク先]] をノートを開くリンクにする", () => {
    const { html } = render("[[量子ゲート]]");
    expect(html).toContain('href="sundesk-open://note?target=%E9%87%8F%E5%AD%90%E3%82%B2%E3%83%BC%E3%83%88"');
    expect(html).toContain('class="wikilink"');
    expect(html).toContain(">量子ゲート</a>");
  });

  it("[[リンク先|表示名]] は表示名を出す", () => {
    const { html } = render("[[数学/線形代数/ベクトル|ベクトル]]");
    expect(html).toContain('data-target="数学/線形代数/ベクトル"');
    expect(html).toContain(">ベクトル</a>");
  });

  it("表の中の [[リンク先|表示名]] も壊れない（\\| でも | でもよい）", () => {
    const { html } = render("| 分野 | 入口 |\n|---|---|\n| 線形代数 | [[数学/ベクトル|ベクトル]] |\n| 量子 | [[量子ビット\\|量子]] |");
    expect(html).toContain('data-target="数学/ベクトル"');
    expect(html).toContain(">ベクトル</a>");
    expect(html).toContain('data-target="量子ビット"');
    expect(html.match(/<td>/g)?.length).toBe(4);
  });

  it("コードと数式の中はリンクにしない", () => {
    const { html } = render("`[[コード]]` と $[[n,k,d]]$\n\n```\n[[図]]\n```");
    expect(html).not.toContain("wikilink");
  });

  it.each([
    ["量子ゲート", { target: "量子ゲート", label: "量子ゲート" }],
    ["a|b", { target: "a", label: "b" }],
    ["a\\|b", { target: "a", label: "b" }],
    [" a ", { target: "a", label: "a" }],
    ["|b", null],
  ])("parseWikilink(%j)", (inner, expected) => {
    expect(parseWikilink(inner)).toEqual(expected);
  });
});

describe("注記", () => {
  it("[!note] 見出し を注記の枠にする", () => {
    const { html } = render("> [!note] 対角化との関係\n> 本文");
    expect(html).toContain('class="callout callout-note"');
    expect(html).toContain('<div class="callout-title">対角化との関係</div>');
    expect(html).toContain("<p>本文</p>");
    expect(html).not.toContain("[!note]");
  });

  it("見出しがなければ種類の名前を出す", () => {
    const { html } = render("> [!warning]\n> 気をつける");
    expect(html).toContain('<div class="callout-title">注意</div>');
  });

  it("普通の引用はそのまま", () => {
    const { html } = render("> ただの引用");
    expect(html).not.toContain("callout");
  });
});

describe("数式", () => {
  it("インラインとディスプレイの数式を KaTeX で描く", () => {
    const { html } = render("$E = mc^2$\n\n$$\n\\hat{A}|a\\rangle = a|a\\rangle\n$$");
    expect(html).toContain('class="katex"');
    expect(html).toContain("katex-display");
  });
});

describe("見出し", () => {
  it("出現順に id を振り、目次を返す", () => {
    const { html, headings } = render("# タイトル\n\n## 測定の理論 `A`\n\n### 小見出し");
    expect(headings).toEqual([
      { level: 1, text: "タイトル", id: "h-0" },
      { level: 2, text: "測定の理論 A", id: "h-1" },
      { level: 3, text: "小見出し", id: "h-2" },
    ]);
    expect(html).toContain('<h2 id="h-1">');
  });
});

describe("相対パス", () => {
  it("画像は Vault から読む", () => {
    const { html } = render("![Bloch 球](../資料/bloch-sphere.png)");
    expect(html).toContain('src="sundesk-vault://vault/%E8%B3%87%E6%96%99/bloch-sphere.png"');
  });

  it("ファイルへのリンクはアプリで開く", () => {
    const { html } = render("[レポート](実験レポート_VQE.html)");
    expect(html).toContain("sundesk-open://note?target=");
    expect(html).toContain("exact=1");
  });

  it("http のリンクは書き換えない", () => {
    const { html } = render("[Apple](https://www.apple.com)");
    expect(html).toContain('href="https://www.apple.com"');
  });

  it.each([
    ["量子計算/量子ビット.md", "../資料/図.png", "資料/図.png"],
    ["量子計算/量子ビット.md", "./量子ゲート.md", "量子計算/量子ゲート.md"],
    ["ホーム.md", "数学/線形代数/ベクトル.md", "数学/線形代数/ベクトル.md"],
    ["ホーム.md", "../外.md", null],
    ["a/b.md", "c%20d.md#見出し", "a/c d.md"],
  ])("resolveVaultPath(%j, %j)", (note, relative, expected) => {
    expect(resolveVaultPath(note, relative)).toBe(expected);
  });
});

describe("フロントマター", () => {
  it("先頭の --- ブロックを取り除く", () => {
    expect(stripFrontmatter("---\ntitle: a\ntags: [x]\n---\n# 本文")).toBe("# 本文");
  });

  it("フロントマターがなければそのまま", () => {
    expect(stripFrontmatter("# 本文\n---\n")).toBe("# 本文\n---\n");
  });
});

describe("脚注とタスクリスト", () => {
  it("脚注を描く", () => {
    const { html } = render("本文[^1]\n\n[^1]: 注");
    expect(html).toContain("footnote");
  });

  it("チェックボックスを描く（押せない）", () => {
    const { html } = render("- [x] 済\n- [ ] 未");
    expect(html).toContain('type="checkbox"');
    expect(html).toContain("disabled");
  });
});

describe("コードの色づけ", () => {
  let highlighter: Highlighter;
  beforeAll(async () => {
    highlighter = await createHighlighter();
  });

  it("Swift に色を付ける（ライトとダークの両方の色を持つ）", () => {
    const html = highlighter.highlight("let x = 1", "swift");
    expect(html).toContain('class="shiki');
    expect(html).toContain("--shiki-dark");
  });

  it("別名でも言語を見つける", () => {
    expect(highlighter.languages.has("py")).toBe(true);
    expect(highlighter.languages.has("sh")).toBe(true);
  });

  it("知らない言語は色を付けずに返す", () => {
    expect(highlighter.highlight("<x>", "unknown-language")).toContain("&#x3C;x>");
  });

  it("Markdown のコードブロックにも色を付ける", () => {
    const html = renderMarkdown(createMarkdown(highlighter), "```swift\nlet x = 1\n```", "a.md").html;
    expect(html).toContain('class="shiki');
  });
});
