"""LLM client factory supporting OpenRouter via LangChain ChatOpenAI and StubLLM."""

from __future__ import annotations

import logging
from django.conf import settings
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage

logger = logging.getLogger(__name__)


class LLMServiceError(Exception):
    """Raised when the upstream LLM service fails or times out."""


class StubChatModel(BaseChatModel):
    """Offline stub LLM for deterministic testing without external API calls."""

    default_response: str = "This is a stub LLM response based on retrieved context."

    @property
    def _llm_type(self) -> str:
        return "stub-chat-model"

    def _generate(
        self,
        messages: list[BaseMessage],
        stop: list[str] | None = None,
        run_manager: object | None = None,
        **kwargs: object,
    ) -> object:
        from langchain_core.outputs import ChatGeneration, ChatResult

        last_msg = messages[-1].content if messages else ""
        # If HyDE prompt, produce a hypothetical answer snippet
        if "Hypothetical answer:" in str(last_msg) or "hypothetical" in str(last_msg).lower():
            text = f"Hypothetical document excerpt addressing: {last_msg}"
        else:
            text = self.default_response
        return ChatResult(generations=[ChatGeneration(message=AIMessage(content=text))])


def get_llm() -> BaseChatModel:
    """Return configured ChatOpenAI instance pointed at OpenRouter or StubChatModel."""
    if getattr(settings, "RAVID_LLM_STUB", False):
        return StubChatModel()

    from langchain_openai import ChatOpenAI

    api_key = getattr(settings, "OPENROUTER_API_KEY", "") or "sk-dummy"
    base_url = getattr(settings, "OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
    model_name = getattr(settings, "OPENROUTER_MODEL", "google/gemma-2-9b-it:free")
    timeout = getattr(settings, "OPENROUTER_TIMEOUT", 30)

    return ChatOpenAI(
        model=model_name,
        openai_api_key=api_key,
        openai_api_base=base_url,
        temperature=0.3,
        max_tokens=1024,
        timeout=timeout,
    )
