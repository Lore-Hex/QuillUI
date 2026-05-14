#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import sqlite3
import sys
from pathlib import Path


APPLE_REFERENCE_DATE = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
CONVERSATION_TABLE = "_quilldata_json_QuillEnchantedCore_QuillDataConversationRecord"
MESSAGE_TABLE = "_quilldata_json_QuillEnchantedCore_QuillDataMessageRecord"


def seconds_since_reference(value: dt.datetime) -> float:
    return (value - APPLE_REFERENCE_DATE).total_seconds()


def create_payload_table(connection: sqlite3.Connection, table: str) -> None:
    connection.execute(
        f"""
        CREATE TABLE IF NOT EXISTS "{table}" (
            id TEXT PRIMARY KEY ON CONFLICT REPLACE,
            payload BLOB NOT NULL
        )
        """
    )


def insert_payload(connection: sqlite3.Connection, table: str, record_id: str, payload: dict[str, object]) -> None:
    connection.execute(
        f'INSERT OR REPLACE INTO "{table}" (id, payload) VALUES (?, ?)',
        (record_id, json.dumps(payload, sort_keys=True).encode("utf-8")),
    )


def seed_database(home: Path) -> None:
    database_path = home / ".quillui" / "enchanted" / "enchanted-quilldata.sqlite"
    database_path.parent.mkdir(parents=True, exist_ok=True)

    base = dt.datetime(2026, 1, 12, 9, 0, tzinfo=dt.timezone.utc)
    conversations = [
        {
            "id": "daily-brief",
            "title": "Launch checklist",
            "messages": [
                ("system-1", "system", "You are chatting with a local Ollama model in Enchanted."),
                ("user-1", "user", "Turn my meeting notes into a short launch checklist."),
                (
                    "assistant-1",
                    "assistant",
                    "Confirm the owner, send the revised timeline, collect final screenshots, and ask design for approval before Friday.",
                ),
            ],
        },
        {
            "id": "local-models",
            "title": "Local model setup",
            "messages": [
                ("local-user-1", "user", "What should I check before switching models for a longer draft?"),
                (
                    "local-assistant-1",
                    "assistant",
                    "Keep the endpoint reachable, choose the model with the right context window, and run a short prompt before pasting the full draft.",
                ),
            ],
        },
        {
            "id": "attachments",
            "title": "Image attachment flow",
            "messages": [
                ("attachment-user-1", "user", "Can you help turn this screenshot into release-note copy?"),
                (
                    "attachment-assistant-1",
                    "assistant",
                    "Use a concise caption, mention what changed, and keep the note focused on the user-facing setup flow.",
                ),
            ],
        },
    ]

    with sqlite3.connect(database_path) as connection:
        create_payload_table(connection, CONVERSATION_TABLE)
        create_payload_table(connection, MESSAGE_TABLE)
        connection.execute(f'DELETE FROM "{CONVERSATION_TABLE}"')
        connection.execute(f'DELETE FROM "{MESSAGE_TABLE}"')

        for conversation_index, conversation in enumerate(conversations):
            conversation_time = base + dt.timedelta(minutes=conversation_index * 5)
            insert_payload(
                connection,
                CONVERSATION_TABLE,
                conversation["id"],
                {
                    "id": conversation["id"],
                    "title": conversation["title"],
                    "createdAt": seconds_since_reference(conversation_time),
                    "updatedAt": seconds_since_reference(conversation_time + dt.timedelta(minutes=4)),
                },
            )

            for message_index, (message_id, role, content) in enumerate(conversation["messages"]):
                message_time = conversation_time + dt.timedelta(minutes=message_index)
                insert_payload(
                    connection,
                    MESSAGE_TABLE,
                    message_id,
                    {
                        "id": message_id,
                        "conversationID": conversation["id"],
                        "role": role,
                        "content": content,
                        "createdAt": seconds_since_reference(message_time),
                    },
                )


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: seed-enchanted-reference-data.py HOME_DIR", file=sys.stderr)
        return 64

    seed_database(Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
