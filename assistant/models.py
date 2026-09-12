from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, Field


class Channel(StrEnum):
    slack = "slack"
    slack_informal = "slack_informal"
    talking_points = "talking_points"
    formal = "formal"
    ai_prompt = "ai_prompt"
    other = "other"


class PolishRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=20000)
    channel: Channel


class Correction(BaseModel):
    original: str
    corrected: str
    why: str


class VocabularyItem(BaseModel):
    term: str
    meaning: str
    example: str


class LearningSummary(BaseModel):
    corrections: list[Correction]
    grammar_insight: str
    vocabulary: list[VocabularyItem]


class PolishResponse(BaseModel):
    polished_text: str
    learning_summary: LearningSummary | None
    detected_language: str
    was_translated: bool
    model_used: str
