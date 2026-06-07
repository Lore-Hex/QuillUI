#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import sqlite3
import sys
import uuid
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


def generated_model_payload(
    name: str = "llava:latest",
    image_support: bool = True,
) -> dict[str, object]:
    return {
        "name": name,
        "isAvailable": False,
        "imageSupport": image_support,
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


def reference_uuid(value: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "quill-chat-reference:" + value))


def quill_chat_reference_items(now: dt.datetime) -> list[dict[str, object]]:
    items = [
        (3, 0, "Auto-config test: reply with one short phrase confirming you got this."),
        (3, 1, "say one short word"),
        (3, 2, "say hi in one word"),
        (4, 0, "Write a text message asking a friend to be my plus-one at a wedding"),
        (7, 0, "Give me phrases to learn in a new language"),
        (7, 1, "How to center div in HTML?"),
        (7, 2, "Long transcript scroll test"),
    ]

    conversations: list[dict[str, object]] = []
    for days, rank, title in items:
        updated = now - dt.timedelta(days=days, seconds=rank)
        conversations.append(
            {
                "id": reference_uuid(title),
                "title": title,
                "created_at": updated,
                "updated_at": updated,
                "messages": [],
            }
        )

    markdown_conversation = next(
        conversation for conversation in conversations if conversation["title"] == "How to center div in HTML?"
    )
    markdown_time = markdown_conversation["updated_at"]
    markdown_conversation["messages"] = [
        (
            "user",
            "How to center div in HTML?",
            markdown_time + dt.timedelta(seconds=1),
        ),
        (
            "assistant",
            "Use **flexbox**: set `display` to `flex`, then align-items and justify-content to center. "
            "See [MDN flexbox](https://developer.mozilla.org/docs/Web/CSS/CSS_flexible_box_layout) for details.\n\n"
            "## CSS example\n\n"
            "```css\n"
            ".parent {\n"
            "  display: flex;\n"
            "  align-items: center;\n"
            "  justify-content: center;\n"
            "}\n"
            "```\n\n"
            "| Property | Value |\n"
            "| --- | --- |\n"
            "| display | `flex` |\n"
            "| align-items | `center` |\n"
            "| justify-content | `center` |\n\n"
            "> This keeps the child centered in both axes.\n\n"
            "- Give the parent a height.\n"
            "- Put the content inside one child element.",
            markdown_time + dt.timedelta(seconds=2),
        ),
    ]

    long_conversation = next(
        conversation for conversation in conversations if conversation["title"] == "Long transcript scroll test"
    )
    long_time = long_conversation["updated_at"]
    long_messages = []
    for index in range(18):
        pair = index + 1
        long_messages.append(
            (
                "user",
                f"Long transcript prompt {pair}: please keep the answer concise.",
                long_time + dt.timedelta(seconds=index * 2 + 1),
            )
        )
        long_messages.append(
            (
                "assistant",
                f"Long transcript reply {pair}: this is enough content to make the chat scroll.",
                long_time + dt.timedelta(seconds=index * 2 + 2),
            )
        )
    long_messages.append(
        (
            "user",
            "Final user check: bottom scroll target visible near the composer.",
            long_time + dt.timedelta(seconds=101),
        )
    )
    long_messages.append(
        (
            "assistant",
            "Final answer: bottom scroll target is visible near the composer. "
            "This intentionally long final response gives the Linux visual smoke test "
            "a dense left-aligned bottom marker after ScrollViewReader scrolls to the newest message.",
            long_time + dt.timedelta(seconds=102),
        )
    )
    long_conversation["messages"] = long_messages

    return conversations


def seed_database_file(database_path: Path) -> None:
    database_path.parent.mkdir(parents=True, exist_ok=True)

    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    conversations = quill_chat_reference_items(now)

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
        insert_payload(
            connection,
            GENERATED_MODEL_TABLE,
            "name:mistral-7b-reference-linux-picker:latest",
            generated_model_payload(
                name="mistral-7b-reference-linux-picker:latest",
                image_support=False,
            ),
        )

        for conversation in conversations:
            conversation_id = str(conversation["id"])
            conversation_time = conversation["created_at"]
            updated_at = conversation["updated_at"]
            generated_conversation = generated_conversation_payload(
                conversation_id,
                str(conversation["title"]),
                conversation_time,
                updated_at,
            )
            insert_payload(
                connection,
                CONVERSATION_TABLE,
                conversation_id,
                {
                    "id": conversation_id,
                    "title": conversation["title"],
                    "createdAt": seconds_since_reference(conversation_time),
                    "updatedAt": seconds_since_reference(updated_at),
                },
            )
            insert_payload(
                connection,
                GENERATED_CONVERSATION_TABLE,
                f"id:{conversation_id}",
                generated_conversation,
            )

            for role, content, message_time in conversation["messages"]:
                message_id = reference_uuid(f"{conversation_id}:{role}:{content}")
                insert_payload(
                    connection,
                    MESSAGE_TABLE,
                    message_id,
                    {
                        "id": message_id,
                        "conversationID": conversation_id,
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
