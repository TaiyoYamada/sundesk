//
//  FileKind.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

/// Vault の中のファイルの種類。開き方（描画するか、ソースを見せるか）を決める。
public enum FileKind: Hashable, Sendable {
    case folder
    case markdown
    case html
    /// 色づけして見せるコード。`language` は言語名（コードの色づけに使う）。
    case code(language: String)
    /// 色づけしないテキスト。
    case text
    case image
    case pdf
    /// Jupyter のノートブック（`.ipynb`）。セルと出力を並べて見せる。
    case notebook
    /// それ以外。Quick Look でプレビューする。
    case other

    /// ファイル名から種類を決める。拡張子のないもの（Makefile など）は名前で見る。
    public init(fileName: String) {
        let lowercased = fileName.lowercased()
        if let special = Self.specialFileNames[lowercased] {
            self = special
            return
        }
        guard let dot = lowercased.lastIndex(of: "."), dot != lowercased.startIndex else {
            self = .other
            return
        }
        let fileExtension = String(lowercased[lowercased.index(after: dot)...])
        self = Self.byExtension[fileExtension] ?? .other
    }

    /// 生のソース（テキスト）として見られるか。
    public var hasSourceView: Bool {
        switch self {
        case .markdown, .html, .code, .text, .notebook: true
        case .folder, .image, .pdf, .other: false
        }
    }

    private static let specialFileNames: [String: FileKind] = [
        "makefile": .code(language: "makefile"),
        "dockerfile": .code(language: "dockerfile"),
        "license": .text,
        "readme": .text,
    ]

    private static let byExtension: [String: FileKind] = {
        var table: [String: FileKind] = [
            "md": .markdown, "markdown": .markdown,
            "html": .html, "htm": .html,
            "txt": .text, "log": .text, "csv": .text, "tsv": .text,
            "pdf": .pdf, "ipynb": .notebook,
        ]
        for fileExtension in ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg"] {
            table[fileExtension] = .image
        }
        let languages: [String: String] = [
            "swift": "swift", "py": "python", "js": "javascript", "mjs": "javascript", "cjs": "javascript",
            "ts": "typescript", "tsx": "tsx", "jsx": "tsx", "json": "json", "jsonc": "jsonc",
            "yaml": "yaml", "yml": "yaml", "toml": "toml", "xml": "xml", "plist": "xml",
            "sh": "shellscript", "bash": "shellscript", "zsh": "shellscript",
            "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp", "hpp": "cpp", "m": "c",
            "rs": "rust", "go": "go", "java": "java", "kt": "kotlin", "rb": "ruby",
            "sql": "sql", "css": "css", "tex": "latex", "diff": "diff", "patch": "diff",
        ]
        for (fileExtension, language) in languages {
            table[fileExtension] = .code(language: language)
        }
        return table
    }()
}
