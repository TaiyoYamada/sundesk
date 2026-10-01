"""チャット（NDJSON）。出典の番号づけとプロンプトの組み立ては、アプリが行う。"""

from typing import Literal

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from sundesk_engine.engine import EngineDep
from sundesk_engine.lab.generation import stream_chat
from sundesk_engine.lab.tokens import chat_prompt
from sundesk_engine.runtime.manager import check_adapter
from sundesk_engine.streaming import Emit, ndjson_response

router = APIRouter()


class Message(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    model: str
    messages: list[Message] = Field(min_length=1)
    max_tokens: int = Field(default=1024, ge=1, le=32768)
    temperature: float = Field(default=0.7, ge=0.0, le=5.0)
    top_p: float = Field(default=0.95, gt=0.0, le=1.0)
    adapter: str | None = None
    thinking: bool = True
    """偽なら、考える過程（Qwen3 の `<think>`）を飛ばして、すぐ答えさせる"""


@router.post("/chat")
async def post_chat(request: ChatRequest, engine: EngineDep) -> StreamingResponse:
    # 見つからないものは、流し始める前に 404 にする
    engine.hub.resolve(request.model)
    if request.adapter:
        check_adapter(request.adapter)

    def work(emit: Emit) -> None:
        llm = engine.models.llm(
            request.model,
            request.adapter,
            on_loading=lambda: emit({"type": "loading", "model": request.model}),
        )
        messages = [message.model_dump() for message in request.messages]
        prompt = chat_prompt(llm.tokenizer, messages, thinking=request.thinking)
        ids = [int(token) for token in llm.tokenizer.encode(prompt, add_special_tokens=False)]
        stats = stream_chat(
            llm.model,
            llm.tokenizer,
            ids,
            max_tokens=request.max_tokens,
            temperature=request.temperature,
            top_p=request.top_p,
            on_text=lambda text: emit({"type": "token", "text": text}),
        )
        if stats.tail:
            emit({"type": "token", "text": stats.tail})
        emit(
            {
                "type": "done",
                "prompt_tokens": len(ids),
                "generated_tokens": stats.generated_tokens,
                "tokens_per_second": round(stats.tokens_per_second, 2),
            }
        )

    return ndjson_response(work, engine.mlx_executor)
