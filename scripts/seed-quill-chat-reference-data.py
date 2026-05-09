#!/usr/bin/env python3
import datetime
import json
import os
import sqlite3
import sys
import uuid


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: seed-quill-chat-reference-data.py HOME_DIR", file=sys.stderr)
        return 64

    home = sys.argv[1]
    database_dir = os.path.join(home, ".quilldata")
    os.makedirs(database_dir, exist_ok=True)
    database_path = os.path.join(database_dir, "default.sqlite")
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    items = [
        (3, 0, "Auto-config test: reply with one short phrase confirming you got this."),
        (3, 1, "say one short word"),
        (3, 2, "say hi in one word"),
        (4, 0, "Write a text message asking a friend to be my plus-one at a wedding"),
        (7, 0, "Give me phrases to learn in a new language"),
        (7, 1, "How to center div in HTML?"),
        (7, 2, "Long transcript scroll test"),
    ]

    connection = sqlite3.connect(database_path)
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS "quillDataRecords" (
            "modelType" TEXT NOT NULL,
            "modelID" TEXT NOT NULL,
            "json" BLOB NOT NULL,
            "updatedAt" DATETIME NOT NULL,
            PRIMARY KEY("modelType", "modelID") ON CONFLICT REPLACE
        )
        """
    )
    transcript_conversation_id = None
    transcript_conversation_payload = None
    transcript_base_time = None
    long_conversation_id = None
    long_conversation_payload = None
    long_base_time = None
    for days, rank, title in items:
        updated = now - datetime.timedelta(days=days, seconds=rank)
        json_stamp = updated.strftime("%Y-%m-%dT%H:%M:%SZ")
        sqlite_stamp = updated.strftime("%Y-%m-%d %H:%M:%S.000")
        model_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "quill-chat-reference:" + title))
        payload = {
            "id": model_id,
            "name": title,
            "createdAt": json_stamp,
            "updatedAt": json_stamp,
            "model": None,
            "messages": [],
        }
        connection.execute(
            """
            INSERT OR REPLACE INTO "quillDataRecords"
                ("modelType", "modelID", "json", "updatedAt")
            VALUES (?, ?, ?, ?)
            """,
            (
                "GeneratedSwiftUILinuxApp.ConversationSD",
                model_id,
                json.dumps(payload).encode(),
                sqlite_stamp,
            ),
        )
        if title == "How to center div in HTML?":
            transcript_conversation_id = model_id
            transcript_conversation_payload = payload
            transcript_base_time = updated
        elif title == "Long transcript scroll test":
            long_conversation_id = model_id
            long_conversation_payload = payload
            long_base_time = updated

    if transcript_conversation_id and transcript_conversation_payload and transcript_base_time:
        messages = [
            (
                "user",
                "How to center div in HTML?",
                transcript_base_time + datetime.timedelta(seconds=1),
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
                transcript_base_time + datetime.timedelta(seconds=2),
            ),
        ]
        for role, content, created_at in messages:
            message_id = str(
                uuid.uuid5(
                    uuid.NAMESPACE_URL,
                    f"quill-chat-reference:{transcript_conversation_id}:{role}:{content}",
                )
            )
            json_stamp = created_at.strftime("%Y-%m-%dT%H:%M:%SZ")
            sqlite_stamp = created_at.strftime("%Y-%m-%d %H:%M:%S.000")
            payload = {
                "id": message_id,
                "content": content,
                "role": role,
                "done": role == "assistant",
                "error": False,
                "createdAt": json_stamp,
                "conversation": transcript_conversation_payload,
            }
            connection.execute(
                """
                INSERT OR REPLACE INTO "quillDataRecords"
                    ("modelType", "modelID", "json", "updatedAt")
                VALUES (?, ?, ?, ?)
                """,
                (
                    "GeneratedSwiftUILinuxApp.MessageSD",
                    message_id,
                    json.dumps(payload).encode(),
                    sqlite_stamp,
                ),
            )

    if long_conversation_id and long_conversation_payload and long_base_time:
        long_messages = []
        for index in range(18):
            pair = index + 1
            long_messages.append(
                (
                    "user",
                    f"Long transcript prompt {pair}: please keep the answer concise.",
                    long_base_time + datetime.timedelta(seconds=index * 2 + 1),
                )
            )
            long_messages.append(
                (
                    "assistant",
                    f"Long transcript reply {pair}: this is enough content to make the chat scroll.",
                    long_base_time + datetime.timedelta(seconds=index * 2 + 2),
                )
            )
        long_messages.append(
            (
                "user",
                "Final user check: bottom scroll target visible near the composer.",
                long_base_time + datetime.timedelta(seconds=101),
            )
        )
        long_messages.append(
            (
                "assistant",
                "Final answer: bottom scroll target is visible near the composer. "
                "This intentionally long final response gives the Linux visual smoke test "
                "a dense left-aligned bottom marker after ScrollViewReader scrolls to the newest message.",
                long_base_time + datetime.timedelta(seconds=102),
            )
        )

        for role, content, created_at in long_messages:
            message_id = str(
                uuid.uuid5(
                    uuid.NAMESPACE_URL,
                    f"quill-chat-reference:{long_conversation_id}:{role}:{content}",
                )
            )
            json_stamp = created_at.strftime("%Y-%m-%dT%H:%M:%SZ")
            sqlite_stamp = created_at.strftime("%Y-%m-%d %H:%M:%S.000")
            payload = {
                "id": message_id,
                "content": content,
                "role": role,
                "done": role == "assistant",
                "error": False,
                "createdAt": json_stamp,
                "conversation": long_conversation_payload,
            }
            connection.execute(
                """
                INSERT OR REPLACE INTO "quillDataRecords"
                    ("modelType", "modelID", "json", "updatedAt")
                VALUES (?, ?, ?, ?)
                """,
                (
                    "GeneratedSwiftUILinuxApp.MessageSD",
                    message_id,
                    json.dumps(payload).encode(),
                    sqlite_stamp,
                ),
            )
    connection.commit()
    connection.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
