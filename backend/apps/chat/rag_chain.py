"""RAG query execution pipeline supporting standard vector retrieval and HyDE."""

from __future__ import annotations

import logging
from typing import Any

from django.conf import settings
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage

from apps.chat.llm import LLMServiceError, get_llm
from apps.chat.prompts import HYDE_PROMPT_TEMPLATE, RAG_SYSTEM_PROMPT
from apps.rag.embeddings import get_embeddings
from apps.rag.vectorstore import get_collection

logger = logging.getLogger(__name__)


def retrieve_context_standard(user_id: int, query: str, k: int = 5) -> list[str]:
    """Retrieve top-k chunk texts from the user's Chroma collection using query text."""
    try:
        collection = get_collection(user_id)
        if collection.count() == 0:
            return []

        embeddings_service = get_embeddings()
        if hasattr(embeddings_service, "embed_query"):
            query_vector = embeddings_service.embed_query(query)
            results = collection.query(
                query_embeddings=[query_vector],
                n_results=min(k, collection.count()),
            )
        else:
            results = collection.query(
                query_texts=[query],
                n_results=min(k, collection.count()),
            )

        documents = results.get("documents", [[]])
        if documents and len(documents) > 0:
            return documents[0]
        return []
    except Exception as exc:
        logger.warning("Error retrieving vector context for user %s: %s", user_id, exc)
        return []


def retrieve_context_hyde(user_id: int, query: str, k: int = 5) -> list[str]:
    """Retrieve top-k chunk texts using Hypothetical Document Embeddings."""
    llm = get_llm()
    hyde_prompt = HYDE_PROMPT_TEMPLATE.format(query=query)

    try:
        hyde_response = llm.invoke([HumanMessage(content=hyde_prompt)])
        hypothetical_doc = hyde_response.content if hasattr(hyde_response, "content") else str(hyde_response)
    except Exception as exc:
        logger.warning(
            "HyDE hypothetical passage generation failed (%s). Falling back to standard retrieval.",
            exc,
        )
        return retrieve_context_standard(user_id, query, k=k)

    try:
        collection = get_collection(user_id)
        if collection.count() == 0:
            return []

        embeddings_service = get_embeddings()
        hypothetical_vector = embeddings_service.embed_query(hypothetical_doc)
        results = collection.query(
            query_embeddings=[hypothetical_vector],
            n_results=min(k, collection.count()),
        )
        documents = results.get("documents", [[]])
        if documents and len(documents) > 0:
            return documents[0]
        return []
    except Exception as exc:
        logger.warning(
            "HyDE vector retrieval failed (%s). Falling back to standard retrieval.",
            exc,
        )
        return retrieve_context_standard(user_id, query, k=k)


def format_context(chunks: list[str]) -> str:
    """Format list of chunk strings into a unified context block."""
    if not chunks:
        return "No relevant document context found."
    return "\n\n---\n\n".join(chunks)


def build_messages(
    context_str: str,
    query: str,
    message_histories: list[dict[str, Any]],
) -> list[BaseMessage]:
    """Construct message history and prompt structure for LLM invocation."""
    messages: list[BaseMessage] = [
        SystemMessage(content=RAG_SYSTEM_PROMPT.format(context=context_str))
    ]

    for item in message_histories:
        role = item.get("role")
        content = item.get("content", "")
        if role == "user":
            messages.append(HumanMessage(content=content))
        elif role == "assistant":
            messages.append(AIMessage(content=content))

    messages.append(HumanMessage(content=query))
    return messages


def run_query(
    user_id: int,
    query: str,
    message_histories: list[dict[str, Any]] | None = None,
    use_hyde: bool = False,
    k: int = 5,
) -> str:
    """Execute RAG query against user's vector store and generate answer via LLM."""
    if message_histories is None:
        message_histories = []

    # 1. Retrieve context
    if use_hyde:
        chunks = retrieve_context_hyde(user_id=user_id, query=query, k=k)
    else:
        chunks = retrieve_context_standard(user_id=user_id, query=query, k=k)

    context_str = format_context(chunks)

    # 2. Build prompt messages
    messages = build_messages(context_str, query, message_histories)

    # 3. Call LLM
    try:
        llm = get_llm()
        response = llm.invoke(messages)
        answer = response.content if hasattr(response, "content") else str(response)
        return str(answer).strip()
    except Exception as exc:
        logger.error("LLM invocation failed: %s", exc, exc_info=True)
        raise LLMServiceError("The AI service is temporarily unavailable. Please try again later.") from exc
