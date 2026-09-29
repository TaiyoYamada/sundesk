// アプリとの取り決め。ここで作る URL を、Swift 側のナビゲーションの判定と
// URL スキームのハンドラが受け取る。

/** ノートを開く。Swift はこの URL へのナビゲーションを取り消し、代わりにタブで開く。 */
export function openURL(target: string, options: { exact?: boolean } = {}): string {
  const query = new URLSearchParams({ target });
  if (options.exact) query.set("exact", "1");
  return `sundesk-open://note?${query.toString()}`;
}

/** Vault 内のファイル（画像など）を読み込む URL。 */
export function vaultURL(path: string): string {
  return `sundesk-vault://vault/${path.split("/").map(encodeURIComponent).join("/")}`;
}

/** URL スキームを持つか（http:、mailto: など）。 */
export function hasScheme(href: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(href);
}

/**
 * ノートのある場所を基準に、相対パスを Vault のルートからのパスに直す。
 * Vault の外を指す場合は null。
 */
export function resolveVaultPath(notePath: string, relative: string): string | null {
  const [pathPart = ""] = relative.split(/[?#]/, 1);
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathPart);
  } catch {
    decoded = pathPart;
  }

  const base = decoded.startsWith("/") ? [] : notePath.split("/").slice(0, -1);
  const segments = [...base];
  for (const segment of decoded.split("/")) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") {
      if (segments.length === 0) return null;
      segments.pop();
    } else {
      segments.push(segment);
    }
  }
  return segments.length > 0 ? segments.join("/") : null;
}
