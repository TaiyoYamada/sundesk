"""`POST /graph/build` の要求と応答の形。"""

from typing import Literal

from pydantic import BaseModel, Field

type RelationKind = Literal[
    "cooccurrence", "hierarchy", "definition", "is_a", "link", "contains", "similar"
]


class ChunkIn(BaseModel):
    id: str
    heading_path: list[str] = Field(default_factory=list[str])
    text: str


class NoteIn(BaseModel):
    path: str
    title: str
    links: list[str] = Field(default_factory=list[str])
    chunks: list[ChunkIn] = Field(default_factory=list[ChunkIn])


class BuildOptions(BaseModel):
    max_concepts: int = Field(default=1500, ge=1, le=20000)
    min_frequency: int = Field(default=2, ge=1)
    similarity: bool = False
    min_cooccurrence: int = Field(default=2, ge=1)
    """共起の線を引くのに必要な、同じチャンクに出た回数"""
    similarity_threshold: float = Field(default=0.9, ge=-1.0, le=1.0)
    """`similar` の線を引く、コサイン類似度の下限（ruri-v3 で「トピック: 」を付けたときの目安）"""
    embedding_model: str | None = None
    """`similar` に使う埋め込みモデル（省略すると cl-nagoya/ruri-v3-130m）"""


class BuildRequest(BaseModel):
    notes: list[NoteIn]
    options: BuildOptions = Field(default_factory=BuildOptions)


class ConceptOut(BaseModel):
    id: int
    label: str
    normalized: str
    score: float
    frequency: int
    pagerank: float
    community: int


class MentionOut(BaseModel):
    concept: int
    chunk: str
    count: int


class RelationOut(BaseModel):
    source: int
    target: int
    kind: RelationKind
    weight: float
    evidence: str


class BuildResponse(BaseModel):
    concepts: list[ConceptOut]
    mentions: list[MentionOut]
    relations: list[RelationOut]
