// アプリ（Swift）から呼ばれる窓口。WebKit の中で window.sundesk として公開する。

import "katex/dist/katex.min.css";
import "./style.css";

import { createHighlighter } from "./highlight.js";
import { type Heading, createMarkdown, renderMarkdown } from "./markdown.js";

export interface RenderResult {
  headings: Heading[];
}

export interface SundeskRenderer {
  renderMarkdown(source: string, notePath: string): Promise<RenderResult>;
  renderCode(source: string, language: string): Promise<RenderResult>;
  scrollToHeading(id: string): void;
}

declare global {
  interface Window {
    sundesk: SundeskRenderer;
  }
}

const highlighter = createHighlighter();
const markdown = highlighter.then((h) => createMarkdown(h));

function content(): HTMLElement {
  const element = document.getElementById("content");
  if (!element) throw new Error("#content がありません");
  return element;
}

window.sundesk = {
  async renderMarkdown(source, notePath) {
    const result = renderMarkdown(await markdown, source, notePath);
    const element = content();
    element.className = "markdown";
    element.innerHTML = result.html;
    window.scrollTo(0, 0);
    return { headings: result.headings };
  },

  async renderCode(source, language) {
    const element = content();
    element.className = "source";
    element.innerHTML = (await highlighter).highlight(source, language);
    window.scrollTo(0, 0);
    return { headings: [] };
  },

  scrollToHeading(id) {
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
  },
};

document.documentElement.dataset.ready = "true";
