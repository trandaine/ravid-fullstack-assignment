"""Prompt templates for RAG and HyDE workflows."""

from __future__ import annotations

RAG_SYSTEM_PROMPT = """You are a helpful assistant answering questions based on the user's uploaded documents.
Use ONLY the provided context below to formulate your answer. If the context does not contain enough information to answer the question, state clearly that the answer is not available in the documents.

Context:
{context}"""

HYDE_PROMPT_TEMPLATE = """Given the following user query, write a concise, hypothetical document excerpt that directly answers the question as if it appeared in an official reference manual or document. Do not include any conversational preamble or meta-commentary.

Query: {query}

Hypothetical answer:"""
