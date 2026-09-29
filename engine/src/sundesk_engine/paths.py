"""アプリから渡されたパスを確かめる。

エンジンは 127.0.0.1 とトークンで守っているが、書き出し先や読み込むフォルダは念のため、
利用者のホームと一時フォルダ（とモデルの置き場）の中だけに限る。
"""

import os
import tempfile

from sundesk_engine.errors import BadRequestError

MODELS_DIR_ENV = "SUNDESK_MODELS_DIR"


def _allowed_roots() -> list[str]:
    candidates = [os.path.expanduser("~"), tempfile.gettempdir()]
    if models := os.environ.get(MODELS_DIR_ENV):
        candidates.append(models)
    roots: list[str] = []
    for candidate in candidates:
        # macOS の /var と /private/var のように、シンボリックリンクの両方の書き方を許す
        for form in (os.path.normpath(candidate), os.path.realpath(candidate)):
            if form not in roots:
                roots.append(form)
    return roots


def confined_path(value: str, what: str) -> str:
    """絶対パスに直し、許した場所の中にあるときだけ返す。そうでなければ 400 にする。"""
    normalized = os.path.normpath(os.path.expanduser(value))
    if not os.path.isabs(normalized):
        raise BadRequestError(f"{what}は絶対パスで指定してください: {value}")
    for root in _allowed_roots():
        # 置き場そのものではなく、その中だけを許す（CodeQL が確かめ方として認める startswith の形にする）
        if normalized.startswith(root.rstrip(os.sep) + os.sep):
            return normalized
    raise BadRequestError(f"{what}は、ホームか一時フォルダの中にしてください: {value}")
