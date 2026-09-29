"""sundesk の AI エンジン。

Swift のアプリから別プロセスとして起動され、HTTP で計算を引き受ける。
状態は持たず、保存はすべてアプリ側（SwiftData）が行う（docs/adr/0003 を参照）。
"""

from importlib.metadata import version

__version__ = version("sundesk-engine")
