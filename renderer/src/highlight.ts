// Shiki でコードに色を付ける。VS Code と同じ文法定義を使う。
//
// バンドルを小さく保つため、よく使う言語とテーマだけを読み込む。
// 正規表現エンジンは WebAssembly を使わない JavaScript 版にする。

import bash from "@shikijs/langs/shellscript";
import c from "@shikijs/langs/c";
import cpp from "@shikijs/langs/cpp";
import css from "@shikijs/langs/css";
import diff from "@shikijs/langs/diff";
import dockerfile from "@shikijs/langs/dockerfile";
import go from "@shikijs/langs/go";
import html from "@shikijs/langs/html";
import java from "@shikijs/langs/java";
import javascript from "@shikijs/langs/javascript";
import json from "@shikijs/langs/json";
import jsonc from "@shikijs/langs/jsonc";
import kotlin from "@shikijs/langs/kotlin";
import latex from "@shikijs/langs/latex";
import makefile from "@shikijs/langs/makefile";
import markdown from "@shikijs/langs/markdown";
import python from "@shikijs/langs/python";
import ruby from "@shikijs/langs/ruby";
import rust from "@shikijs/langs/rust";
import sql from "@shikijs/langs/sql";
import swift from "@shikijs/langs/swift";
import toml from "@shikijs/langs/toml";
import tsx from "@shikijs/langs/tsx";
import typescript from "@shikijs/langs/typescript";
import xml from "@shikijs/langs/xml";
import yaml from "@shikijs/langs/yaml";
import githubDark from "@shikijs/themes/github-dark";
import githubLight from "@shikijs/themes/github-light";
import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";

const LANGUAGES = [
  bash, c, cpp, css, diff, dockerfile, go, html, java, javascript, json, jsonc, kotlin, latex,
  makefile, markdown, python, ruby, rust, sql, swift, toml, tsx, typescript, xml, yaml,
];

export interface Highlighter {
  /** `<pre class="shiki">…</pre>` を返す。知らない言語は色を付けずに返す。 */
  highlight(code: string, language: string): string;
  /** 読み込んである言語（別名を含む）。 */
  readonly languages: ReadonlySet<string>;
}

export async function createHighlighter(): Promise<Highlighter> {
  const core = await createHighlighterCore({
    themes: [githubLight, githubDark],
    langs: LANGUAGES,
    engine: createJavaScriptRegexEngine(),
  });
  const languages = new Set(core.getLoadedLanguages());

  return {
    languages,
    highlight(code, language) {
      const lang = languages.has(language.toLowerCase()) ? language.toLowerCase() : "text";
      return core.codeToHtml(code, {
        lang,
        // ライトとダークの両方の色を CSS 変数で出し、どちらを使うかは CSS が決める
        themes: { light: "github-light", dark: "github-dark" },
        defaultColor: false,
      });
    },
  };
}
