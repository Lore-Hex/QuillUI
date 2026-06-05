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
GENERATED_CONVERSATION_TABLE = "_quilldata_json_GeneratedSwiftUILinuxApp_ConversationSD"
GENERATED_MESSAGE_TABLE = "_quilldata_json_GeneratedSwiftUILinuxApp_MessageSD"
GENERATED_MODEL_TABLE = "_quilldata_json_GeneratedSwiftUILinuxApp_LanguageModelSD"


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


def generated_model_payload() -> dict[str, object]:
    return {
        "name": "llava:latest",
        "isAvailable": False,
        "imageSupport": True,
        "modelProvider": {"ollama": {}},
        "conversations": [],
    }


def generated_conversation_payload(
    conversation_id: str,
    name: str,
    created_at: dt.datetime,
    updated_at: dt.datetime,
) -> dict[str, object]:
    return {
        "id": conversation_id,
        "name": name,
        "createdAt": seconds_since_reference(created_at),
        "updatedAt": seconds_since_reference(updated_at),
        "model": generated_model_payload(),
        "messages": [],
    }


def generated_message_payload(
    message_id: str,
    role: str,
    content: str,
    created_at: dt.datetime,
    conversation_payload: dict[str, object],
) -> dict[str, object]:
    return {
        "id": message_id,
        "role": role,
        "content": content,
        "createdAt": seconds_since_reference(created_at),
        "done": role == "assistant",
        "error": False,
        "conversation": conversation_payload,
    }


def seed_database_file(database_path: Path) -> None:
    database_path.parent.mkdir(parents=True, exist_ok=True)

    base = dt.datetime(2026, 1, 12, 9, 0, tzinfo=dt.timezone.utc)
    conversations = [
        {
            "id": "11111111-1111-4111-8111-111111111111",
            "title": "Launch checklist",
            "messages": [
                ("21111111-1111-4111-8111-111111111111", "system", "You are chatting with a local Ollama model in Enchanted."),
                ("21111111-1111-4111-8111-111111111112", "user", "Turn my meeting notes into a short launch checklist."),
                (
                    "21111111-1111-4111-8111-111111111113",
                    "assistant",
                    "Confirm the owner, send the revised timeline, collect final screenshots, and ask design for approval before Friday.",
                ),
            ],
        },
        {
            "id": "11111111-1111-4111-8111-111111111112",
            "title": "Local model setup",
            "messages": [
                ("21111111-1111-4111-8111-111111111114", "user", "What should I check before switching models for a longer draft?"),
                (
                    "21111111-1111-4111-8111-111111111115",
                    "assistant",
                    "Keep the endpoint reachable, choose the model with the right context window, and run a short prompt before pasting the full draft.",
                ),
            ],
        },
        {
            "id": "11111111-1111-4111-8111-111111111113",
            "title": "Image attachment flow",
            "messages": [
                ("21111111-1111-4111-8111-111111111116", "user", "Can you help turn this screenshot into release-note copy?"),
                (
                    "21111111-1111-4111-8111-111111111117",
                    "assistant",
                    "Use a concise caption, mention what changed, and keep the note focused on the user-facing setup flow.",
                ),
            ],
        },
    ]

    with sqlite3.connect(database_path) as connection:
        for table in [
            CONVERSATION_TABLE,
            MESSAGE_TABLE,
            GENERATED_CONVERSATION_TABLE,
            GENERATED_MESSAGE_TABLE,
            GENERATED_MODEL_TABLE,
        ]:
            create_payload_table(connection, table)
            connection.execute(f'DELETE FROM "{table}"')

        insert_payload(
            connection,
            GENERATED_MODEL_TABLE,
            "name:llava:latest",
            generated_model_payload(),
        )

        for conversation_index, conversation in enumerate(conversations):
            conversation_time = base + dt.timedelta(minutes=conversation_index * 5)
            generated_conversation = generated_conversation_payload(
                conversation["id"],
                conversation["title"],
                conversation_time,
                conversation_time + dt.timedelta(minutes=4),
            )
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
            insert_payload(
                connection,
                GENERATED_CONVERSATION_TABLE,
                f'id:{conversation["id"]}',
                generated_conversation,
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
                insert_payload(
                    connection,
                    GENERATED_MESSAGE_TABLE,
                    f"id:{message_id}",
                    generated_message_payload(
                        message_id,
                        role,
                        content,
                        message_time,
                        generated_conversation,
                    ),
                )


def seed_database(home: Path) -> None:
    seed_database_file(home / ".quilldata" / "default.sqlite")
    seed_database_file(home / ".quillui" / "enchanted" / "enchanted-quilldata.sqlite")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: seed-enchanted-reference-data.py HOME_DIR", file=sys.stderr)
        return 64

    seed_database(Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
