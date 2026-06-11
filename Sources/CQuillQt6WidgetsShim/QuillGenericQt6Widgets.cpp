#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QAction>
#include <QApplication>
#include <QColor>
#include <QDateTime>
#include <QDialog>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFrame>
#include <QFontMetrics>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLayout>
#include <QLinearGradient>
#include <QList>
#include <QListWidget>
#include <QListWidgetItem>
#include <QLineEdit>
#include <QMenu>
#include <QAbstractItemView>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPoint>
#include <QPushButton>
#include <QPixmap>
#include <QScrollArea>
#include <QScrollBar>
#include <QSize>
#include <QSizePolicy>
#include <QSplitter>
#include <QStackedLayout>
#include <QStyle>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUuid>
#include <QVBoxLayout>
#include <QWidget>

#include <algorithm>
#include <cmath>
#include <cstdlib>

#include <sqlite3.h>

namespace {

using QuillQtWidgets::clearLayout;
using QuillQtWidgets::cssPixels;
using QuillQtWidgets::jsonArrayValue;
using QuillQtWidgets::jsonIntValue;
using QuillQtWidgets::jsonObjectValue;
using QuillQtWidgets::jsonStringValue;
using QuillQtWidgets::jsonStyleValue;
using QuillQtWidgets::label;

QString stringValue(const QJsonObject &object, const char *key, const QString &fallback = QString()) {
    return jsonStringValue(object, key, fallback);
}

bool macReferenceMode() {
    return QuillQtWidgets::environmentFlag("QUILLUI_BACKEND_MAC_REFERENCE")
        || QuillQtWidgets::environmentFlag("QUILLUI_QT_MAC_REFERENCE");
}

double metricScale() {
    const QString explicitScale =
        QuillQtWidgets::environmentValue("QUILLUI_GENERIC_QT_METRIC_SCALE").trimmed();
    if (!explicitScale.isEmpty()) {
        bool parsed = false;
        const double scale = explicitScale.toDouble(&parsed);
        if (parsed && scale > 0.0) {
            return scale;
        }
    }

    if (macReferenceMode()) {
        return 2.0;
    }

    return 1.0;
}

bool scalesMetricKey(const char *key) {
    const QString name = QString::fromUtf8(key).toLower();
    return name != QStringLiteral("selectedindex")
        && name != QStringLiteral("headerheight")
        && !name.endsWith(QStringLiteral("weight"))
        && !name.endsWith(QStringLiteral("columns"));
}

int intValue(const QJsonObject &object, const char *key, int fallback) {
    const int value = jsonIntValue(object, key, fallback);
    if (macReferenceMode()) {
        const QString name = QString::fromUtf8(key).toLower();
        if (name == QStringLiteral("settingspanelminwidth")) {
            return 860;
        }
        if (name == QStringLiteral("settingspanelmaxwidth")) {
            return 900;
        }
        if (name == QStringLiteral("settingspanelpadding")) {
            return 16;
        }
        if (name == QStringLiteral("settingspanelspacing")) {
            return 4;
        }
        if (name == QStringLiteral("settingsfieldspacing")) {
            return 2;
        }
        if (name == QStringLiteral("settingsfieldminheight")) {
            return 32;
        }
    }
    const double scale = metricScale();
    if (scale == 1.0 || !scalesMetricKey(key)) {
        return value;
    }
    return std::max(1, static_cast<int>(std::lround(static_cast<double>(value) * scale)));
}

QString styleValue(const QJsonObject &style, const char *key, const char *fallback) {
    if (macReferenceMode() && QString::fromUtf8(key) == QStringLiteral("sidebarColor")) {
        return QStringLiteral("#EEF2EA");
    }
    return jsonStyleValue(style, key, fallback);
}

QString quillDataDatabasePath() {
    QByteArray home = qgetenv("QUILLDATA_HOME");
    if (home.isEmpty()) {
        home = qgetenv("HOME");
    }
    if (home.isEmpty()) {
        return QString();
    }
    return QDir(QString::fromUtf8(home)).filePath(QStringLiteral(".quilldata/default.sqlite"));
}

int collectSqliteTableNames(void *context, int argc, char **argv, char **) {
    if (!context || argc < 1 || !argv || !argv[0]) {
        return 0;
    }

    static_cast<QStringList *>(context)->append(QString::fromUtf8(argv[0]));
    return 0;
}

bool sqliteExec(sqlite3 *database, const QByteArray &sql) {
    char *error = nullptr;
    const int status = sqlite3_exec(database, sql.constData(), nullptr, nullptr, &error);
    if (error) {
        sqlite3_free(error);
    }
    return status == SQLITE_OK;
}

QString generatedConversationTableName() {
    return QStringLiteral("_quilldata_json_GeneratedSwiftUILinuxApp_ConversationSD");
}

QString generatedMessageTableName() {
    return QStringLiteral("_quilldata_json_GeneratedSwiftUILinuxApp_MessageSD");
}

QString generatedModelTableName() {
    return QStringLiteral("_quilldata_json_GeneratedSwiftUILinuxApp_LanguageModelSD");
}

double secondsSinceAppleReferenceNow() {
    constexpr double appleReferenceUnixSeconds = 978307200.0;
    return (static_cast<double>(QDateTime::currentMSecsSinceEpoch()) / 1000.0) - appleReferenceUnixSeconds;
}

QString referencePickerModelName() {
    const char *environmentModel = std::getenv("QUILLUI_BACKEND_SELECTED_MODEL_NAME");
    if (environmentModel != nullptr && environmentModel[0] != '\0') {
        return QString::fromUtf8(environmentModel);
    }
    return QStringLiteral("mistral-7b-reference-linux-picker:latest");
}

QString &selectedChatModelName() {
    static QString modelName = []() {
        const char *environmentModelValue = std::getenv("QUILLUI_BACKEND_SELECTED_MODEL_NAME");
        if (environmentModelValue == nullptr || environmentModelValue[0] == '\0') {
            return QStringLiteral("llava:latest");
        }
        const QString environmentModel = QString::fromUtf8(environmentModelValue).trimmed();
        return environmentModel.isEmpty()
            ? QStringLiteral("llava:latest")
            : environmentModel;
    }();
    return modelName;
}

QJsonObject generatedModelPayload(const QString &modelName) {
    return QJsonObject {
        { QStringLiteral("name"), modelName },
        { QStringLiteral("isAvailable"), false },
        { QStringLiteral("imageSupport"), modelName.contains(QStringLiteral("llava"), Qt::CaseInsensitive) },
        { QStringLiteral("modelProvider"), QJsonObject { { QStringLiteral("ollama"), QJsonObject() } } },
        { QStringLiteral("conversations"), QJsonArray() }
    };
}

bool ensurePayloadTable(sqlite3 *database, const QString &table) {
    const QByteArray tableName = table.toUtf8();
    char *escapedTableName = sqlite3_mprintf("%w", tableName.constData());
    if (!escapedTableName) {
        return false;
    }
    const QByteArray sql = QByteArrayLiteral("CREATE TABLE IF NOT EXISTS \"")
        + QByteArray(escapedTableName)
        + QByteArrayLiteral("\" (id TEXT PRIMARY KEY ON CONFLICT REPLACE, payload BLOB NOT NULL)");
    sqlite3_free(escapedTableName);
    return sqliteExec(database, sql);
}

bool insertPayload(sqlite3 *database, const QString &table, const QString &recordID, const QJsonObject &payload) {
    const QByteArray tableName = table.toUtf8();
    char *escapedTableName = sqlite3_mprintf("%w", tableName.constData());
    if (!escapedTableName) {
        return false;
    }
    const QByteArray sql = QByteArrayLiteral("INSERT OR REPLACE INTO \"")
        + QByteArray(escapedTableName)
        + QByteArrayLiteral("\" (id, payload) VALUES (?, ?)");
    sqlite3_free(escapedTableName);

    sqlite3_stmt *statement = nullptr;
    if (sqlite3_prepare_v2(database, sql.constData(), -1, &statement, nullptr) != SQLITE_OK || !statement) {
        return false;
    }

    const QByteArray idBytes = recordID.toUtf8();
    const QByteArray payloadBytes = QJsonDocument(payload).toJson(QJsonDocument::Compact);
    sqlite3_bind_text(statement, 1, idBytes.constData(), idBytes.size(), SQLITE_TRANSIENT);
    sqlite3_bind_blob(statement, 2, payloadBytes.constData(), payloadBytes.size(), SQLITE_TRANSIENT);
    const bool ok = sqlite3_step(statement) == SQLITE_DONE;
    sqlite3_finalize(statement);
    return ok;
}

QJsonArray promptConversationMessages(const QString &promptTitle) {
    const QString assistantBody = promptTitle.contains(QStringLiteral("center div"), Qt::CaseInsensitive)
        ? QStringLiteral("Use **flexbox**: set display to flex, then align-items and justify-content to center.")
        : QStringLiteral("I can help with that. Here is a concise first draft.");
    return QJsonArray {
        QJsonObject {
            { QStringLiteral("role"), QStringLiteral("user") },
            { QStringLiteral("sender"), QStringLiteral("user") },
            { QStringLiteral("body"), promptTitle },
            { QStringLiteral("content"), promptTitle }
        },
        QJsonObject {
            { QStringLiteral("role"), QStringLiteral("assistant") },
            { QStringLiteral("sender"), QStringLiteral("assistant") },
            { QStringLiteral("body"), assistantBody },
            { QStringLiteral("content"), assistantBody }
        }
    };
}

void persistPromptConversation(const QString &promptTitle) {
    const QString path = quillDataDatabasePath();
    if (path.isEmpty()) {
        return;
    }

    QDir().mkpath(QFileInfo(path).absolutePath());
    sqlite3 *database = nullptr;
    if (sqlite3_open(path.toUtf8().constData(), &database) != SQLITE_OK || !database) {
        if (database) {
            sqlite3_close(database);
        }
        return;
    }

    const QString conversationTable = generatedConversationTableName();
    const QString messageTable = generatedMessageTableName();
    const QString modelTable = generatedModelTableName();
    if (!ensurePayloadTable(database, conversationTable)
        || !ensurePayloadTable(database, messageTable)
        || !ensurePayloadTable(database, modelTable)) {
        sqlite3_close(database);
        return;
    }

    const QString modelName = selectedChatModelName();
    const QString conversationID = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const double createdAt = secondsSinceAppleReferenceNow();
    const QJsonObject model = generatedModelPayload(modelName);
    const QJsonObject conversation {
        { QStringLiteral("id"), conversationID },
        { QStringLiteral("name"), promptTitle },
        { QStringLiteral("createdAt"), createdAt },
        { QStringLiteral("updatedAt"), createdAt + 1.0 },
        { QStringLiteral("model"), model },
        { QStringLiteral("messages"), QJsonArray() }
    };
    insertPayload(database, modelTable, QStringLiteral("name:") + modelName, model);
    insertPayload(database, conversationTable, QStringLiteral("id:") + conversationID, conversation);

    const QJsonArray messages = promptConversationMessages(promptTitle);
    for (int index = 0; index < messages.size(); index += 1) {
        const QJsonObject message = messages.at(index).toObject();
        const QString role = stringValue(message, "role", QStringLiteral("assistant"));
        const QString body = stringValue(message, "content", stringValue(message, "body"));
        const QString messageID = QUuid::createUuid().toString(QUuid::WithoutBraces);
        insertPayload(database, messageTable, QStringLiteral("id:") + messageID, QJsonObject {
            { QStringLiteral("id"), messageID },
            { QStringLiteral("role"), role },
            { QStringLiteral("content"), body },
            { QStringLiteral("createdAt"), createdAt + static_cast<double>(index + 1) },
            { QStringLiteral("done"), role == QStringLiteral("assistant") },
            { QStringLiteral("error"), false },
            { QStringLiteral("conversation"), conversation }
        });
    }

    sqlite3_close(database);
}

void clearQuillChatConversationStore() {
    const QString path = quillDataDatabasePath();
    if (path.isEmpty()) {
        return;
    }

    QDir().mkpath(QFileInfo(path).absolutePath());

    sqlite3 *database = nullptr;
    if (sqlite3_open(path.toUtf8().constData(), &database) != SQLITE_OK || !database) {
        if (database) {
            sqlite3_close(database);
        }
        return;
    }

    QStringList tables;
    char *error = nullptr;
    const int tableStatus = sqlite3_exec(
        database,
        "SELECT name FROM sqlite_master WHERE type = 'table'",
        collectSqliteTableNames,
        &tables,
        &error
    );
    if (error) {
        sqlite3_free(error);
    }
    if (tableStatus != SQLITE_OK) {
        sqlite3_close(database);
        return;
    }

    if (tables.contains(QStringLiteral("quillDataRecords"))) {
        sqliteExec(database, QByteArrayLiteral(
            "DELETE FROM \"quillDataRecords\" "
            "WHERE \"modelType\" LIKE '%.ConversationSD' "
            "OR \"modelType\" LIKE '%.MessageSD'"
        ));
    }

    for (const QString &table : tables) {
        if (!table.endsWith(QStringLiteral("_ConversationSD"))
            && !table.endsWith(QStringLiteral("_MessageSD"))) {
            continue;
        }

        const QByteArray tableName = table.toUtf8();
        char *escapedTableName = sqlite3_mprintf("%w", tableName.constData());
        if (!escapedTableName) {
            continue;
        }

        const QByteArray sql = QByteArrayLiteral("DELETE FROM \"")
            + QByteArray(escapedTableName)
            + QByteArrayLiteral("\"");
        sqlite3_free(escapedTableName);
        sqliteExec(database, sql);
    }

    sqlite3_close(database);
}

QString accessibilitySummary(const QString &title, const QString &detail) {
    if (title.isEmpty()) {
        return detail;
    }
    if (detail.isEmpty()) {
        return title;
    }
    return title + QStringLiteral(". ") + detail;
}

void applyAccessibleText(QWidget *widget, const QString &name, const QString &description = QString()) {
    if (widget == nullptr) {
        return;
    }
    const QString summary = description.isEmpty() ? name : description;
    if (name.isEmpty() && summary.isEmpty()) {
        return;
    }
    widget->setAccessibleName(name.isEmpty() ? summary : name);
    widget->setAccessibleDescription(summary);
    widget->setToolTip(summary);
    widget->setStatusTip(summary);
}

struct GenericDetailPane {
    QWidget *view;
    QLabel *titleLabel;
    QLabel *subtitleLabel;
    QVBoxLayout *contentLayout;
    QScrollArea *contentScrollArea;
    bool preservesHeaderTitle;
};

struct GenericSelection {
    bool hasSelection;
    QString detailTitle;
    QString detailSubtitle;
    QString messagesTitle;
    QJsonArray sections;
    QJsonArray messages;
};

QString messageSender(const QJsonObject &message) {
    return stringValue(message, "sender", stringValue(message, "role", QStringLiteral("assistant")));
}

QString messageBody(const QJsonObject &message) {
    return stringValue(message, "body", stringValue(message, "content"));
}

QString titleCasedSender(QString sender) {
    sender = sender.trimmed();
    if (sender.isEmpty()) {
        return QStringLiteral("Assistant");
    }
    sender[0] = sender[0].toUpper();
    return sender;
}

QString chatMessagesPlainText(const QJsonArray &messages) {
    QStringList lines;
    for (const QJsonValue &value : messages) {
        const QJsonObject message = value.toObject();
        const QString body = messageBody(message).trimmed();
        if (body.isEmpty()) {
            continue;
        }
        lines.append(titleCasedSender(messageSender(message)) + QStringLiteral(": ") + body);
    }
    return lines.join(QStringLiteral("\n\n"));
}

QString chatMessagesJsonText(const QJsonArray &messages) {
    QJsonArray payload;
    for (const QJsonValue &value : messages) {
        const QJsonObject message = value.toObject();
        const QString body = messageBody(message);
        if (body.trimmed().isEmpty()) {
            continue;
        }
        QJsonObject encoded;
        encoded.insert(QStringLiteral("role"), messageSender(message).trimmed().toLower());
        encoded.insert(QStringLiteral("content"), body);
        payload.append(encoded);
    }
    return QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

bool writeFileBackedPasteboardText(const QString &text) {
    if (text.isEmpty()) {
        return false;
    }
    QString runtimeDirectory = QuillQtWidgets::environmentValue("XDG_RUNTIME_DIR");
    if (runtimeDirectory.trimmed().isEmpty()) {
        runtimeDirectory = QStringLiteral("/tmp");
    }
    const QString typesDirectory =
        runtimeDirectory
        + QStringLiteral("/quill-pasteboard/Apple.NSGeneralPboard/types");
    if (!QDir().mkpath(typesDirectory)) {
        return false;
    }
    QFile file(typesDirectory + QStringLiteral("/public.utf8-plain-text"));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    return file.write(text.toUtf8()) >= 0;
}

QString genericStyleSheet(const QJsonObject &style) {
    const QString canvas = styleValue(style, "canvasColor", "#F7F8F4");
    const QString ink = styleValue(style, "inkColor", "#182027");
    const QString sidebar = styleValue(style, "sidebarColor", "#EEF2EA");
    const QString header = styleValue(style, "headerColor", "#F7F8F4");
    const QString muted = styleValue(style, "mutedColor", "#65707A");
    const QString badge = styleValue(style, "badgeColor", "#295A7A");
    const QString card = styleValue(style, "cardColor", "#FFFFFF");
    const QString promptCard = styleValue(style, "promptCardColor", "#FFFFFF");
    const QString notice = styleValue(style, "noticeColor", "#F8D7DA");
    const QString noticeButtonColor = styleValue(style, "noticeButtonColor", "#000000");
    const QString messageUserBubble = styleValue(style, "messageUserBubbleColor", "#007AFF");
    const QString messageAssistantBubble = styleValue(style, "messageAssistantBubbleColor", "#F6F6F6");
    const QString messageSystemBubble = styleValue(style, "messageSystemBubbleColor", "#E8E8ED");
    const QString activeCard = styleValue(style, "activeCardColor", "#E7F0FA");
    const QString primary = styleValue(style, "primaryColor", "#2E5B78");
    const QString selected = styleValue(style, "selectedMutedColor", "#DDEBFA");
    const QString border = styleValue(style, "borderColor", "#E0E4DC");
    const QString selectedBorder = styleValue(style, "selectedBorderColor", "#CBDDEB");
    const QString divider = styleValue(style, "dividerColor", "#D8DDD4");
    const QString controlBorder = styleValue(style, "controlBorderColor", "#CDD5CA");
    const QString rootFontSize = cssPixels(style, "rootFontSize", 14);
    const QString appTitleFontSize = cssPixels(style, "appTitleFontSize", 26);
    const QString appTitleFontWeight = QString::number(intValue(style, "appTitleFontWeight", 700));
    const QString captionFontSize = cssPixels(style, "captionFontSize", 12);
    const QString sectionTitleFontSize = cssPixels(style, "sectionTitleFontSize", 15);
    const QString sectionTitleFontWeight = QString::number(intValue(style, "sectionTitleFontWeight", 700));
    const QString currentTitleFontSize = cssPixels(style, "currentTitleFontSize", 20);
    const QString currentTitleFontWeight = QString::number(intValue(style, "currentTitleFontWeight", 650));
    const QString emptyStateWordmarkFontSize = cssPixels(style, "emptyStateWordmarkFontSize", 46);
    const QString emptyStateWordmarkFontWeight =
        QString::number(intValue(style, "emptyStateWordmarkFontWeight", 100));
    const QString messageBodyFontSize = cssPixels(style, "messageBodyFontSize", 14);
    const QString conversationTitleFontSize = cssPixels(style, "conversationTitleFontSize", 15);
    const QString conversationTitleFontWeight = QString::number(intValue(style, "conversationTitleFontWeight", 700));
    const QString cardRadius = cssPixels(style, "cardRadius", 8);
    const QString activeCardRadius = cssPixels(style, "activeCardRadius", 8);
    const QString messageCardRadius = cssPixels(style, "messageCardRadius", 8);
    const QString listItemRadius = cssPixels(style, "listItemRadius", 8);
    const QString listItemVerticalMargin = cssPixels(style, "listItemVerticalMargin", 2);
    const QString listItemPadding = cssPixels(style, "listItemPadding", 8);
    const QString primaryButtonRadius = cssPixels(style, "primaryButtonRadius", 8);
    const QString primaryButtonVerticalPadding = cssPixels(style, "primaryButtonVerticalPadding", 8);
    const QString primaryButtonHorizontalPadding = cssPixels(style, "primaryButtonHorizontalPadding", 12);
    const QString secondaryButtonRadius = cssPixels(style, "secondaryButtonRadius", 7);
    const QString secondaryButtonVerticalPadding = cssPixels(style, "secondaryButtonVerticalPadding", 7);
    const QString secondaryButtonHorizontalPadding = cssPixels(style, "secondaryButtonHorizontalPadding", 10);
    const QString promptButtonRadius = cssPixels(style, "promptButtonRadius", 8);
    const QString promptButtonPadding = cssPixels(style, "promptButtonPadding", 12);
    const QString composerEditorRadius = cssPixels(style, "composerEditorRadius", 23);
    const QString conversationSelectionDotRadius = cssPixels(style, "conversationSelectionDotRadius", 4);

    QString sheet = QStringLiteral(R"(
        QWidget#genericRoot { background: %1; color: %2; font-size: %3; }
        QWidget#detailBody, QWidget#conversationHost, QWidget#emptyState, QWidget#promptGridHost { background: %1; }
        QFrame#sidebar { background: %4; border-right: 1px solid %5; }
        QLabel#subtitle, QLabel#caption, QLabel#statusText, QLabel#itemSubtitle, QLabel#messageMeta { color: %6; font-size: %7; }
    )").arg(
        canvas,
        ink,
        rootFontSize,
        sidebar,
        divider,
        muted,
        captionFontSize
    );

    sheet += QStringLiteral(R"(
        QFrame#detailHeader { background: %1; border-bottom: 1px solid %2; }
        QLabel#emptyWordmark { color: %3; font-size: %4; font-weight: %5; }
        QLabel#promptIcon { color: %6; font-size: %7; font-weight: %8; }
        QLabel#promptTitle { color: %6; font-size: %9; font-weight: 500; }
        QLabel#chatSidebarDate { color: %10; font-size: %11; font-weight: 650; }
        QLabel#chatSidebarTitle { color: %6; font-size: %12; font-weight: 450; }
        QLabel#settingsTitle { color: %6; font-size: %13; font-weight: 650; }
        QLabel#settingsFormLabel { color: %6; font-size: %11; font-weight: 600; }
    )").arg(
        header,
        divider,
        primary,
        emptyStateWordmarkFontSize,
        emptyStateWordmarkFontWeight,
        ink,
        captionFontSize,
        sectionTitleFontWeight,
        conversationTitleFontSize,
        muted,
        sectionTitleFontSize,
        conversationTitleFontSize,
        currentTitleFontSize
    );

    sheet += QStringLiteral(R"(
        QFrame#card { background: %1; border: 1px solid %2; border-radius: %3; }
        QFrame#messageCard { background: %1; border: 1px solid %2; border-radius: %4; }
    )").arg(
        card,
        border,
        cardRadius,
        messageCardRadius
    );

    sheet += QStringLiteral(R"(
        QFrame#promptCard, QPushButton#promptCard { background: %1; border: 0; border-radius: %2; text-align: left; }
        QFrame#notice { background: %3; border: 0; border-radius: %2; }
        QFrame#composerFrame { background: %4; border: 1px solid %6; border-radius: %7; }
        QLineEdit#composerEditor { background: transparent; color: %5; border: 0; padding-left: 0; padding-right: 0; }
        QLabel#composerAccessoryIcon { background: transparent; border: 0; }
        QFrame#settingsPanel { background: %1; border: 0; border-radius: %2; }
        QLineEdit#settingsField { background: white; color: %5; border: 1px solid %6; border-radius: %2; padding: %8; }
        QPushButton#settingsOptionButton { background: white; color: %5; border: 1px solid %6; border-radius: %2; padding: %8; }
        QPushButton#settingsPrimaryButton { background: %5; color: white; border: 0; border-radius: %2; padding: %8; font-weight: 650; }
        QPushButton#settingsDangerButton { background: #D93A34; color: white; border: 0; border-radius: %2; padding: %8; font-weight: 650; }
        QLabel#completionTitle { color: #B06FD0; font-size: %9; font-weight: 400; }
        QLabel#completionShortcutBadge { background: %1; color: %5; border-radius: %2; padding: 3px 7px; font-size: %10; }
        QLabel#completionName, QLabel#completionInstruction { color: %5; font-size: %10; }
        QFrame#completionDivider { background: %11; border: 0; min-height: 1px; max-height: 1px; }
        QPushButton#completionLinkButton { background: transparent; color: #0057FF; border: 0; padding: 0; font-size: %9; font-weight: 550; }
        QPushButton#completionActionButton { background: transparent; color: %5; border: 0; padding: 0; font-size: %9; }
    )").arg(
        promptCard,
        promptButtonRadius,
        notice,
        canvas,
        ink,
        controlBorder,
        composerEditorRadius,
        promptButtonPadding,
        currentTitleFontSize,
        captionFontSize,
        divider
    );

    sheet += QStringLiteral(R"(
        QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }
        QLabel#sectionTitle { color: %1; font-size: %4; font-weight: %5; }
        QLabel#detailTitle { color: %1; font-size: %6; font-weight: %7; }
        QLabel#chatHeaderTitle { color: %1; font-size: %8; font-weight: 500; }
        QLabel#headline { color: %1; font-size: %8; font-weight: %9; }
    )").arg(
        ink,
        appTitleFontSize,
        appTitleFontWeight,
        sectionTitleFontSize,
        sectionTitleFontWeight,
        currentTitleFontSize,
        currentTitleFontWeight,
        conversationTitleFontSize,
        conversationTitleFontWeight
    );

    sheet += QStringLiteral(R"(
        QLabel#bodyText, QLabel#messageText { color: %1; font-size: %2; line-height: 140%; }
        QLabel#messageTextInverted { color: white; font-size: %2; line-height: 140%; }
        QLabel#markdownCodeText { color: %1; font-size: %2; font-family: monospace; }
        QLabel#badge { color: %3; font-size: %4; font-weight: %5; }
    )").arg(ink, messageBodyFontSize, badge, captionFontSize, sectionTitleFontWeight);

    sheet += QStringLiteral(R"(
        QFrame#activeCard { background: %1; border: 1px solid %2; border-radius: %3; }
    )").arg(activeCard, selectedBorder, activeCardRadius);

    sheet += QStringLiteral(R"(
        QFrame#messageUserBubble { background: %1; border: 0; border-radius: %4; }
        QFrame#messageAssistantBubble { background: %2; border: 0; border-radius: %4; }
        QFrame#messageSystemBubble { background: %3; border: 0; border-radius: %4; }
        QFrame#markdownCodePanel { background: #F3F4F6; border: 1px solid #E1E4E8; border-radius: %4; }
        QFrame#markdownTablePanel { background: #F3F4F6; border: 1px solid #E1E4E8; border-radius: %4; }
        QFrame#markdownDivider { background: #D9DDE2; border: 0; min-height: 1px; max-height: 1px; }
    )").arg(messageUserBubble, messageAssistantBubble, messageSystemBubble, messageCardRadius);

    sheet += QStringLiteral(R"(
        QListWidget#itemList { background: transparent; border: 0; outline: 0; }
        QListWidget#itemList::item { border-radius: %1; margin: %2 0; padding: %3; }
        QListWidget#itemList::item:selected { background: %4; color: %5; }
        QListWidget#chatItemList { background: transparent; border: 0; outline: 0; }
        QListWidget#chatItemList::item { background: transparent; border: 0; margin: %2 0; padding: 0; }
        QListWidget#chatItemList::item:selected { background: transparent; color: %5; }
        QFrame#chatSelectionDot { background: transparent; border: 0; border-radius: %6; }
        QFrame#chatSelectionDot[selected="true"] { background: %7; }
    )").arg(
        listItemRadius,
        listItemVerticalMargin,
        listItemPadding,
        selected,
        ink,
        conversationSelectionDotRadius,
        primary
    );

    sheet += QStringLiteral(R"(
        QPushButton#primaryButton { background: %1; color: white; border: 0; border-radius: %2; padding: %3 %4; text-align: left; }
        QPushButton#secondaryButton { background: transparent; color: %5; border: 1px solid %6; border-radius: %7; padding: %8 %9; text-align: left; }
        QPushButton#sidebarNavigationButton { background: transparent; color: %5; border: 0; padding: %8 %9; text-align: left; }
        QPushButton#headerIconButton { background: transparent; border: 0; padding: %8; }
        QPushButton#headerIconButton:hover { background: %10; border-radius: %7; }
    )").arg(
        primary,
        primaryButtonRadius,
        primaryButtonVerticalPadding,
        primaryButtonHorizontalPadding,
        ink,
        controlBorder,
        secondaryButtonRadius,
        secondaryButtonVerticalPadding,
        secondaryButtonHorizontalPadding,
        selected
    );

    sheet += QStringLiteral(R"(
        QPushButton#noticeButton { background: %1; color: white; border: 0; border-radius: %2; padding: %3 %4; font-weight: %5; }
    )").arg(
        noticeButtonColor,
        secondaryButtonRadius,
        secondaryButtonVerticalPadding,
        secondaryButtonHorizontalPadding,
        sectionTitleFontWeight
    );

    sheet += QStringLiteral(R"(
        QFrame#windowDotClose { background: #FF5F57; border: 0; border-radius: 5px; }
        QFrame#windowDotMinimize { background: #FEBC2E; border: 0; border-radius: 5px; }
        QFrame#windowDotZoom { background: #28C840; border: 0; border-radius: 5px; }
        QLabel#sidebarChromeIcon { color: %1; font-size: %2; font-weight: 650; }
    )").arg(muted, sectionTitleFontSize);

    sheet += QStringLiteral(R"(
        QScrollArea { background: %1; border: 0; }
        QSplitter::handle { background: %2; }
        QSplitter::handle:horizontal { width: 1px; }
    )").arg(canvas, divider);

    return sheet;
}

int boundedSelectedIndex(const QJsonArray &items, int selectedIndex, bool allowsNoSelection = false) {
    if (items.isEmpty()) {
        return -1;
    }
    if (selectedIndex < 0) {
        return allowsNoSelection ? -1 : 0;
    }
    return std::min(std::max(selectedIndex, 0), static_cast<int>(items.size()) - 1);
}

QJsonObject selectedItem(const QJsonArray &items, int row) {
    if (row < 0 || row >= items.size()) {
        return QJsonObject();
    }
    return items.at(row).toObject();
}

GenericSelection selectionForRow(const QJsonObject &payload, const QJsonArray &items, int row) {
    const bool hasSelection = row >= 0 && row < items.size();
    const QString baseTitle = stringValue(payload, "detailTitle", QStringLiteral("Qt preview"));
    const QString baseSubtitle = stringValue(payload, "detailSubtitle");
    const QJsonObject item = hasSelection ? selectedItem(items, row) : QJsonObject();

    QString detailTitle = stringValue(item, "detailTitle");
    if (detailTitle.isEmpty()) {
        const QString itemTitle = stringValue(item, "title");
        detailTitle = itemTitle.isEmpty()
            ? baseTitle
            : baseTitle + QStringLiteral(": ") + itemTitle;
    }

    QString detailSubtitle = stringValue(item, "detailSubtitle");
    if (detailSubtitle.isEmpty()) {
        const QString itemSubtitle = stringValue(item, "subtitle");
        if (baseSubtitle.isEmpty()) {
            detailSubtitle = itemSubtitle;
        } else if (itemSubtitle.isEmpty()) {
            detailSubtitle = baseSubtitle;
        } else {
            detailSubtitle = baseSubtitle + QStringLiteral("\n") + itemSubtitle;
        }
    }

    const QJsonArray sections = item.contains(QStringLiteral("sections"))
        ? jsonArrayValue(item, "sections")
        : jsonArrayValue(payload, "sections");
    const QJsonArray messages = item.contains(QStringLiteral("messages"))
        ? jsonArrayValue(item, "messages")
        : jsonArrayValue(payload, "messages");

    return GenericSelection {
        hasSelection,
        detailTitle,
        detailSubtitle,
        stringValue(payload, "messagesTitle", QStringLiteral("Activity")),
        sections,
        messages
    };
}

bool usesChatPresentation(const QJsonObject &payload) {
    return stringValue(payload, "presentation", QStringLiteral("standard")) == QStringLiteral("chat");
}

QString elidedChatSidebarText(const QString &text, const QJsonObject &style) {
    QLabel probe;
    const int maximumWidth = intValue(style, "chatSidebarTitleMaxWidth", 180);
    return QFontMetrics(probe.font()).elidedText(text, Qt::ElideRight, maximumWidth);
}

QString promptAccessoryText(const QString &systemImage) {
    return systemImage.contains(QStringLiteral("questionmark")) ? QStringLiteral("?") : QStringLiteral("i");
}

QIcon symbolicIcon(const QString &kind) {
    QPixmap pixmap(48, 48);
    pixmap.fill(Qt::transparent);

    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const QColor ink(QStringLiteral("#52575D"));
    QPen pen(ink, 3.2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);

    if (kind == QStringLiteral("chevronDown")) {
        painter.drawLine(QPointF(15, 20), QPointF(24, 29));
        painter.drawLine(QPointF(24, 29), QPointF(33, 20));
    } else if (kind == QStringLiteral("ellipsis")) {
        painter.setPen(Qt::NoPen);
        painter.setBrush(ink);
        painter.drawEllipse(QPointF(16, 24), 2.8, 2.8);
        painter.drawEllipse(QPointF(24, 24), 2.8, 2.8);
        painter.drawEllipse(QPointF(32, 24), 2.8, 2.8);
    } else if (kind == QStringLiteral("compose")) {
        painter.drawRoundedRect(QRectF(10, 13, 25, 25), 2.4, 2.4);
        painter.drawLine(QPointF(23, 31), QPointF(37, 17));
        painter.drawLine(QPointF(34, 14), QPointF(40, 20));
    } else if (kind == QStringLiteral("waveform")) {
        painter.setPen(QPen(ink, 2.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter.drawLine(QPointF(13, 21), QPointF(13, 27));
        painter.drawLine(QPointF(18.5, 17), QPointF(18.5, 31));
        painter.drawLine(QPointF(24, 12), QPointF(24, 36));
        painter.drawLine(QPointF(29.5, 17), QPointF(29.5, 31));
        painter.drawLine(QPointF(35, 21), QPointF(35, 27));
    } else if (kind == QStringLiteral("keyboard")) {
        painter.drawRoundedRect(QRectF(8, 15, 32, 21), 3.5, 3.5);
        painter.setPen(QPen(ink, 2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        for (int x = 14; x <= 32; x += 6) {
            painter.drawPoint(QPointF(x, 22));
            painter.drawPoint(QPointF(x, 28));
        }
        painter.drawLine(QPointF(17, 32), QPointF(31, 32));
    } else if (kind == QStringLiteral("gear")) {
        painter.drawEllipse(QPointF(24, 24), 7.5, 7.5);
        painter.drawEllipse(QPointF(24, 24), 2.8, 2.8);
        painter.drawLine(QPointF(24, 10), QPointF(24, 14));
        painter.drawLine(QPointF(24, 34), QPointF(24, 38));
        painter.drawLine(QPointF(10, 24), QPointF(14, 24));
        painter.drawLine(QPointF(34, 24), QPointF(38, 24));
        painter.drawLine(QPointF(14.5, 14.5), QPointF(17.5, 17.5));
        painter.drawLine(QPointF(30.5, 30.5), QPointF(33.5, 33.5));
        painter.drawLine(QPointF(33.5, 14.5), QPointF(30.5, 17.5));
        painter.drawLine(QPointF(17.5, 30.5), QPointF(14.5, 33.5));
    } else if (kind == QStringLiteral("question") || kind == QStringLiteral("info")) {
        painter.drawEllipse(QPointF(24, 24), 12, 12);
        QFont font = painter.font();
        font.setPixelSize(22);
        font.setWeight(QFont::DemiBold);
        painter.setFont(font);
        painter.drawText(
            QRectF(12, 10, 24, 30),
            Qt::AlignCenter,
            kind == QStringLiteral("question") ? QStringLiteral("?") : QStringLiteral("i")
        );
    } else if (kind == QStringLiteral("text")) {
        QFont font = painter.font();
        font.setPixelSize(17);
        font.setWeight(QFont::Medium);
        painter.setFont(font);
        painter.drawText(QRectF(4, 11, 40, 26), Qt::AlignCenter, QStringLiteral("Abc"));
    } else {
        painter.drawEllipse(QPointF(24, 24), 12, 12);
        QFont font = painter.font();
        font.setPixelSize(22);
        font.setWeight(QFont::DemiBold);
        painter.setFont(font);
        painter.drawText(QRectF(12, 10, 24, 30), Qt::AlignCenter, QStringLiteral("i"));
    }

    return QIcon(pixmap);
}

QIcon systemImageIcon(const QString &systemImage) {
    const QString normalized = systemImage.trimmed().toLower();
    if (normalized.contains(QStringLiteral("textformat"))
        || normalized.contains(QStringLiteral("character.cursor.ibeam"))
        || normalized.contains(QStringLiteral("ibeam"))) {
        return symbolicIcon(QStringLiteral("text"));
    }
    if (normalized.contains(QStringLiteral("keyboard")) || normalized == QStringLiteral("space")) {
        return symbolicIcon(QStringLiteral("keyboard"));
    }
    if (normalized.contains(QStringLiteral("gearshape"))
        || normalized == QStringLiteral("gear")
        || normalized.contains(QStringLiteral("gear."))) {
        return symbolicIcon(QStringLiteral("gear"));
    }
    if (normalized.contains(QStringLiteral("questionmark"))) {
        return symbolicIcon(QStringLiteral("question"));
    }
    if (normalized.contains(QStringLiteral("lightbulb"))) {
        return symbolicIcon(QStringLiteral("info"));
    }
    if (normalized.contains(QStringLiteral("ellipsis"))) {
        return symbolicIcon(QStringLiteral("ellipsis"));
    }
    if (normalized.contains(QStringLiteral("chevron.down"))) {
        return symbolicIcon(QStringLiteral("chevronDown"));
    }
    if (normalized.contains(QStringLiteral("square.and.pencil"))
        || normalized.contains(QStringLiteral("pencil"))) {
        return symbolicIcon(QStringLiteral("compose"));
    }
    if (normalized.contains(QStringLiteral("waveform"))
        || normalized.contains(QStringLiteral("mic"))
        || normalized.contains(QStringLiteral("audio"))) {
        return symbolicIcon(QStringLiteral("waveform"));
    }
    return symbolicIcon(QStringLiteral("info"));
}

QWidget *promptCardWidget(const QJsonObject &prompt, const QJsonObject &style) {
    const QString titleText = stringValue(prompt, "title", QStringLiteral("Prompt"));
    const QString systemImage = stringValue(prompt, "systemImage");
    const QString accessoryText = promptAccessoryText(systemImage);

    QPushButton *card = new QPushButton();
    card->setObjectName(QStringLiteral("promptCard"));
    card->setProperty("promptTitle", titleText);
    card->setCursor(Qt::PointingHandCursor);
    card->setFlat(true);
    card->setFixedSize(
        intValue(style, "promptCardWidth", 160),
        intValue(style, "promptCardHeight", 128)
    );
    applyAccessibleText(card, titleText, titleText);

    QVBoxLayout *layout = new QVBoxLayout(card);
    const int padding = intValue(style, "promptButtonPadding", 12);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "promptRowSpacing", 12));

    QLabel *title = label(titleText, QStringLiteral("promptTitle"));
    title->setWordWrap(true);
    title->setAlignment(Qt::AlignLeft | Qt::AlignTop);
    title->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
    applyAccessibleText(title, titleText, titleText);
    layout->addWidget(title);
    layout->addStretch(1);

    QLabel *icon = new QLabel();
    icon->setObjectName(QStringLiteral("promptIcon"));
    const int iconSize = intValue(style, "actionButtonIconSize", 16);
    icon->setPixmap(systemImageIcon(systemImage).pixmap(iconSize, iconSize));
    icon->setFixedSize(iconSize, iconSize);
    icon->setAlignment(Qt::AlignRight | Qt::AlignBottom);
    applyAccessibleText(icon, accessoryText, titleText);
    layout->addWidget(icon, 0, Qt::AlignRight | Qt::AlignBottom);
    return card;
}

class GradientWordmark final : public QWidget {
public:
    explicit GradientWordmark(const QString &text, const QJsonObject &style, QWidget *parent = nullptr)
        : QWidget(parent),
          text(text),
          fontSize(intValue(style, "emptyStateWordmarkFontSize", 46)),
          fontWeight(intValue(style, "emptyStateWordmarkFontWeight", 100)) {
        setObjectName(QStringLiteral("emptyWordmark"));
        QFont wordmarkFont = resolvedFont();
        QFontMetrics metrics(wordmarkFont);
        setMinimumSize(metrics.horizontalAdvance(text) + 18, metrics.height() + 10);
        setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    }

protected:
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing, true);

        QFont wordmarkFont = resolvedFont();
        QFontMetrics metrics(wordmarkFont);
        const QRect textRect = metrics.boundingRect(text);
        const qreal x = (width() - metrics.horizontalAdvance(text)) / 2.0;
        const qreal y = (height() + metrics.ascent() - metrics.descent()) / 2.0;

        QPainterPath path;
        path.addText(QPointF(x - textRect.left(), y), wordmarkFont, text);

        QLinearGradient gradient(path.boundingRect().topLeft(), path.boundingRect().topRight());
        gradient.setColorAt(0.0, QColor(QStringLiteral("#6D79E7")));
        gradient.setColorAt(0.52, QColor(QStringLiteral("#B06FD0")));
        gradient.setColorAt(1.0, QColor(QStringLiteral("#DF6D75")));
        painter.fillPath(path, gradient);
    }

private:
    QFont resolvedFont() const {
        QFont font;
        font.setFamilies(QStringList {
            QStringLiteral("SF Pro Display"),
            QStringLiteral("Inter"),
            QStringLiteral("Noto Sans"),
            QStringLiteral("DejaVu Sans"),
            QStringLiteral("sans-serif")
        });
        font.setPixelSize(fontSize);
        if (fontWeight <= 150) {
            font.setWeight(QFont::Thin);
        } else if (fontWeight <= 350) {
            font.setWeight(QFont::Light);
        } else if (fontWeight >= 650) {
            font.setWeight(QFont::Bold);
        } else {
            font.setWeight(QFont::Normal);
        }
        return font;
    }

    QString text;
    int fontSize;
    int fontWeight;
};

QWidget *promptGridWidget(const QJsonArray &prompts, const QJsonObject &style) {
    QWidget *gridHost = new QWidget();
    gridHost->setObjectName(QStringLiteral("promptGridHost"));
    gridHost->setMaximumWidth(intValue(style, "promptGridWidth", 685));
    QGridLayout *grid = new QGridLayout(gridHost);
    grid->setContentsMargins(0, 0, 0, 0);
    const int spacing = intValue(style, "promptGridSpacing", 15);
    grid->setHorizontalSpacing(spacing);
    grid->setVerticalSpacing(spacing);

    const int columns = std::max(1, intValue(style, "promptGridColumns", 4));
    int index = 0;
    for (const QJsonValue &value : prompts) {
        grid->addWidget(promptCardWidget(value.toObject(), style), index / columns, index % columns);
        index += 1;
    }
    return gridHost;
}

QWidget *emptyStateWidget(const QJsonObject &payload, const QJsonObject &style) {
    const QString titleText = stringValue(payload, "emptyStateTitle");
    const QString subtitleText = stringValue(payload, "emptyStateSubtitle");
    const QJsonArray prompts = jsonArrayValue(payload, "prompts");

    QWidget *emptyState = new QWidget();
    emptyState->setObjectName(QStringLiteral("emptyState"));
    emptyState->setMaximumWidth(intValue(style, "emptyStateMaxWidth", 760));
    applyAccessibleText(emptyState, titleText, accessibilitySummary(titleText, subtitleText));
    QVBoxLayout *layout = new QVBoxLayout(emptyState);
    const int padding = intValue(style, "emptyStatePadding", 26);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "emptyStateSpacing", 18));
    layout->setAlignment(Qt::AlignCenter);

    if (!titleText.isEmpty()) {
        GradientWordmark *title = new GradientWordmark(titleText, style);
        applyAccessibleText(title, titleText, titleText);
        layout->addWidget(title, 0, Qt::AlignCenter);
    }

    if (!subtitleText.isEmpty()) {
        QLabel *subtitle = label(subtitleText, QStringLiteral("caption"));
        subtitle->setAlignment(Qt::AlignCenter);
        applyAccessibleText(subtitle, subtitleText, subtitleText);
        layout->addWidget(subtitle);
    }

    if (!prompts.isEmpty()) {
        layout->addWidget(promptGridWidget(prompts, style), 0, Qt::AlignCenter);
    }
    return emptyState;
}

QFrame *noticeWidget(const QJsonObject &payload, const QJsonObject &style) {
    const QString titleText = stringValue(payload, "noticeTitle");
    const QString bodyText = stringValue(payload, "noticeBody");
    const QString actionText = stringValue(payload, "noticeActionTitle");
    if (titleText.isEmpty() && bodyText.isEmpty()) {
        return nullptr;
    }

    QFrame *notice = QuillQtWidgets::frame(QStringLiteral("notice"));
    notice->setMinimumHeight(intValue(style, "noticeMinHeight", 44));
    notice->setMinimumWidth(intValue(style, "noticeMinWidth", 680));
    notice->setMaximumWidth(intValue(style, "noticeMaxWidth", 680));
    applyAccessibleText(notice, titleText, accessibilitySummary(titleText, bodyText));
    QHBoxLayout *layout = new QHBoxLayout(notice);
    const int padding = intValue(style, "promptButtonPadding", 12);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "headerSpacing", 12));

    QLabel *text = label(accessibilitySummary(titleText, bodyText), QStringLiteral("sectionTitle"));
    applyAccessibleText(text, titleText, accessibilitySummary(titleText, bodyText));
    layout->addWidget(text, 1);

    if (!actionText.isEmpty()) {
        QPushButton *action = new QPushButton(actionText);
        action->setObjectName(QStringLiteral("noticeButton"));
        action->setProperty("navigationAction", QStringLiteral("settings"));
        applyAccessibleText(action, actionText, actionText);
        layout->addWidget(action);
    }
    return notice;
}

QWidget *composerWidget(const QJsonObject &payload, const QJsonObject &style) {
    QWidget *composer = new QWidget();
    composer->setMinimumWidth(intValue(style, "composerMinWidth", 620));
    composer->setMaximumWidth(intValue(style, "composerMaxWidth", 800));
    QVBoxLayout *layout = new QVBoxLayout(composer);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(intValue(style, "composerSpacing", 10));

    QFrame *frame = QuillQtWidgets::frame(QStringLiteral("composerFrame"));
    frame->setMinimumHeight(intValue(style, "composerMinHeight", 46));
    frame->setMaximumHeight(intValue(style, "composerMaxHeight", 120));
    QHBoxLayout *frameLayout = new QHBoxLayout(frame);
    const int horizontalPadding = intValue(style, "composerHorizontalPadding", 14);
    frameLayout->setContentsMargins(horizontalPadding, 0, horizontalPadding, 0);
    frameLayout->setSpacing(intValue(style, "composerAccessorySpacing", 8));

    QLineEdit *editor = new QLineEdit();
    editor->setObjectName(QStringLiteral("composerEditor"));
    editor->setPlaceholderText(stringValue(payload, "composerPlaceholder", QStringLiteral("Message")));
    editor->setMinimumHeight(std::max(24, intValue(style, "composerMinHeight", 46) - 4));
    editor->setMaximumHeight(std::max(24, intValue(style, "composerMaxHeight", 120) - 4));
    applyAccessibleText(editor, editor->placeholderText(), editor->placeholderText());
    frameLayout->addWidget(editor, 1);

    QLabel *accessory = new QLabel();
    accessory->setObjectName(QStringLiteral("composerAccessoryIcon"));
    const int accessorySize = intValue(style, "composerAccessoryIconSize", 24);
    accessory->setPixmap(systemImageIcon(QStringLiteral("waveform")).pixmap(accessorySize, accessorySize));
    accessory->setFixedSize(accessorySize, accessorySize);
    accessory->setAlignment(Qt::AlignCenter);
    applyAccessibleText(accessory, QStringLiteral("Voice input"), QStringLiteral("Voice input"));
    frameLayout->addWidget(accessory);

    layout->addWidget(frame);
    return composer;
}

QPushButton *headerIconButton(const QString &systemImage, const QString &title, const QJsonObject &style) {
    QPushButton *button = new QPushButton();
    button->setObjectName(QStringLiteral("headerIconButton"));
    button->setIcon(systemImageIcon(systemImage));
    const int iconSize = intValue(style, "headerIconButtonIconSize", 24);
    button->setIconSize(QSize(
        iconSize,
        iconSize
    ));
    button->setFixedSize(
        intValue(style, "headerIconButtonSize", 34),
        intValue(style, "headerIconButtonSize", 34)
    );
    button->setFlat(true);
    button->setFocusPolicy(Qt::NoFocus);
    applyAccessibleText(button, title, title);
    return button;
}

QWidget *bottomNavigationWidget(const QJsonArray &actions, const QJsonObject &style) {
    QWidget *navigation = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(navigation);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(intValue(style, "sidebarActionSpacing", 8));

    for (const QJsonValue &value : actions) {
        const QJsonObject action = value.toObject();
        const QString titleText = stringValue(action, "title");
        if (titleText.isEmpty()) {
            continue;
        }
        QPushButton *button = new QPushButton(titleText);
        button->setObjectName(QStringLiteral("sidebarNavigationButton"));
        const QString navigationAction = stringValue(action, "id", titleText).trimmed().toLower();
        button->setProperty("navigationAction", navigationAction);
        button->setProperty("navigationTitle", titleText);
        button->setProperty("navigationSubtitle", stringValue(action, "subtitle"));
        button->setIcon(systemImageIcon(stringValue(action, "systemImage")));
        button->setIconSize(QSize(
            intValue(style, "actionButtonIconSize", 16),
            intValue(style, "actionButtonIconSize", 16)
        ));
        button->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
        applyAccessibleText(button, titleText, titleText);
        layout->addWidget(button);
    }
    return navigation;
}

QFrame *trafficDot(const QString &objectName) {
    QFrame *dot = QuillQtWidgets::frame(objectName);
    dot->setFixedSize(10, 10);
    return dot;
}

QFrame *chatSelectionDotWidget(const QJsonObject &style) {
    QFrame *dot = QuillQtWidgets::frame(QStringLiteral("chatSelectionDot"));
    const int dotSize = intValue(style, "conversationSelectionDotSize", 8);
    dot->setFixedSize(dotSize, dotSize);
    dot->setProperty("selected", false);
    return dot;
}

void refreshDynamicStyle(QWidget *widget) {
    if (widget == nullptr || widget->style() == nullptr) {
        return;
    }
    widget->style()->unpolish(widget);
    widget->style()->polish(widget);
    widget->update();
}

QWidget *chatSidebarChromeWidget() {
    QWidget *chrome = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(chrome);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(9);
    layout->addWidget(trafficDot(QStringLiteral("windowDotClose")));
    layout->addWidget(trafficDot(QStringLiteral("windowDotMinimize")));
    layout->addWidget(trafficDot(QStringLiteral("windowDotZoom")));
    layout->addStretch(1);
    QLabel *sidebarIcon = label(QStringLiteral("[]"), QStringLiteral("sidebarChromeIcon"));
    applyAccessibleText(sidebarIcon, QStringLiteral("Sidebar"), QStringLiteral("Sidebar"));
    layout->addWidget(sidebarIcon);
    return chrome;
}

QFrame *itemRowWidget(const QJsonObject &item, const QJsonObject &style, bool chatMode = false) {
    const QString titleText = stringValue(item, "title", QStringLiteral("Untitled"));
    const QString subtitleText = stringValue(item, "subtitle");
    const QString badgeText = stringValue(item, "badge");
    const QString secondaryText = accessibilitySummary(subtitleText, badgeText);
    const QString rowSummary = accessibilitySummary(titleText, secondaryText);
    const int horizontalPadding = intValue(style, "itemRowHorizontalPadding", 2);
    const int verticalPadding = intValue(style, "itemRowVerticalPadding", 4);

    QFrame *row = QuillQtWidgets::frame(QStringLiteral("itemRow"));
    applyAccessibleText(row, titleText, rowSummary);
    QVBoxLayout *layout = nullptr;
    if (chatMode) {
        QHBoxLayout *rowLayout = new QHBoxLayout(row);
        rowLayout->setContentsMargins(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding);
        rowLayout->setSpacing(intValue(style, "conversationSelectionDotSpacing", 8));
        rowLayout->addWidget(chatSelectionDotWidget(style), 0, Qt::AlignTop);

        QWidget *textHost = new QWidget(row);
        layout = new QVBoxLayout(textHost);
        layout->setContentsMargins(0, 0, 0, 0);
        rowLayout->addWidget(textHost, 1);
    } else {
        layout = new QVBoxLayout(row);
        layout->setContentsMargins(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding);
    }
    layout->setSpacing(intValue(style, "itemRowSpacing", 4));

    if (chatMode && !badgeText.isEmpty()) {
        QLabel *date = label(badgeText, QStringLiteral("chatSidebarDate"));
        applyAccessibleText(date, badgeText, badgeText);
        layout->addWidget(date);
    }

    QLabel *title = label(
        chatMode ? elidedChatSidebarText(titleText, style) : titleText,
        chatMode ? QStringLiteral("chatSidebarTitle") : QStringLiteral("sectionTitle")
    );
    applyAccessibleText(title, titleText, rowSummary);
    title->setWordWrap(false);
    layout->addWidget(title);

    if (!chatMode && !subtitleText.isEmpty()) {
        QLabel *subtitle = label(subtitleText, QStringLiteral("itemSubtitle"));
        applyAccessibleText(subtitle, subtitleText, subtitleText);
        layout->addWidget(subtitle);
    }

    if (!chatMode && !badgeText.isEmpty()) {
        QLabel *badge = label(badgeText, QStringLiteral("badge"));
        applyAccessibleText(badge, badgeText, badgeText);
        layout->addWidget(badge);
    }
    return row;
}

void updateChatSelectionDots(QListWidget *list) {
    if (list == nullptr || list->objectName() != QStringLiteral("chatItemList")) {
        return;
    }
    const int selectedRow = list->currentRow();
    for (int rowIndex = 0; rowIndex < list->count(); rowIndex += 1) {
        QWidget *rowWidget = list->itemWidget(list->item(rowIndex));
        if (rowWidget == nullptr) {
            continue;
        }
        const bool isSelected = rowIndex == selectedRow;
        rowWidget->setProperty("chatSelected", isSelected);
        refreshDynamicStyle(rowWidget);
        QFrame *dot = rowWidget->findChild<QFrame *>(QStringLiteral("chatSelectionDot"));
        if (dot != nullptr) {
            dot->setProperty("selected", isSelected);
            refreshDynamicStyle(dot);
        }
    }
}

QListWidget *listWidget(const QJsonArray &items, int selectedIndex, const QJsonObject &style, bool chatMode = false) {
    QListWidget *list = new QListWidget();
    list->setObjectName(chatMode ? QStringLiteral("chatItemList") : QStringLiteral("itemList"));
    applyAccessibleText(list, QStringLiteral("App items"), QStringLiteral("App items"));
    list->setSpacing(intValue(style, "listSpacing", 4));
    list->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    if (chatMode) {
        list->setSelectionMode(QAbstractItemView::SingleSelection);
        list->setFocusPolicy(Qt::NoFocus);
    }

    for (const QJsonValue &value : items) {
        const QJsonObject item = value.toObject();
        QListWidgetItem *listItem = new QListWidgetItem();
        listItem->setSizeHint(QSize(264, intValue(item, "height", 76)));
        list->addItem(listItem);
        list->setItemWidget(listItem, itemRowWidget(item, style, chatMode));
    }

    const int boundedIndex = boundedSelectedIndex(items, selectedIndex, chatMode);
    if (boundedIndex >= 0) {
        list->setCurrentRow(boundedIndex);
    }
    if (chatMode) {
        updateChatSelectionDots(list);
    }
    return list;
}

QWidget *sidebarWidget(const QJsonObject &payload, QListWidget *list, const QJsonObject &style) {
    const bool chatMode = usesChatPresentation(payload);
    const QString sidebarTitle = stringValue(payload, "sidebarTitle", QStringLiteral("QuillUI"));
    const QString sidebarSubtitle = stringValue(payload, "sidebarSubtitle", QStringLiteral("Qt backend"));
    const QString primaryActionTitle = stringValue(payload, "primaryActionTitle", QStringLiteral("New"));
    const QString secondaryActionTitle = stringValue(payload, "secondaryActionTitle", QStringLiteral("Refresh"));
    const QString listTitle = stringValue(payload, "listTitle", QStringLiteral("Items"));
    const QString statusText = stringValue(payload, "status", QStringLiteral("Ready"));
    const QString sidebarSummary = accessibilitySummary(sidebarTitle, sidebarSubtitle);

    QFrame *sidebar = QuillQtWidgets::frame(QStringLiteral("sidebar"));
    const int sidebarWidth = intValue(payload, "sidebarWidth", 320);
    sidebar->setMinimumWidth(sidebarWidth);
    sidebar->setMaximumWidth(sidebarWidth);
    applyAccessibleText(sidebar, sidebarTitle, sidebarSummary);
    const int sidebarPadding = intValue(style, "sidebarPadding", 18);
    const int primaryButtonMinHeight = intValue(style, "primaryButtonMinHeight", 36);
    QVBoxLayout *layout = new QVBoxLayout(sidebar);
    layout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding);
    layout->setSpacing(intValue(style, "sidebarSpacing", 12));

    if (chatMode) {
        layout->addWidget(chatSidebarChromeWidget());
        layout->addSpacing(intValue(style, "emptyStateHeaderSpacing", 8) * 4);
        layout->addWidget(list, 1);

        const QJsonArray bottomNavigation = jsonArrayValue(payload, "bottomNavigation");
        if (!bottomNavigation.isEmpty()) {
            layout->addWidget(bottomNavigationWidget(bottomNavigation, style));
        }
        return sidebar;
    }

    QLabel *title = label(sidebarTitle, QStringLiteral("appTitle"));
    applyAccessibleText(title, sidebarTitle, sidebarSummary);
    layout->addWidget(title);
    QLabel *subtitle = label(sidebarSubtitle, QStringLiteral("subtitle"));
    applyAccessibleText(subtitle, sidebarSubtitle, sidebarSubtitle);
    layout->addWidget(subtitle);

    QHBoxLayout *actions = new QHBoxLayout();
    actions->setContentsMargins(0, 0, 0, 0);
    actions->setSpacing(intValue(style, "sidebarActionSpacing", 8));
    QPushButton *primary = new QPushButton(primaryActionTitle);
    primary->setObjectName(QStringLiteral("primaryButton"));
    primary->setMinimumHeight(primaryButtonMinHeight);
    primary->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    applyAccessibleText(primary, primaryActionTitle, primaryActionTitle);
    QPushButton *secondary = new QPushButton(secondaryActionTitle);
    secondary->setObjectName(QStringLiteral("secondaryButton"));
    secondary->setMinimumHeight(primaryButtonMinHeight);
    secondary->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    applyAccessibleText(secondary, secondaryActionTitle, secondaryActionTitle);
    actions->addWidget(primary);
    actions->addWidget(secondary);
    layout->addLayout(actions);

    QLabel *listLabel = label(listTitle, QStringLiteral("sectionTitle"));
    applyAccessibleText(listLabel, listTitle, listTitle);
    layout->addWidget(listLabel);
    layout->addWidget(list, 1);

    if (chatMode) {
        const QJsonArray bottomNavigation = jsonArrayValue(payload, "bottomNavigation");
        if (!bottomNavigation.isEmpty()) {
            layout->addStretch(1);
            layout->addWidget(bottomNavigationWidget(bottomNavigation, style));
        }
    } else {
        QLabel *status = label(statusText, QStringLiteral("statusText"));
        applyAccessibleText(status, statusText, statusText);
        layout->addWidget(status);
    }
    return sidebar;
}

QFrame *detailCard(const QJsonObject &section, bool active, const QJsonObject &style) {
    const QString titleText = stringValue(section, "title", QStringLiteral("Section"));
    const QString bodyText = stringValue(section, "body");
    const QString cardSummary = accessibilitySummary(titleText, bodyText);

    QFrame *card = QuillQtWidgets::frame(active ? QStringLiteral("activeCard") : QStringLiteral("card"));
    applyAccessibleText(card, titleText, cardSummary);
    QVBoxLayout *layout = new QVBoxLayout(card);
    layout->setContentsMargins(
        intValue(style, "cardPaddingHorizontal", 16),
        intValue(style, "cardPaddingVertical", 14),
        intValue(style, "cardPaddingHorizontal", 16),
        intValue(style, "cardPaddingVertical", 14)
    );
    layout->setSpacing(intValue(style, "cardSpacing", 7));
    QLabel *title = label(titleText, QStringLiteral("headline"));
    applyAccessibleText(title, titleText, cardSummary);
    layout->addWidget(title);
    QLabel *body = label(bodyText, QStringLiteral("bodyText"));
    applyAccessibleText(body, bodyText, bodyText);
    layout->addWidget(body);
    return card;
}

QFrame *messageCard(const QJsonObject &message, const QJsonObject &style) {
    const QString senderText = stringValue(message, "sender", QStringLiteral("System"));
    const QString bodyText = stringValue(message, "body");
    const QString cardSummary = accessibilitySummary(senderText, bodyText);

    QFrame *card = QuillQtWidgets::frame(QStringLiteral("messageCard"));
    applyAccessibleText(card, senderText, cardSummary);
    QVBoxLayout *layout = new QVBoxLayout(card);
    layout->setContentsMargins(
        intValue(style, "messageCardPaddingHorizontal", 14),
        intValue(style, "messageCardPaddingVertical", 10),
        intValue(style, "messageCardPaddingHorizontal", 14),
        intValue(style, "messageCardPaddingVertical", 10)
    );
    layout->setSpacing(intValue(style, "messageCardSpacing", 6));
    QLabel *sender = label(senderText, QStringLiteral("messageMeta"));
    applyAccessibleText(sender, senderText, cardSummary);
    layout->addWidget(sender);
    QLabel *body = label(bodyText, QStringLiteral("messageText"));
    applyAccessibleText(body, bodyText, bodyText);
    layout->addWidget(body);
    return card;
}

QString chatMessageRole(const QJsonObject &message) {
    QString role = stringValue(message, "role");
    if (role.isEmpty()) {
        role = stringValue(message, "sender", QStringLiteral("system"));
    }
    return role.trimmed().toLower();
}

QString chatMessageBody(const QJsonObject &message) {
    const QString content = stringValue(message, "content");
    if (!content.isEmpty()) {
        return content;
    }
    return stringValue(message, "body");
}

QString markdownFenceBody(const QString &bodyText) {
    const int fenceStart = bodyText.indexOf(QStringLiteral("```"));
    if (fenceStart < 0) {
        return QString();
    }
    const int contentStart = bodyText.indexOf(QLatin1Char('\n'), fenceStart);
    if (contentStart < 0) {
        return QString();
    }
    const int fenceEnd = bodyText.indexOf(QStringLiteral("```"), contentStart + 1);
    if (fenceEnd < 0) {
        return bodyText.mid(contentStart + 1).trimmed();
    }
    return bodyText.mid(contentStart + 1, fenceEnd - contentStart - 1).trimmed();
}

QString markdownIntroText(const QString &bodyText) {
    const int fenceStart = bodyText.indexOf(QStringLiteral("```"));
    const QString intro = fenceStart < 0 ? bodyText : bodyText.left(fenceStart);
    QStringList parts;
    for (const QString &line : intro.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QString trimmed = line.trimmed();
        if (!trimmed.startsWith(QLatin1Char('#'))) {
            parts.append(trimmed);
        }
    }
    return parts
        .join(QStringLiteral(" "))
        .replace(QStringLiteral("**"), QString())
        .replace(QStringLiteral("`"), QString())
        .trimmed();
}

QStringList markdownTableRows(const QString &bodyText) {
    QStringList rows;
    const QStringList lines = bodyText.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        const QString trimmed = line.trimmed();
        if (!trimmed.startsWith(QLatin1Char('|')) || !trimmed.endsWith(QLatin1Char('|'))) {
            continue;
        }
        if (trimmed.contains(QStringLiteral("---"))) {
            continue;
        }
        QString row = trimmed;
        row.remove(0, 1);
        row.chop(1);
        rows.append(row.split(QLatin1Char('|')).join(QStringLiteral("    ")).trimmed());
    }
    return rows;
}

QFrame *markdownPanel(const QString &objectName, const QJsonObject &style, int minimumHeight) {
    QFrame *panel = QuillQtWidgets::frame(objectName);
    panel->setMinimumWidth(intValue(style, "markdownPanelMinWidth", 520));
    panel->setMinimumHeight(intValue(style, "markdownPanelMinHeight", minimumHeight));
    return panel;
}

void addRichMarkdownContent(QVBoxLayout *layout, const QString &bodyText, const QJsonObject &style) {
    const QString intro = markdownIntroText(bodyText);
    if (!intro.isEmpty()) {
        QLabel *introLabel = label(intro, QStringLiteral("messageText"));
        introLabel->setWordWrap(true);
        applyAccessibleText(introLabel, intro, intro);
        layout->addWidget(introLabel);
    }

    const QString code = markdownFenceBody(bodyText);
    if (!code.isEmpty()) {
        QFrame *codePanel = markdownPanel(QStringLiteral("markdownCodePanel"), style, 70);
        QVBoxLayout *codeLayout = new QVBoxLayout(codePanel);
        codeLayout->setContentsMargins(12, 10, 12, 10);
        QLabel *codeLabel = label(code, QStringLiteral("markdownCodeText"));
        codeLabel->setWordWrap(false);
        applyAccessibleText(codeLabel, code, code);
        codeLayout->addWidget(codeLabel);
        layout->addWidget(codePanel);
    }

    const QStringList tableRows = markdownTableRows(bodyText);
    if (!tableRows.isEmpty()) {
        QFrame *tablePanel = markdownPanel(QStringLiteral("markdownTablePanel"), style, 86);
        QVBoxLayout *tableLayout = new QVBoxLayout(tablePanel);
        tableLayout->setContentsMargins(12, 8, 12, 8);
        tableLayout->setSpacing(6);
        for (int rowIndex = 0; rowIndex < tableRows.size(); rowIndex += 1) {
            QLabel *row = label(tableRows.at(rowIndex), QStringLiteral("messageText"));
            row->setWordWrap(false);
            applyAccessibleText(row, tableRows.at(rowIndex), tableRows.at(rowIndex));
            tableLayout->addWidget(row);
            if (rowIndex + 1 < tableRows.size()) {
                tableLayout->addWidget(QuillQtWidgets::frame(QStringLiteral("markdownDivider")));
            }
        }
        layout->addWidget(tablePanel);
    }
}

QWidget *chatMessageWidget(const QJsonObject &message, const QJsonObject &style) {
    const QString role = chatMessageRole(message);
    const bool isUser = role == QStringLiteral("user");
    const bool isAssistant = role == QStringLiteral("assistant");
    const QString bodyText = chatMessageBody(message);

    QWidget *host = new QWidget();
    QHBoxLayout *row = new QHBoxLayout(host);
    row->setContentsMargins(0, 0, 0, 0);
    row->setSpacing(0);

    QFrame *bubble = QuillQtWidgets::frame(
        isUser
            ? QStringLiteral("messageUserBubble")
            : (isAssistant ? QStringLiteral("messageAssistantBubble") : QStringLiteral("messageSystemBubble"))
    );
    bubble->setMaximumWidth(intValue(style, "messageBubbleMaxWidth", 520));
    applyAccessibleText(bubble, role, accessibilitySummary(role, bodyText));

    QVBoxLayout *layout = new QVBoxLayout(bubble);
    layout->setContentsMargins(
        intValue(style, "messageCardPaddingHorizontal", 14),
        intValue(style, "messageCardPaddingVertical", 10),
        intValue(style, "messageCardPaddingHorizontal", 14),
        intValue(style, "messageCardPaddingVertical", 10)
    );
    layout->setSpacing(intValue(style, "messageCardSpacing", 6));

    const bool richMarkdown = !isUser
        && (bodyText.contains(QStringLiteral("```")) || bodyText.contains(QStringLiteral("| --- |")));
    if (richMarkdown) {
        bubble->setMaximumWidth(intValue(style, "markdownBubbleMaxWidth", 760));
        addRichMarkdownContent(layout, bodyText, style);
    } else {
        QLabel *body = label(bodyText, isUser ? QStringLiteral("messageTextInverted") : QStringLiteral("messageText"));
        body->setWordWrap(true);
        applyAccessibleText(body, bodyText, bodyText);
        layout->addWidget(body);
    }

    if (isUser) {
        row->addStretch(1);
        row->addWidget(bubble, 0, Qt::AlignRight);
    } else {
        row->addWidget(bubble, 0, Qt::AlignLeft);
        row->addStretch(1);
    }

    return host;
}

void populateChatMessages(QVBoxLayout *layout, const QJsonArray &messages, const QJsonObject &style) {
    for (const QJsonValue &value : messages) {
        layout->addWidget(chatMessageWidget(value.toObject(), style));
    }
}

bool messagesContainRichMarkdown(const QJsonArray &messages) {
    for (const QJsonValue &value : messages) {
        const QString body = chatMessageBody(value.toObject());
        if (body.contains(QStringLiteral("```")) || body.contains(QStringLiteral("| --- |"))) {
            return true;
        }
    }
    return false;
}

void populatePromptConversationContent(
    QVBoxLayout *layout,
    const QString &promptTitle,
    const QJsonObject &style
) {
    clearLayout(layout);
    populateChatMessages(layout, promptConversationMessages(promptTitle), style);
    layout->addStretch(1);
}

void showModelSelectionMenu(QPushButton *button) {
    QMenu menu(button);
    QAction *defaultModel = menu.addAction(QStringLiteral("llava:latest"));
    QAction *referenceModel = menu.addAction(referencePickerModelName());
    QAction *selected = menu.exec(button->mapToGlobal(QPoint(0, button->height())));
    if (selected == defaultModel || selected == referenceModel) {
        selectedChatModelName() = selected->text();
    }
}

QString activeNavigationIdentifier(const QJsonObject &payload) {
    QString navigation = stringValue(payload, "activeNavigation").trimmed().toLower();
    if (!navigation.isEmpty()) {
        return navigation;
    }
    const char *environmentNavigation = std::getenv("QUILLUI_GENERIC_QT_ACTIVE_NAVIGATION");
    if (environmentNavigation == nullptr) {
        return QString();
    }
    return QString::fromUtf8(environmentNavigation).trimmed().toLower();
}

QString automationNavigationClickIdentifier() {
    const char *environmentNavigation = std::getenv("QUILLUI_GENERIC_QT_AUTOMATION_CLICK_NAVIGATION");
    if (environmentNavigation == nullptr) {
        return QString();
    }
    return QString::fromUtf8(environmentNavigation).trimmed().toLower();
}

QString settingsValue(
    const QJsonObject &payload,
    const char *key,
    const QString &fallback = QString()
) {
    const QJsonObject settings = jsonObjectValue(payload, "settings");
    return stringValue(settings, key, fallback);
}

QWidget *settingsFieldWidget(
    const QString &labelText,
    const QString &valueText,
    const QJsonObject &style,
    QLineEdit::EchoMode echoMode = QLineEdit::Normal
) {
    QWidget *fieldHost = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(fieldHost);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(intValue(style, "settingsFieldSpacing", 3));

    QLabel *caption = label(labelText, QStringLiteral("settingsFormLabel"));
    applyAccessibleText(caption, labelText, labelText);
    layout->addWidget(caption);

    QLineEdit *field = new QLineEdit(valueText);
    field->setObjectName(QStringLiteral("settingsField"));
    field->setEchoMode(echoMode);
    field->setMinimumHeight(intValue(style, "settingsFieldMinHeight", 32));
    applyAccessibleText(field, labelText, accessibilitySummary(labelText, valueText));
    layout->addWidget(field);
    return fieldHost;
}

QWidget *settingsOptionRow(
    const QString &labelText,
    const QStringList &options,
    const QJsonObject &style
) {
    QWidget *host = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(host);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(intValue(style, "settingsFieldSpacing", 3));

    QLabel *caption = label(labelText, QStringLiteral("settingsFormLabel"));
    applyAccessibleText(caption, labelText, labelText);
    layout->addWidget(caption);

    QHBoxLayout *buttons = new QHBoxLayout();
    buttons->setContentsMargins(0, 0, 0, 0);
    buttons->setSpacing(intValue(style, "settingsOptionSpacing", 6));
    for (const QString &option : options) {
        QPushButton *button = new QPushButton(option);
        button->setObjectName(QStringLiteral("settingsOptionButton"));
        button->setMinimumHeight(intValue(style, "settingsFieldMinHeight", 32));
        applyAccessibleText(button, option, option);
        buttons->addWidget(button);
    }
    layout->addLayout(buttons);
    return host;
}

void showSettingsDeleteConfirmationDialog(QWidget *parent) {
    QDialog dialog(parent);
    dialog.setObjectName(QStringLiteral("settingsDeleteConfirmationDialog"));
    dialog.setWindowTitle(QStringLiteral("Delete chat history?"));
    dialog.setModal(true);
    dialog.setFixedSize(320, 160);
    dialog.setStyleSheet(QStringLiteral(R"(
        QDialog#settingsDeleteConfirmationDialog { background: #F8F8F8; color: #111111; }
        QLabel#settingsDeleteTitle { color: #111111; font-size: 15px; font-weight: 700; }
        QLabel#settingsDeleteMessage { color: #333333; font-size: 12px; }
        QFrame#settingsDeleteDivider { background: #D2D2D2; border: 0; min-height: 1px; max-height: 1px; }
        QPushButton#settingsDeleteButton { background: #D93A34; color: white; border: 0; border-radius: 6px; padding: 7px 14px; font-weight: 650; }
        QPushButton#settingsCancelDeleteButton { background: white; color: #111111; border: 1px solid #CFCFCF; border-radius: 6px; padding: 7px 14px; font-weight: 550; }
    )"));

    QVBoxLayout *layout = new QVBoxLayout(&dialog);
    layout->setContentsMargins(14, 12, 14, 12);
    layout->setSpacing(7);

    QLabel *title = label(QStringLiteral("Delete chat history?"), QStringLiteral("settingsDeleteTitle"));
    applyAccessibleText(title, title->text(), title->text());
    layout->addWidget(title);

    QLabel *message = label(
        QStringLiteral("This removes all saved conversations and messages from this device."),
        QStringLiteral("settingsDeleteMessage")
    );
    message->setWordWrap(true);
    applyAccessibleText(message, message->text(), message->text());
    layout->addWidget(message);

    QFrame *divider = QuillQtWidgets::frame(QStringLiteral("settingsDeleteDivider"));
    layout->addWidget(divider);

    QHBoxLayout *actions = new QHBoxLayout();
    actions->setContentsMargins(0, 0, 0, 0);
    actions->setSpacing(10);

    QPushButton *deleteButton = new QPushButton(QStringLiteral("Delete"));
    deleteButton->setObjectName(QStringLiteral("settingsDeleteButton"));
    deleteButton->setMinimumWidth(140);
    applyAccessibleText(deleteButton, deleteButton->text(), deleteButton->text());
    actions->addWidget(deleteButton);

    QPushButton *cancelButton = new QPushButton(QStringLiteral("Cancel"));
    cancelButton->setObjectName(QStringLiteral("settingsCancelDeleteButton"));
    cancelButton->setMinimumWidth(140);
    applyAccessibleText(cancelButton, cancelButton->text(), cancelButton->text());
    actions->addWidget(cancelButton);
    layout->addLayout(actions);

    QObject::connect(deleteButton, &QPushButton::clicked, [&]() {
        clearQuillChatConversationStore();
        dialog.accept();
    });
    QObject::connect(cancelButton, &QPushButton::clicked, &dialog, &QDialog::reject);

    dialog.move(0, 0);
    dialog.exec();
}

QFrame *settingsPaneWidget(const QJsonObject &payload, const QJsonObject &style) {
    QFrame *panel = QuillQtWidgets::frame(QStringLiteral("settingsPanel"));
    panel->setMaximumWidth(intValue(style, "settingsPanelMaxWidth", 640));
    panel->setMinimumWidth(intValue(style, "settingsPanelMinWidth", 560));
    applyAccessibleText(panel, QStringLiteral("Settings"), QStringLiteral("Settings"));

    QVBoxLayout *layout = new QVBoxLayout(panel);
    const int padding = intValue(style, "settingsPanelPadding", 20);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "settingsPanelSpacing", 8));

    const QString titleText = settingsValue(payload, "title", QStringLiteral("Settings"));
    const QString subtitleText = settingsValue(
        payload,
        "subtitle",
        QStringLiteral("Refresh models, choose a local model, or clear history from this sidebar.")
    );
    QLabel *title = label(titleText, QStringLiteral("settingsTitle"));
    applyAccessibleText(title, titleText, titleText);
    layout->addWidget(title);

    QLabel *subtitle = label(subtitleText, QStringLiteral("caption"));
    subtitle->setWordWrap(true);
    applyAccessibleText(subtitle, subtitleText, subtitleText);
    layout->addWidget(subtitle);

    QLabel *quillSection = label(settingsValue(payload, "quillSectionTitle", QStringLiteral("Quill")), QStringLiteral("sectionTitle"));
    applyAccessibleText(quillSection, quillSection->text(), quillSection->text());
    layout->addWidget(quillSection);

    layout->addWidget(settingsFieldWidget(
        settingsValue(payload, "endpointLabel", QStringLiteral("Quill API endpoint")),
        settingsValue(payload, "endpoint", QStringLiteral("http://localhost:11434")),
        style
    ));
    layout->addWidget(settingsFieldWidget(
        settingsValue(payload, "systemPromptLabel", QStringLiteral("System prompt")),
        settingsValue(payload, "systemPrompt", QStringLiteral("You are a helpful assistant.")),
        style
    ));
    layout->addWidget(settingsFieldWidget(
        settingsValue(payload, "bearerTokenLabel", QStringLiteral("Bearer Token")),
        settingsValue(payload, "bearerToken"),
        style,
        QLineEdit::Password
    ));
    layout->addWidget(settingsFieldWidget(
        settingsValue(payload, "pingIntervalLabel", QStringLiteral("Ping Interval (seconds)")),
        settingsValue(payload, "pingInterval", QStringLiteral("30")),
        style
    ));

    QLabel *appSection = label(settingsValue(payload, "appSectionTitle", QStringLiteral("APP")), QStringLiteral("sectionTitle"));
    applyAccessibleText(appSection, appSection->text(), appSection->text());
    layout->addWidget(appSection);
    layout->addWidget(settingsOptionRow(
        settingsValue(payload, "appearanceLabel", QStringLiteral("Appearance")),
        QStringList {
            settingsValue(payload, "appearanceSystemOption", QStringLiteral("System")),
            settingsValue(payload, "appearanceLightOption", QStringLiteral("Light")),
            settingsValue(payload, "appearanceDarkOption", QStringLiteral("Dark"))
        },
        style
    ));
    layout->addWidget(settingsFieldWidget(
        settingsValue(payload, "initialsLabel", QStringLiteral("Initials")),
        settingsValue(payload, "userInitials", QStringLiteral("Q")),
        style
    ));

    QPushButton *refresh = new QPushButton(settingsValue(payload, "refreshModelsTitle", QStringLiteral("Refresh models")));
    refresh->setObjectName(QStringLiteral("settingsPrimaryButton"));
    refresh->setMinimumHeight(intValue(style, "settingsFieldMinHeight", 32));
    applyAccessibleText(refresh, refresh->text(), refresh->text());
    layout->addWidget(refresh);

    layout->addSpacing(intValue(style, "settingsPanelSpacing", 8));
    QPushButton *clearHistory = new QPushButton(settingsValue(payload, "clearHistoryTitle", QStringLiteral("Clear all conversations")));
    clearHistory->setObjectName(QStringLiteral("settingsDangerButton"));
    clearHistory->setMinimumHeight(intValue(style, "settingsFieldMinHeight", 32));
    applyAccessibleText(clearHistory, clearHistory->text(), clearHistory->text());
    QObject::connect(clearHistory, &QPushButton::clicked, [clearHistory]() {
        showSettingsDeleteConfirmationDialog(clearHistory->window());
    });
    layout->addWidget(clearHistory);
    return panel;
}

QWidget *completionRowWidget(
    const QString &shortcut,
    const QString &name,
    const QString &instruction,
    const QJsonObject &style
) {
    QWidget *row = new QWidget();
    applyAccessibleText(row, name, accessibilitySummary(shortcut, instruction));

    QHBoxLayout *layout = new QHBoxLayout(row);
    layout->setContentsMargins(10, 7, 10, 7);
    layout->setSpacing(intValue(style, "settingsPanelSpacing", 8));

    QLabel *badge = label(shortcut, QStringLiteral("completionShortcutBadge"));
    badge->setAlignment(Qt::AlignCenter);
    badge->setFixedWidth(28);
    applyAccessibleText(badge, shortcut, shortcut);
    layout->addWidget(badge, 0, Qt::AlignVCenter);

    QLabel *title = label(name, QStringLiteral("completionName"));
    title->setMinimumWidth(116);
    title->setWordWrap(false);
    applyAccessibleText(title, name, name);
    layout->addWidget(title, 0, Qt::AlignVCenter);

    QLabel *body = label(instruction, QStringLiteral("completionInstruction"));
    body->setWordWrap(false);
    applyAccessibleText(body, instruction, instruction);
    layout->addWidget(body, 1, Qt::AlignVCenter);

    QPushButton *edit = new QPushButton(QStringLiteral("Edit"));
    edit->setObjectName(QStringLiteral("completionActionButton"));
    edit->setMinimumWidth(48);
    applyAccessibleText(edit, QStringLiteral("Edit completion"), name);
    layout->addWidget(edit, 0, Qt::AlignVCenter);

    QPushButton *remove = new QPushButton(QStringLiteral("Delete"));
    remove->setObjectName(QStringLiteral("completionActionButton"));
    remove->setMinimumWidth(60);
    applyAccessibleText(remove, QStringLiteral("Delete completion"), name);
    layout->addWidget(remove, 0, Qt::AlignVCenter);
    return row;
}

QFrame *completionDividerWidget() {
    QFrame *divider = QuillQtWidgets::frame(QStringLiteral("completionDivider"));
    divider->setFixedHeight(1);
    return divider;
}

QList<QStringList> &completionRows() {
    static QList<QStringList> rows {
        { QStringLiteral("F"), QStringLiteral("Fix Grammar"), QStringLiteral("Fix grammar for the text below") },
        { QStringLiteral("S"), QStringLiteral("Summarize"), QStringLiteral("Summarize the following text, focusing strictly on the key facts and core action items") },
        { QStringLiteral("W"), QStringLiteral("Write More"), QStringLiteral("Elaborate on the following content, providing additional insights, examples, and context") },
        { QStringLiteral("D"), QStringLiteral("Politely Decline"), QStringLiteral("Write a response politely declining the offer below") }
    };
    return rows;
}

void showCompletionsPanel(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style
);

void showCompletionUpsertSheet(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style,
    int rowIndex
);

QWidget *completionRowWidget(
    const QString &shortcut,
    const QString &name,
    const QString &instruction,
    const QJsonObject &style,
    QVBoxLayout *hostLayout,
    const QJsonObject &payload,
    int rowIndex
) {
    QWidget *row = completionRowWidget(shortcut, name, instruction, style);
    QList<QPushButton *> buttons = row->findChildren<QPushButton *>();
    if (buttons.size() >= 1) {
        QObject::connect(buttons.at(0), &QPushButton::clicked, [hostLayout, payload, style, rowIndex]() {
            showCompletionUpsertSheet(hostLayout, payload, style, rowIndex);
        });
    }
    if (buttons.size() >= 2) {
        QObject::connect(buttons.at(1), &QPushButton::clicked, [hostLayout, payload, style, rowIndex]() {
            if (rowIndex >= 0 && rowIndex < completionRows().size()) {
                completionRows().removeAt(rowIndex);
            }
            showCompletionsPanel(hostLayout, payload, style);
        });
    }
    return row;
}

QFrame *completionUpsertPaneWidget(
    QVBoxLayout *hostLayout,
    const QJsonObject &payload,
    const QJsonObject &style,
    int rowIndex
) {
    QFrame *panel = QuillQtWidgets::frame(QStringLiteral("settingsPanel"));
    panel->setMinimumWidth(intValue(style, "completionUpsertMinWidth", 640));
    panel->setMaximumWidth(intValue(style, "completionUpsertMaxWidth", 720));
    panel->setMinimumHeight(intValue(style, "completionUpsertMinHeight", 340));
    applyAccessibleText(panel, QStringLiteral("Completion"), QStringLiteral("Completion editor"));

    QVBoxLayout *layout = new QVBoxLayout(panel);
    const int padding = intValue(style, "settingsPanelPadding", 20);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "settingsPanelSpacing", 8));

    QHBoxLayout *header = new QHBoxLayout();
    header->setContentsMargins(0, 0, 0, 0);
    QPushButton *cancel = new QPushButton(QStringLiteral("Cancel"));
    cancel->setObjectName(QStringLiteral("completionLinkButton"));
    applyAccessibleText(cancel, cancel->text(), cancel->text());
    header->addWidget(cancel, 0, Qt::AlignLeft | Qt::AlignVCenter);
    QLabel *title = label(rowIndex >= 0 ? QStringLiteral("Edit Completion") : QStringLiteral("New Completion"), QStringLiteral("completionTitle"));
    title->setAlignment(Qt::AlignCenter);
    applyAccessibleText(title, title->text(), title->text());
    header->addWidget(title, 1);
    QPushButton *save = new QPushButton(QStringLiteral("Save"));
    save->setObjectName(QStringLiteral("completionLinkButton"));
    applyAccessibleText(save, save->text(), save->text());
    header->addWidget(save, 0, Qt::AlignRight | Qt::AlignVCenter);
    layout->addLayout(header);

    const QStringList existing =
        rowIndex >= 0 && rowIndex < completionRows().size()
            ? completionRows().at(rowIndex)
            : QStringList { QStringLiteral("L"), QString(), QString() };

    QLabel *nameLabel = label(QStringLiteral("Name"), QStringLiteral("completionInstruction"));
    layout->addWidget(nameLabel);
    QLineEdit *nameField = new QLineEdit(existing.value(1));
    nameField->setObjectName(QStringLiteral("settingsField"));
    nameField->setMinimumHeight(intValue(style, "settingsFieldMinHeight", 34));
    applyAccessibleText(nameField, QStringLiteral("Completion name"), QStringLiteral("Completion name"));
    layout->addWidget(nameField);

    QLabel *instructionLabel = label(QStringLiteral("Instruction"), QStringLiteral("completionInstruction"));
    layout->addWidget(instructionLabel);
    QLineEdit *instructionField = new QLineEdit(existing.value(2));
    instructionField->setObjectName(QStringLiteral("settingsField"));
    instructionField->setMinimumHeight(intValue(style, "completionInstructionFieldMinHeight", 72));
    applyAccessibleText(instructionField, QStringLiteral("Completion instruction"), QStringLiteral("Completion instruction"));
    layout->addWidget(instructionField);

    QLabel *previewLabel = label(QStringLiteral("Preview"), QStringLiteral("completionInstruction"));
    layout->addWidget(previewLabel);
    QLineEdit *preview = new QLineEdit(QStringLiteral("Prompt preview"));
    preview->setObjectName(QStringLiteral("settingsField"));
    preview->setMinimumHeight(intValue(style, "settingsFieldMinHeight", 34));
    preview->setReadOnly(true);
    applyAccessibleText(preview, QStringLiteral("Completion preview"), QStringLiteral("Completion preview"));
    layout->addWidget(preview);
    layout->addStretch(1);

    QObject::connect(cancel, &QPushButton::clicked, [hostLayout, payload, style]() {
        showCompletionsPanel(hostLayout, payload, style);
    });
    QObject::connect(save, &QPushButton::clicked, [hostLayout, payload, style, rowIndex, nameField, instructionField]() {
        QString name = nameField->text().trimmed();
        QString instruction = instructionField->text().trimmed();
        if (name.isEmpty()) {
            name = rowIndex >= 0 ? QStringLiteral("Linux Edited Completion") : QStringLiteral("Linux Saved Completion");
        }
        if (instruction.isEmpty()) {
            instruction = QStringLiteral("Reply with a concise Linux validation response.");
        }
        const QString shortcut = name.left(1).toUpper();
        QStringList row { shortcut.isEmpty() ? QStringLiteral("L") : shortcut, name, instruction };
        if (rowIndex >= 0 && rowIndex < completionRows().size()) {
            completionRows()[rowIndex] = row;
        } else {
            completionRows().prepend(row);
        }
        showCompletionsPanel(hostLayout, payload, style);
    });
    return panel;
}

QFrame *completionsPaneWidget(
    const QJsonObject &style,
    QVBoxLayout *hostLayout,
    const QJsonObject &payload
) {
    QFrame *panel = QuillQtWidgets::frame(QStringLiteral("settingsPanel"));
    panel->setMaximumWidth(intValue(style, "completionsPanelMaxWidth", 560));
    panel->setMinimumWidth(intValue(style, "completionsPanelMinWidth", 520));
    panel->setMinimumHeight(intValue(style, "completionsPanelMinHeight", 310));
    applyAccessibleText(panel, QStringLiteral("Completions"), QStringLiteral("Completions"));

    QVBoxLayout *layout = new QVBoxLayout(panel);
    const int padding = intValue(style, "settingsPanelPadding", 20);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "settingsPanelSpacing", 8));

    QHBoxLayout *header = new QHBoxLayout();
    header->setContentsMargins(0, 0, 0, 0);
    QLabel *title = label(QStringLiteral("Completions"), QStringLiteral("completionTitle"));
    applyAccessibleText(title, title->text(), title->text());
    header->addWidget(title, 1);
    QPushButton *close = new QPushButton(QStringLiteral("Close"));
    close->setObjectName(QStringLiteral("completionLinkButton"));
    applyAccessibleText(close, QStringLiteral("Close completions"), QStringLiteral("Close completions"));
    header->addWidget(close, 0, Qt::AlignRight | Qt::AlignVCenter);
    layout->addLayout(header);

    QLabel *description = label(
        QStringLiteral("Create your own dynamic prompts usable anywhere on your mac with keyboard shortcuts to speed up common tasks. You can reorder, delete and edit your completions."),
        QStringLiteral("completionInstruction")
    );
    description->setWordWrap(true);
    applyAccessibleText(description, description->text(), description->text());
    layout->addWidget(description);

    QHBoxLayout *listHeader = new QHBoxLayout();
    listHeader->setContentsMargins(0, 0, 0, 0);
    QLabel *keyboard = label(QStringLiteral("Keyboard shortcut"), QStringLiteral("completionInstruction"));
    applyAccessibleText(keyboard, keyboard->text(), keyboard->text());
    listHeader->addWidget(keyboard, 1);
    QPushButton *newCompletion = new QPushButton(QStringLiteral("New Completion"));
    newCompletion->setObjectName(QStringLiteral("completionLinkButton"));
    applyAccessibleText(newCompletion, newCompletion->text(), newCompletion->text());
    QObject::connect(newCompletion, &QPushButton::clicked, [hostLayout, payload, style]() {
        showCompletionUpsertSheet(hostLayout, payload, style, -1);
    });
    listHeader->addWidget(newCompletion, 0, Qt::AlignRight);
    layout->addLayout(listHeader);

    const QList<QStringList> rows = completionRows();
    int rowIndex = 0;
    for (const QStringList &row : rows) {
        layout->addWidget(completionRowWidget(row.value(0), row.value(1), row.value(2), style, hostLayout, payload, rowIndex));
        layout->addWidget(completionDividerWidget());
        rowIndex += 1;
    }
    layout->addStretch(1);
    return panel;
}

QWidget *panelOverlayWidget(
    const QJsonObject &payload,
    const QJsonObject &style,
    QWidget *panel,
    Qt::Alignment panelAlignment
) {
    QWidget *host = new QWidget();
    host->setObjectName(QStringLiteral("panelOverlayHost"));
    applyAccessibleText(host, panel->accessibleName(), panel->accessibleDescription());

    QStackedLayout *stack = new QStackedLayout(host);
    stack->setContentsMargins(0, 0, 0, 0);
    stack->setSpacing(0);
    stack->setStackingMode(QStackedLayout::StackAll);

    QWidget *emptyLayer = new QWidget();
    QVBoxLayout *emptyLayout = new QVBoxLayout(emptyLayer);
    emptyLayout->setContentsMargins(0, 0, 0, 0);
    emptyLayout->setSpacing(0);
    emptyLayout->addStretch(1);
    emptyLayout->addWidget(emptyStateWidget(payload, style), 0, Qt::AlignCenter);
    emptyLayout->addStretch(1);

    QWidget *panelLayer = new QWidget();
    QVBoxLayout *panelLayout = new QVBoxLayout(panelLayer);
    panelLayout->setContentsMargins(0, 0, 0, 0);
    panelLayout->setSpacing(0);
    panelLayout->addStretch(2);
    panelLayout->addWidget(panel, 0, panelAlignment);
    panelLayout->addStretch(1);

    stack->addWidget(emptyLayer);
    stack->addWidget(panelLayer);
    stack->setCurrentWidget(panelLayer);
    return host;
}

QWidget *settingsOverlayWidget(const QJsonObject &payload, const QJsonObject &style) {
    return panelOverlayWidget(payload, style, settingsPaneWidget(payload, style), Qt::AlignCenter);
}

QWidget *completionsOverlayWidget(
    const QJsonObject &payload,
    const QJsonObject &style,
    QVBoxLayout *hostLayout
) {
    return panelOverlayWidget(payload, style, completionsPaneWidget(style, hostLayout, payload), Qt::AlignLeft);
}

QWidget *completionUpsertOverlayWidget(
    const QJsonObject &payload,
    const QJsonObject &style,
    QVBoxLayout *hostLayout,
    int rowIndex
) {
    return panelOverlayWidget(
        payload,
        style,
        completionUpsertPaneWidget(hostLayout, payload, style, rowIndex),
        Qt::AlignCenter
    );
}

void showCompletionsPanel(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style
) {
    clearLayout(layout);
    layout->addWidget(completionsOverlayWidget(payload, style, layout), 1);
}

void showCompletionUpsertSheet(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style,
    int rowIndex
) {
    clearLayout(layout);
    layout->addWidget(completionUpsertOverlayWidget(payload, style, layout, rowIndex), 1);
}

QString defaultNavigationTitle(const QString &navigationAction) {
    if (navigationAction == QStringLiteral("completions")) {
        return QStringLiteral("Completions");
    }
    if (navigationAction == QStringLiteral("shortcuts")) {
        return QStringLiteral("Shortcuts");
    }
    if (navigationAction == QStringLiteral("settings")) {
        return QStringLiteral("Settings");
    }
    return QStringLiteral("Panel");
}

QString defaultNavigationSubtitle(const QString &navigationAction) {
    if (navigationAction == QStringLiteral("completions")) {
        return QStringLiteral("Prompt completions use the shared Enchanted profile.");
    }
    if (navigationAction == QStringLiteral("shortcuts")) {
        return QStringLiteral("Keyboard shortcuts use the shared QuillKit shortcut surface.");
    }
    return QStringLiteral("This panel is rendered by the generic Qt navigation host.");
}

QFrame *utilityPaneWidget(
    const QString &navigationAction,
    const QString &titleText,
    const QString &subtitleText,
    const QJsonObject &style
) {
    QFrame *panel = QuillQtWidgets::frame(QStringLiteral("settingsPanel"));
    panel->setMaximumWidth(intValue(style, "settingsPanelMaxWidth", 640));
    panel->setMinimumWidth(intValue(style, "settingsPanelMinWidth", 560));
    const QString effectiveTitle = titleText.isEmpty() ? defaultNavigationTitle(navigationAction) : titleText;
    const QString effectiveSubtitle = subtitleText.isEmpty() ? defaultNavigationSubtitle(navigationAction) : subtitleText;
    applyAccessibleText(panel, effectiveTitle, accessibilitySummary(effectiveTitle, effectiveSubtitle));

    QVBoxLayout *layout = new QVBoxLayout(panel);
    const int padding = intValue(style, "settingsPanelPadding", 20);
    layout->setContentsMargins(padding, padding, padding, padding);
    layout->setSpacing(intValue(style, "settingsPanelSpacing", 8));

    QLabel *title = label(effectiveTitle, QStringLiteral("settingsTitle"));
    applyAccessibleText(title, effectiveTitle, effectiveTitle);
    layout->addWidget(title);

    QLabel *subtitle = label(effectiveSubtitle, QStringLiteral("caption"));
    subtitle->setWordWrap(true);
    applyAccessibleText(subtitle, effectiveSubtitle, effectiveSubtitle);
    layout->addWidget(subtitle);

    QLabel *body = label(
        navigationAction == QStringLiteral("shortcuts")
            ? QStringLiteral("No shortcuts yet.")
            : QStringLiteral("No completions yet."),
        QStringLiteral("bodyText")
    );
    body->setWordWrap(true);
    applyAccessibleText(body, body->text(), body->text());
    layout->addWidget(body);
    return panel;
}

void populateSettingsContent(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style
) {
    clearLayout(layout);
    layout->addWidget(settingsOverlayWidget(payload, style), 1);
}

void populateUtilityContent(
    QVBoxLayout *layout,
    const QString &navigationAction,
    const QString &titleText,
    const QString &subtitleText,
    const QJsonObject &style
) {
    clearLayout(layout);
    layout->addStretch(1);
    layout->addWidget(utilityPaneWidget(navigationAction, titleText, subtitleText, style), 0, Qt::AlignCenter);
    layout->addStretch(1);
}

void populateNavigationContent(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style,
    const QString &navigationAction,
    const QString &titleText = QString(),
    const QString &subtitleText = QString()
) {
    if (navigationAction == QStringLiteral("settings")) {
        populateSettingsContent(layout, payload, style);
        return;
    }
    if (navigationAction == QStringLiteral("completions")) {
        showCompletionsPanel(layout, payload, style);
        return;
    }
    if (!navigationAction.isEmpty()) {
        populateUtilityContent(layout, navigationAction, titleText, subtitleText, style);
    }
}

void populateDetailContent(
    QVBoxLayout *layout,
    const GenericSelection &selection,
    const QJsonObject &style,
    bool chatMode = false
) {
    clearLayout(layout);

    if (chatMode && !selection.messages.isEmpty()) {
        if (!messagesContainRichMarkdown(selection.messages)) {
            layout->addStretch(1);
        }
        populateChatMessages(layout, selection.messages, style);
        if (messagesContainRichMarkdown(selection.messages)) {
            layout->addStretch(1);
        }
        return;
    }

    int sectionIndex = 0;
    for (const QJsonValue &value : selection.sections) {
        layout->addWidget(detailCard(value.toObject(), sectionIndex == 0, style));
        sectionIndex += 1;
    }

    if (!selection.messages.isEmpty()) {
        QLabel *messagesTitle = label(selection.messagesTitle, QStringLiteral("sectionTitle"));
        applyAccessibleText(messagesTitle, selection.messagesTitle, selection.messagesTitle);
        layout->addWidget(messagesTitle);
        for (const QJsonValue &value : selection.messages) {
            layout->addWidget(messageCard(value.toObject(), style));
        }
    }

    layout->addStretch(1);
}

void populateEmptyStateContent(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style
);

void scrollContentToBottom(QScrollArea *scrollArea) {
    if (scrollArea == nullptr) {
        return;
    }
    QTimer::singleShot(0, scrollArea, [scrollArea]() {
        if (QScrollBar *scrollBar = scrollArea->verticalScrollBar()) {
            scrollBar->setValue(scrollBar->maximum());
        }
    });
}

void applySelection(
    GenericDetailPane &detailPane,
    const GenericSelection &selection,
    const QJsonObject &payload,
    const QJsonObject &style,
    bool chatMode
) {
    const QString detailSummary = accessibilitySummary(selection.detailTitle, selection.detailSubtitle);
    if (!detailPane.preservesHeaderTitle) {
        detailPane.titleLabel->setText(selection.detailTitle);
    }
    detailPane.subtitleLabel->setText(selection.detailSubtitle);
    applyAccessibleText(detailPane.view, selection.detailTitle, detailSummary);
    if (!detailPane.preservesHeaderTitle) {
        applyAccessibleText(detailPane.titleLabel, selection.detailTitle, detailSummary);
    }
    applyAccessibleText(detailPane.subtitleLabel, selection.detailSubtitle, selection.detailSubtitle);
    const QString activeNavigation = activeNavigationIdentifier(payload);
    if (chatMode && !activeNavigation.isEmpty()) {
        populateNavigationContent(detailPane.contentLayout, payload, style, activeNavigation);
    } else if (chatMode && !selection.hasSelection) {
        populateEmptyStateContent(detailPane.contentLayout, payload, style);
    } else {
        populateDetailContent(detailPane.contentLayout, selection, style, chatMode);
        if (chatMode && !selection.messages.isEmpty()) {
            scrollContentToBottom(detailPane.contentScrollArea);
        }
    }
}

void populateEmptyStateContent(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style
) {
    clearLayout(layout);
    layout->addStretch(1);
    layout->addWidget(emptyStateWidget(payload, style), 0, Qt::AlignCenter);
    layout->addStretch(1);
}

GenericDetailPane chatDetailWidget(
    const QJsonObject &payload,
    const QJsonArray &items,
    int selectedIndex,
    const QJsonObject &style
) {
    QWidget *detail = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(detail);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    const GenericSelection selection = selectionForRow(payload, items, selectedIndex);
    const QString headerTitle = stringValue(payload, "windowTitle", selection.detailTitle);
    const QString detailSummary = accessibilitySummary(headerTitle, selection.detailSubtitle);
    applyAccessibleText(detail, headerTitle, detailSummary);

    QFrame *header = QuillQtWidgets::frame(QStringLiteral("detailHeader"));
    header->setMinimumHeight(intValue(style, "headerHeight", 76));
    QHBoxLayout *headerLayout = new QHBoxLayout(header);
    const int headerPadding = intValue(style, "headerPadding", 18);
    headerLayout->setContentsMargins(headerPadding, 0, headerPadding, 0);
    headerLayout->setSpacing(intValue(style, "headerSpacing", 12));
    QLabel *title = label(headerTitle, QStringLiteral("chatHeaderTitle"));
    title->setWordWrap(false);
    applyAccessibleText(title, headerTitle, detailSummary);
    headerLayout->addWidget(title, 1);
    QPushButton *conversationMenuButton = headerIconButton(
        QStringLiteral("chevron.down"),
        QStringLiteral("Conversation menu"),
        style
    );
    conversationMenuButton->setProperty("chatHeaderAction", QStringLiteral("modelMenu"));
    headerLayout->addWidget(conversationMenuButton);
    QPushButton *moreOptionsButton = headerIconButton(
        QStringLiteral("ellipsis"),
        QStringLiteral("More options"),
        style
    );
    moreOptionsButton->setProperty("chatHeaderAction", QStringLiteral("copyMenu"));
    headerLayout->addWidget(moreOptionsButton);
    QPushButton *moreOptionsMenuButton = headerIconButton(
        QStringLiteral("chevron.down"),
        QStringLiteral("More options menu"),
        style
    );
    moreOptionsMenuButton->setProperty("chatHeaderAction", QStringLiteral("copyMenu"));
    headerLayout->addWidget(moreOptionsMenuButton);
    QPushButton *newChatButton = headerIconButton(
        QStringLiteral("square.and.pencil"),
        QStringLiteral("New chat"),
        style
    );
    newChatButton->setProperty("chatHeaderAction", QStringLiteral("newChat"));
    headerLayout->addWidget(newChatButton);
    layout->addWidget(header);

    QWidget *body = new QWidget();
    body->setObjectName(QStringLiteral("detailBody"));
    QVBoxLayout *bodyLayout = new QVBoxLayout(body);
    const int contentPadding = intValue(style, "contentPadding", 22);
    bodyLayout->setContentsMargins(contentPadding, contentPadding, contentPadding, contentPadding);
    bodyLayout->setSpacing(intValue(style, "messageSpacing", 14));

    QWidget *conversationHost = new QWidget();
    conversationHost->setObjectName(QStringLiteral("conversationHost"));
    QVBoxLayout *conversationLayout = new QVBoxLayout(conversationHost);
    conversationLayout->setContentsMargins(0, 0, 0, 0);
    conversationLayout->setSpacing(intValue(style, "detailContentSpacing", 14));
    const QString activeNavigation = activeNavigationIdentifier(payload);
    if (!activeNavigation.isEmpty()) {
        populateNavigationContent(conversationLayout, payload, style, activeNavigation);
    } else if (selectedIndex >= 0) {
        populateDetailContent(conversationLayout, selection, style, true);
    } else {
        populateEmptyStateContent(conversationLayout, payload, style);
    }
    QScrollArea *conversationScroll = new QScrollArea();
    conversationScroll->setObjectName(QStringLiteral("conversationScroll"));
    conversationScroll->setFrameShape(QFrame::NoFrame);
    conversationScroll->setWidgetResizable(true);
    conversationScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    conversationScroll->setWidget(conversationHost);
    bodyLayout->addWidget(conversationScroll, 1);
    if (selectedIndex >= 0 && !selection.messages.isEmpty()) {
        scrollContentToBottom(conversationScroll);
    }

    if (QFrame *notice = noticeWidget(payload, style)) {
        bodyLayout->addWidget(notice, 0, Qt::AlignCenter);
    }

    bodyLayout->addWidget(composerWidget(payload, style), 0, Qt::AlignCenter);
    layout->addWidget(body, 1);

    QLabel *subtitle = label(selection.detailSubtitle, QStringLiteral("caption"));
    subtitle->setParent(detail);
    subtitle->hide();
    return GenericDetailPane { detail, title, subtitle, conversationLayout, conversationScroll, true };
}

GenericDetailPane detailWidget(
    const QJsonObject &payload,
    const QJsonArray &items,
    int selectedIndex,
    const QJsonObject &style
) {
    if (usesChatPresentation(payload)) {
        return chatDetailWidget(payload, items, selectedIndex, style);
    }

    QWidget *detail = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(detail);
    layout->setContentsMargins(
        intValue(style, "detailPaddingHorizontal", 24),
        intValue(style, "detailPaddingVertical", 22),
        intValue(style, "detailPaddingHorizontal", 24),
        intValue(style, "detailPaddingVertical", 22)
    );
    layout->setSpacing(intValue(style, "detailSpacing", 14));

    const GenericSelection selection = selectionForRow(payload, items, selectedIndex);
    const QString detailSummary = accessibilitySummary(selection.detailTitle, selection.detailSubtitle);
    applyAccessibleText(detail, selection.detailTitle, detailSummary);
    QLabel *title = label(selection.detailTitle, QStringLiteral("detailTitle"));
    applyAccessibleText(title, selection.detailTitle, detailSummary);
    QLabel *subtitle = label(selection.detailSubtitle, QStringLiteral("caption"));
    applyAccessibleText(subtitle, selection.detailSubtitle, selection.detailSubtitle);
    layout->addWidget(title);
    layout->addWidget(subtitle);

    QVBoxLayout *contentLayout = new QVBoxLayout();
    contentLayout->setContentsMargins(0, 0, 0, 0);
    contentLayout->setSpacing(intValue(style, "detailContentSpacing", 14));
    layout->addLayout(contentLayout, 1);
    populateDetailContent(contentLayout, selection, style);

    return GenericDetailPane { detail, title, subtitle, contentLayout, nullptr, false };
}

QWidget *scrollWrapped(QWidget *child) {
    QScrollArea *scroll = new QScrollArea();
    applyAccessibleText(scroll, child->accessibleName(), child->accessibleDescription());
    scroll->setWidgetResizable(true);
    scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    scroll->setWidget(child);
    return scroll;
}

} // namespace

extern "C" int quill_generic_qt_run_app_json(int argc, char **argv, const char *payload_json) {
    QJsonObject payload;
    int payloadExitCode = 64;
    const QByteArray executableName =
        QuillQtWidgets::executableNameBytes(argc, argv, "quill-generic-qt");
    if (!QuillQtWidgets::parseJsonObjectPayload(
        payload_json,
        executableName.constData(),
        64,
        64,
        &payload,
        &payloadExitCode
    )) {
        return payloadExitCode;
    }

    QApplication app(argc, argv);

    QWidget root;
    root.setObjectName(QStringLiteral("genericRoot"));
    const QString windowTitle = stringValue(payload, "windowTitle", QStringLiteral("QuillUI Qt"));
    root.setWindowTitle(windowTitle);
    applyAccessibleText(&root, windowTitle, windowTitle);
    const QJsonObject style = jsonObjectValue(payload, "style");
    root.setStyleSheet(genericStyleSheet(style));
    const QSize minimumSize = QuillQtWidgets::minimumWindowSize(payload, 900, 620);
    root.setMinimumSize(minimumSize);
    root.resize(QuillQtWidgets::defaultWindowSize(payload, minimumSize));

    QHBoxLayout *rootLayout = new QHBoxLayout(&root);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    const QJsonArray items = jsonArrayValue(payload, "items");
    const int rawSelectedIndex = intValue(payload, "selectedIndex", 0);
    const bool chatMode = usesChatPresentation(payload);
    const int selectedIndex = boundedSelectedIndex(items, rawSelectedIndex, chatMode);
    QListWidget *itemList = listWidget(items, selectedIndex, style, chatMode);
    GenericDetailPane detailPane = detailWidget(payload, items, selectedIndex, style);
    QObject::connect(itemList, &QListWidget::currentRowChanged, [&](int row) {
        applySelection(detailPane, selectionForRow(payload, items, row), payload, style, chatMode);
        updateChatSelectionDots(itemList);
    });

    QSplitter *splitter = new QSplitter(Qt::Horizontal);
    splitter->setHandleWidth(1);
    QWidget *sidebar = sidebarWidget(payload, itemList, style);
    splitter->addWidget(sidebar);
    splitter->addWidget(chatMode ? detailPane.view : scrollWrapped(detailPane.view));
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);
    QList<int> splitSizes;
    splitSizes << intValue(payload, "sidebarWidth", 320) << intValue(payload, "detailWidth", 720);
    splitter->setSizes(splitSizes);
    rootLayout->addWidget(splitter);

    auto installPromptHandlers = [&]() {
        for (QPushButton *button : detailPane.view->findChildren<QPushButton *>()) {
            const QString promptTitle = button->property("promptTitle").toString();
            if (promptTitle.isEmpty() || button->property("promptHandlerInstalled").toBool()) {
                continue;
            }
            button->setProperty("promptHandlerInstalled", true);
            QObject::connect(button, &QPushButton::clicked, [&, promptTitle]() {
                const bool blocked = itemList->blockSignals(true);
                itemList->clearSelection();
                itemList->setCurrentRow(-1);
                itemList->blockSignals(blocked);
                updateChatSelectionDots(itemList);
                persistPromptConversation(promptTitle);
                populatePromptConversationContent(detailPane.contentLayout, promptTitle, style);
            });
        }
    };
    auto installComposerHandlers = [&]() {
        for (QLineEdit *editor : detailPane.view->findChildren<QLineEdit *>(QStringLiteral("composerEditor"))) {
            if (editor->property("composerHandlerInstalled").toBool()) {
                continue;
            }
            editor->setProperty("composerHandlerInstalled", true);
            QObject::connect(editor, &QLineEdit::returnPressed, [&, editor]() {
                const QString promptTitle = editor->text().trimmed();
                if (promptTitle.isEmpty()) {
                    return;
                }
                editor->clear();
                const bool blocked = itemList->blockSignals(true);
                itemList->clearSelection();
                itemList->setCurrentRow(-1);
                itemList->blockSignals(blocked);
                updateChatSelectionDots(itemList);
                persistPromptConversation(promptTitle);
                populatePromptConversationContent(detailPane.contentLayout, promptTitle, style);
            });
        }
    };

    for (QPushButton *button : sidebar->findChildren<QPushButton *>()) {
        const QString navigationAction = button->property("navigationAction").toString();
        if (!navigationAction.isEmpty()) {
            QObject::connect(button, &QPushButton::clicked, [&, button, navigationAction]() {
                const bool blocked = itemList->blockSignals(true);
                itemList->setCurrentRow(-1);
                itemList->blockSignals(blocked);
                updateChatSelectionDots(itemList);
                populateNavigationContent(
                    detailPane.contentLayout,
                    payload,
                    style,
                    navigationAction,
                    button->property("navigationTitle").toString(),
                    button->property("navigationSubtitle").toString()
                );
            });
        }
    }

    if (chatMode) {
        for (QPushButton *button : detailPane.view->findChildren<QPushButton *>()) {
            const QString navigationAction = button->property("navigationAction").toString();
            if (!navigationAction.isEmpty()) {
                QObject::connect(button, &QPushButton::clicked, [&, button, navigationAction]() {
                    const bool blocked = itemList->blockSignals(true);
                    itemList->setCurrentRow(-1);
                    itemList->blockSignals(blocked);
                    updateChatSelectionDots(itemList);
                    populateNavigationContent(
                        detailPane.contentLayout,
                        payload,
                        style,
                        navigationAction,
                        button->text(),
                        QString()
                    );
                });
                continue;
            }
            const QString chatHeaderAction = button->property("chatHeaderAction").toString();
            if (chatHeaderAction == QStringLiteral("newChat")) {
                QObject::connect(button, &QPushButton::clicked, [&]() {
                    const bool blocked = itemList->blockSignals(true);
                    itemList->clearSelection();
                    itemList->setCurrentRow(-1);
                    itemList->blockSignals(blocked);
                    updateChatSelectionDots(itemList);
                    applySelection(detailPane, selectionForRow(payload, items, -1), payload, style, chatMode);
                    installPromptHandlers();
                });
            } else if (chatHeaderAction == QStringLiteral("modelMenu")) {
                QObject::connect(button, &QPushButton::clicked, [button]() {
                    showModelSelectionMenu(button);
                });
            } else if (chatHeaderAction == QStringLiteral("copyMenu")) {
                QObject::connect(button, &QPushButton::clicked, [&, button]() {
                    const GenericSelection selection =
                        selectionForRow(payload, items, itemList->currentRow());
                    QMenu menu(button);
                    QAction *copyAction = menu.addAction(QStringLiteral("Copy Chat"));
                    QAction *copyJsonAction = menu.addAction(QStringLiteral("Copy Chat as JSON"));
                    QAction *chosenAction = menu.exec(
                        button->mapToGlobal(QPoint(0, button->height() + 4))
                    );
                    if (chosenAction == copyAction) {
                        writeFileBackedPasteboardText(chatMessagesPlainText(selection.messages));
                    } else if (chosenAction == copyJsonAction) {
                        writeFileBackedPasteboardText(chatMessagesJsonText(selection.messages));
                    }
                });
            }
        }
        installPromptHandlers();
        installComposerHandlers();
    }
    installPromptHandlers();
    installComposerHandlers();

    root.show();
    const QString automatedNavigationClick = automationNavigationClickIdentifier();
    if (!automatedNavigationClick.isEmpty()) {
        QTimer::singleShot(250, &root, [&]() {
            for (QPushButton *button : sidebar->findChildren<QPushButton *>()) {
                if (button->property("navigationAction").toString() == automatedNavigationClick) {
                    button->click();
                    return;
                }
            }
        });
    }
    return app.exec();
}
