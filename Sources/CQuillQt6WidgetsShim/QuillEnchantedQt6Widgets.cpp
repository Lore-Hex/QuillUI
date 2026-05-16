#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QByteArray>
#include <QComboBox>
#include <QFileInfo>
#include <QFrame>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QListWidgetItem>
#include <QObject>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QSize>
#include <QSignalBlocker>
#include <QSplitter>
#include <QString>
#include <QStringList>
#include <QVBoxLayout>
#include <QWidget>
#include <functional>

namespace {

using QuillQtWidgets::clearLayout;
using QuillQtWidgets::label;
using PromptAction = std::function<void(const QString &)>;

QString stringValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonStringValue(object, key);
}

QString stringValue(const QJsonObject &object, const char *key, const QString &fallback) {
    return QuillQtWidgets::jsonStringValue(object, key, fallback);
}

QString styleValue(const QJsonObject &style, const char *key, const char *fallback) {
    return QuillQtWidgets::jsonStyleValue(style, key, fallback);
}

int intValue(const QJsonObject &object, const char *key, int fallback) {
    return QuillQtWidgets::jsonIntValue(object, key, fallback);
}

bool boolValue(const QJsonObject &object, const char *key, bool fallback) {
    return QuillQtWidgets::jsonBoolValue(object, key, fallback);
}

QJsonObject objectValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonObjectValue(object, key);
}

QJsonArray arrayValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonArrayValue(object, key);
}

QString appStyleSheet(const QJsonObject &style) {
    const QString canvas = styleValue(style, "canvasColor", "#F6F7F2");
    const QString ink = styleValue(style, "inkColor", "#172026");
    const QString sidebar = styleValue(style, "sidebarColor", "#EEF1EA");
    const QString header = styleValue(style, "headerColor", "#FBFCF7");
    const QString card = styleValue(style, "cardColor", "#FFFFFF");
    const QString primary = styleValue(style, "primaryColor", "#315B7D");
    const QString system = styleValue(style, "systemColor", "#E8EDF3");
    const QString muted = styleValue(style, "mutedColor", "#6C747C");
    const QString selected = styleValue(style, "selectedMutedColor", "#DDEBFA");
    const QString warning = styleValue(style, "warningColor", "#B86A31");
    const QString success = styleValue(style, "successColor", "#2F8F64");
    const QString dropTarget = styleValue(style, "dropTargetColor", "#E1F0EA");

    QString sheet = QStringLiteral(R"(
        QWidget#enchantedRoot { background: %1; color: %2; font-size: 14px; }
        QFrame#sidebar { background: %3; border-right: 1px solid #D8DDD5; }
        QFrame#chatHeader, QFrame#composer { background: %4; }
        QLabel#appTitle { color: %2; font-size: 26px; font-weight: 700; }
        QLabel#caption, QLabel#fieldLabel, QLabel#statusText, QLabel#messageRole { color: %8; font-size: 12px; }
        QLabel#sectionTitle { color: %2; font-size: 15px; font-weight: 700; }
        QLabel#currentTitle { color: %2; font-size: 20px; font-weight: 650; }
        QLabel#messageText { color: %2; font-size: 14px; }
        QFrame#emptyHistory { background: %5; border: 1px solid #E0E5DD; border-radius: 8px; }
        QFrame#messageAssistant, QFrame#messageSystem { background: %5; border: 1px solid #E0E5DD; border-radius: 8px; }
        QFrame#messageUser { background: %7; border: 1px solid #D4DFE8; border-radius: 8px; }
        QFrame#attachmentChip { background: %5; border: 1px solid #E0E5DD; border-radius: 8px; }
        QPushButton#primaryButton, QPushButton#sendButton { background: %6; color: white; border: 0; border-radius: 8px; padding: 9px 12px; text-align: left; }
        QPushButton#sendButton[loading="true"] { background: %9; }
        QPushButton#sendButton:disabled { background: #AAB5BE; color: #F4F6F7; }
        QPushButton#secondaryButton { background: transparent; color: %2; border: 1px solid #CDD5CA; border-radius: 7px; padding: 7px 10px; text-align: left; }
        QPushButton#secondaryButton:disabled { color: #9CA6AD; border: 1px solid #D8DDD5; }
        QPushButton#promptButton { background: %5; color: %2; border: 1px solid #E0E5DD; border-radius: 8px; padding: 12px; text-align: left; }
    )")
        .arg(canvas, ink, sidebar, header, card, primary, system, muted, warning);

    sheet += QStringLiteral(R"(
        QListWidget#conversationList { background: transparent; border: 0; outline: 0; }
        QListWidget#conversationList::item { border-radius: 8px; margin: 2px 0; padding: 8px; }
        QListWidget#conversationList::item:selected { background: transparent; color: %2; }
        QFrame#conversationRow { background: %3; border-radius: 8px; }
        QFrame#conversationRow[active="true"] { background: %8; }
        QLabel#conversationTitle { color: %2; font-size: 15px; font-weight: 700; }
        QLabel#conversationTitle[active="true"] { color: white; }
        QLabel#conversationPreview { color: %5; font-size: 12px; }
        QLabel#conversationPreview[active="true"] { color: %1; }
        QLineEdit, QComboBox, QPlainTextEdit { background: %3; color: %2; border: 1px solid #CDD5CA; border-radius: 7px; padding: 7px; }
        QFrame#statusDot, QFrame#statusDotWarning { min-width: 9px; max-width: 9px; min-height: 9px; max-height: 9px; border-radius: 4px; }
        QFrame#statusDot { background: %4; }
        QFrame#statusDotWarning { background: %5; }
        QLabel#warningText { color: %5; font-size: 12px; }
        QFrame#dropTarget { background: %6; border: 1px solid #C8DED3; border-radius: 8px; }
        QSplitter::handle { background: #D8DDD5; }
        QScrollArea { background: %7; border: 0; }
    )")
        .arg(selected, ink, card, success, muted, dropTarget, canvas, primary);

    return sheet;
}

void refreshStyle(QWidget *widget) {
    if (widget == nullptr) {
        return;
    }
    widget->style()->unpolish(widget);
    widget->style()->polish(widget);
    widget->update();
}

QFrame *conversationRowWidget(const QJsonObject &conversation) {
    QFrame *row = QuillQtWidgets::frame(QStringLiteral("conversationRow"));
    row->setProperty("active", false);
    QVBoxLayout *layout = new QVBoxLayout(row);
    layout->setContentsMargins(11, 9, 11, 9);
    layout->setSpacing(5);

    QLabel *title = label(
        stringValue(conversation, "title", QStringLiteral("New conversation")),
        QStringLiteral("conversationTitle")
    );
    title->setWordWrap(false);
    title->setProperty("active", false);

    QLabel *preview = label(
        stringValue(conversation, "lastMessage", QStringLiteral("No messages yet")),
        QStringLiteral("conversationPreview")
    );
    preview->setProperty("active", false);

    layout->addWidget(title);
    layout->addWidget(preview);
    return row;
}

void updateConversationSelectionStyles(QListWidget *list) {
    if (list == nullptr) {
        return;
    }

    for (int index = 0; index < list->count(); ++index) {
        QListWidgetItem *item = list->item(index);
        QWidget *widget = item == nullptr ? nullptr : list->itemWidget(item);
        if (widget == nullptr) {
            continue;
        }

        const bool isSelected = item->isSelected();
        widget->setProperty("active", isSelected);
        refreshStyle(widget);
        for (QLabel *child : widget->findChildren<QLabel *>()) {
            child->setProperty("active", isSelected);
            refreshStyle(child);
        }
    }
}

void removeConversationRow(QListWidget *list, int row) {
    if (list == nullptr || row < 0 || row >= list->count()) {
        return;
    }

    QListWidgetItem *item = list->item(row);
    QWidget *rowWidget = item == nullptr ? nullptr : list->itemWidget(item);
    if (rowWidget != nullptr) {
        list->removeItemWidget(item);
        delete rowWidget;
    }
    delete list->takeItem(row);
}

QFrame *emptyHistoryWidget(const QString &title, const QString &subtitle) {
    QFrame *card = QuillQtWidgets::frame(QStringLiteral("emptyHistory"));
    QVBoxLayout *layout = new QVBoxLayout(card);
    layout->setContentsMargins(12, 12, 12, 12);
    layout->setSpacing(8);
    layout->addWidget(label(title, QStringLiteral("sectionTitle")));
    layout->addWidget(label(subtitle, QStringLiteral("caption")));
    return card;
}

QString selectedConversationTitle(
    const QJsonArray &conversations,
    const QString &selectedConversationID,
    const QString &fallback
) {
    for (const QJsonValue &value : conversations) {
        const QJsonObject conversation = value.toObject();
        if (stringValue(conversation, "id") == selectedConversationID) {
            return stringValue(conversation, "title", fallback);
        }
    }
    return fallback;
}

QString modelStatusText(const QString &selectedModel) {
    const QString trimmedModel = selectedModel.trimmed();
    if (trimmedModel.isEmpty()) {
        return QStringLiteral("Choose a local model to begin");
    }

    return QStringLiteral("Using %1").arg(trimmedModel);
}

QJsonArray currentModelList(QComboBox *modelPicker) {
    QJsonArray models;
    if (modelPicker == nullptr) {
        return models;
    }

    for (int index = 0; index < modelPicker->count(); ++index) {
        const QString model = modelPicker->itemText(index).trimmed();
        if (!model.isEmpty()) {
            models.append(model);
        }
    }
    return models;
}

QString messageRoleTitle(const QString &role) {
    if (role == QStringLiteral("user")) {
        return QStringLiteral("You");
    }
    if (role == QStringLiteral("system")) {
        return QStringLiteral("System");
    }

    return QStringLiteral("Enchanted");
}

QString currentConversationID(QListWidget *list, const QString &fallback) {
    QListWidgetItem *item = list->currentItem();
    if (item == nullptr) {
        return fallback;
    }

    const QString selectedID = item->data(Qt::UserRole).toString();
    if (selectedID.isEmpty()) {
        return fallback;
    }
    return selectedID;
}

QJsonArray selectedConversationMessages(
    const QJsonArray &conversations,
    const QString &selectedConversationID,
    const QJsonArray &fallbackMessages
) {
    for (const QJsonValue &value : conversations) {
        const QJsonObject conversation = value.toObject();
        if (
            stringValue(conversation, "id") == selectedConversationID
            && conversation.contains(QStringLiteral("messages"))
        ) {
            return arrayValue(conversation, "messages");
        }
    }
    return fallbackMessages;
}

void populateConversations(
    QListWidget *list,
    const QJsonArray &conversations,
    const QString &selectedConversationID
) {
    list->clear();
    int selectedRow = -1;

    for (const QJsonValue &value : conversations) {
        const QJsonObject conversation = value.toObject();
        QListWidgetItem *item = new QListWidgetItem();
        item->setData(Qt::UserRole, stringValue(conversation, "id"));
        item->setSizeHint(QSize(260, 88));
        list->addItem(item);
        list->setItemWidget(item, conversationRowWidget(conversation));
        if (stringValue(conversation, "id") == selectedConversationID) {
            selectedRow = list->row(item);
        }
    }

    if (selectedRow >= 0) {
        list->setCurrentRow(selectedRow);
    } else if (list->count() > 0) {
        list->setCurrentRow(0);
    }
    updateConversationSelectionStyles(list);
}

QFrame *messageBubble(const QJsonObject &message, const QJsonObject &style) {
    const QString role = stringValue(message, "role", QStringLiteral("assistant"));
    QString objectName = QStringLiteral("messageAssistant");
    if (role == QStringLiteral("user")) {
        objectName = QStringLiteral("messageUser");
    } else if (role == QStringLiteral("system")) {
        objectName = QStringLiteral("messageSystem");
    }

    QFrame *bubble = QuillQtWidgets::frame(objectName);
    bubble->setMaximumWidth(intValue(style, "messageMaxWidth", 680));

    QVBoxLayout *layout = new QVBoxLayout(bubble);
    layout->setContentsMargins(14, 10, 14, 10);
    layout->setSpacing(6);
    layout->addWidget(label(messageRoleTitle(role), QStringLiteral("messageRole")));
    layout->addWidget(label(stringValue(message, "content"), QStringLiteral("messageText")));
    return bubble;
}

void addMessageBubble(QVBoxLayout *messageLayout, const QJsonObject &message, const QJsonObject &style) {
    const bool isUser = stringValue(message, "role") == QStringLiteral("user");
    QHBoxLayout *row = new QHBoxLayout();
    row->setContentsMargins(0, 0, 0, 0);
    if (isUser) {
        row->addStretch(1);
    }
    row->addWidget(messageBubble(message, style));
    if (!isUser) {
        row->addStretch(1);
    }
    messageLayout->addLayout(row);
}

void addPromptCards(
    QVBoxLayout *messageLayout,
    const QJsonArray &prompts,
    const QString &title,
    const QString &subtitle,
    const PromptAction &promptAction
) {
    QWidget *emptyState = new QWidget();
    emptyState->setObjectName(QStringLiteral("promptEmptyState"));
    QVBoxLayout *layout = new QVBoxLayout(emptyState);
    layout->setContentsMargins(26, 26, 26, 26);
    layout->setSpacing(18);
    layout->addWidget(label(title, QStringLiteral("currentTitle")));
    layout->addWidget(label(
        subtitle,
        QStringLiteral("caption")
    ));

    QVBoxLayout *promptList = new QVBoxLayout();
    promptList->setSpacing(10);
    for (const QJsonValue &value : prompts) {
        const QString prompt = value.toString();
        QPushButton *button = new QPushButton(prompt);
        button->setObjectName(QStringLiteral("promptButton"));
        button->setMinimumHeight(48);
        button->setMaximumWidth(620);
        QObject::connect(button, &QPushButton::clicked, [prompt, promptAction]() {
            promptAction(prompt);
        });
        promptList->addWidget(button);
    }

    layout->addLayout(promptList);
    emptyState->setMaximumWidth(680);
    messageLayout->addWidget(emptyState);
    messageLayout->addStretch(1);
}

void renderMessages(
    QVBoxLayout *messageLayout,
    const QJsonArray &messages,
    const QJsonArray &prompts,
    const QJsonObject &style,
    const QString &emptyStateTitle,
    const QString &emptyStateSubtitle,
    const PromptAction &promptAction
) {
    clearLayout(messageLayout);
    if (messages.isEmpty()) {
        addPromptCards(messageLayout, prompts, emptyStateTitle, emptyStateSubtitle, promptAction);
        return;
    }

    for (const QJsonValue &value : messages) {
        addMessageBubble(messageLayout, value.toObject(), style);
    }
}

QLabel *fieldLabel(const QString &text) {
    return label(text, QStringLiteral("fieldLabel"));
}

bool hasTrimmedText(const QLineEdit *field) {
    return field != nullptr && !field->text().trimmed().isEmpty();
}

bool hasTrimmedText(const QPlainTextEdit *editor) {
    return editor != nullptr && !editor->toPlainText().trimmed().isEmpty();
}

QString attachmentDisplayName(const QString &rawPath) {
    const QString trimmedPath = rawPath.trimmed();
    if (trimmedPath.isEmpty()) {
        return QString();
    }

    const QFileInfo fileInfo(trimmedPath);
    const QString fileName = fileInfo.fileName();
    return fileName.isEmpty() ? trimmedPath : fileName;
}

QString attachmentDisplayContent(
    const QString &rawPrompt,
    const QString &pendingAttachmentSummary,
    const QString &defaultPrompt,
    const QString &summaryTitle
) {
    const QString trimmedPrompt = rawPrompt.trimmed();
    if (pendingAttachmentSummary.isEmpty()) {
        return trimmedPrompt;
    }

    const QString prompt = trimmedPrompt.isEmpty() ? defaultPrompt : trimmedPrompt;
    return QStringLiteral("%1\n\n%2\n%3").arg(prompt, summaryTitle, pendingAttachmentSummary);
}

void addSidebarField(QVBoxLayout *layout, const QString &title, QWidget *field) {
    layout->addWidget(fieldLabel(title));
    layout->addWidget(field);
}

QJsonObject actionSnapshot(
    const QJsonObject &action,
    quill_enchanted_qt_action_callback actionCallback,
    quill_enchanted_qt_free_string_callback freeString,
    bool *succeeded
) {
    if (succeeded != nullptr) {
        *succeeded = false;
    }
    if (actionCallback == nullptr) {
        return QJsonObject();
    }

    const QByteArray request = QJsonDocument(action).toJson(QJsonDocument::Compact);
    char *response = actionCallback(request.constData());
    if (response == nullptr) {
        return QJsonObject();
    }

    const QByteArray responseBytes(response);
    if (freeString != nullptr) {
        freeString(response);
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(responseBytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        return QJsonObject();
    }

    if (succeeded != nullptr) {
        *succeeded = true;
    }
    return document.object();
}

} // namespace

extern "C" int quill_enchanted_qt_run_app_json(
    int argc,
    char **argv,
    const char *payload_json,
    quill_enchanted_qt_action_callback actionCallback,
    quill_enchanted_qt_free_string_callback freeString
) {
    QJsonObject payload;
    int payloadExitCode = 65;
    const QByteArray executableName =
        QuillQtWidgets::executableNameBytes(argc, argv, "quill-enchanted-qt");
    if (!QuillQtWidgets::parseJsonObjectPayload(
        payload_json,
        executableName.constData(),
        65,
        65,
        &payload,
        &payloadExitCode
    )) {
        return payloadExitCode;
    }

    QApplication app(argc, argv);
    const QJsonObject style = objectValue(payload, "style");
    const bool isLoading = boolValue(payload, "isLoading", false);
    app.setApplicationName(stringValue(payload, "windowTitle", QStringLiteral("Quill Enchanted")));
    app.setStyleSheet(appStyleSheet(style));

    QWidget window;
    window.setObjectName(QStringLiteral("enchantedRoot"));
    window.setWindowTitle(stringValue(payload, "windowTitle", QStringLiteral("Quill Enchanted")));
    const QSize minimumWindowSize = QuillQtWidgets::minimumWindowSize(payload, 980, 680);
    const QSize defaultWindowSize = QuillQtWidgets::defaultWindowSize(payload, minimumWindowSize);
    window.setMinimumSize(minimumWindowSize);
    window.resize(defaultWindowSize);

    QHBoxLayout *rootLayout = new QHBoxLayout(&window);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    QSplitter *splitter = new QSplitter();
    rootLayout->addWidget(splitter);

    QFrame *sidebar = QuillQtWidgets::frame(QStringLiteral("sidebar"));
    sidebar->setMinimumWidth(intValue(style, "sidebarWidth", 300));
    sidebar->setMaximumWidth(intValue(style, "sidebarWidth", 300));
    QVBoxLayout *sidebarLayout = new QVBoxLayout(sidebar);
    sidebarLayout->setContentsMargins(18, 18, 18, 18);
    sidebarLayout->setSpacing(10);

    sidebarLayout->addWidget(label(
        stringValue(payload, "sidebarTitle", QStringLiteral("Enchanted")),
        QStringLiteral("appTitle")
    ));
    sidebarLayout->addWidget(label(
        stringValue(payload, "sidebarSubtitle", QStringLiteral("QuillUI Linux preview")),
        QStringLiteral("caption")
    ));

    QPushButton *newChatButton = new QPushButton(stringValue(payload, "newChatTitle", QStringLiteral("New chat")));
    newChatButton->setObjectName(QStringLiteral("primaryButton"));
    sidebarLayout->addWidget(newChatButton);

    QLineEdit *endpointField = new QLineEdit(stringValue(payload, "endpoint"));
    addSidebarField(
        sidebarLayout,
        stringValue(payload, "endpointLabel", QStringLiteral("Ollama endpoint")),
        endpointField
    );

    QJsonArray models = arrayValue(payload, "models");
    const QString modelLabel = stringValue(payload, "modelLabel", QStringLiteral("Model"));
    QComboBox *modelPicker = new QComboBox();
    QLabel *noModelsNotice = label(
        stringValue(payload, "noModelsTitle", QStringLiteral("No models detected")),
        QStringLiteral("warningText")
    );
    auto populateModelPicker = [&](const QJsonArray &modelValues, const QString &selectedModelValue) {
        QSignalBlocker blocker(modelPicker);
        modelPicker->clear();
        const QString trimmedSelection = selectedModelValue.trimmed();
        QString firstModel;
        int selectedModelIndex = -1;

        for (const QJsonValue &model : modelValues) {
            const QString modelName = model.toString().trimmed();
            if (modelName.isEmpty()) {
                continue;
            }
            if (firstModel.isEmpty()) {
                firstModel = modelName;
            }
            modelPicker->addItem(modelName);
            if (modelName == trimmedSelection) {
                selectedModelIndex = modelPicker->count() - 1;
            }
        }

        if (selectedModelIndex >= 0) {
            modelPicker->setCurrentIndex(selectedModelIndex);
        } else if (!firstModel.isEmpty()) {
            modelPicker->setCurrentIndex(0);
        }
        const bool hasModels = modelPicker->count() > 0;
        modelPicker->setEnabled(hasModels);
        noModelsNotice->setVisible(!hasModels);
    };
    populateModelPicker(models, stringValue(payload, "selectedModel"));
    addSidebarField(
        sidebarLayout,
        modelLabel,
        modelPicker
    );
    sidebarLayout->addWidget(noModelsNotice);

    QHBoxLayout *statusLayout = new QHBoxLayout();
    statusLayout->setContentsMargins(0, 0, 0, 0);
    statusLayout->setSpacing(8);
    QFrame *statusDot = QuillQtWidgets::frame(
        models.isEmpty() ? QStringLiteral("statusDotWarning") : QStringLiteral("statusDot")
    );
    statusDot->setFixedSize(9, 9);
    statusLayout->addWidget(statusDot);
    QLabel *statusText = label(stringValue(payload, "status"), QStringLiteral("statusText"));
    statusLayout->addWidget(statusText);
    sidebarLayout->addLayout(statusLayout);

    sidebarLayout->addWidget(label(
        stringValue(payload, "conversationsTitle", QStringLiteral("Conversations")),
        QStringLiteral("sectionTitle")
    ));

    QJsonArray conversations = arrayValue(payload, "conversations");
    QString selectedConversationID = stringValue(payload, "selectedConversationID");
    QFrame *emptyHistory = emptyHistoryWidget(
        stringValue(payload, "emptyHistoryTitle", QStringLiteral("No saved chats yet")),
        stringValue(payload, "emptyHistorySubtitle", QStringLiteral("Start a chat and it will be saved locally."))
    );
    emptyHistory->setVisible(conversations.isEmpty());
    sidebarLayout->addWidget(emptyHistory);
    QListWidget *conversationList = new QListWidget();
    conversationList->setObjectName(QStringLiteral("conversationList"));
    populateConversations(
        conversationList,
        conversations,
        selectedConversationID
    );
    conversationList->setVisible(!conversations.isEmpty());
    sidebarLayout->addWidget(conversationList, 1);

    QHBoxLayout *conversationActions = new QHBoxLayout();
    conversationActions->setSpacing(8);
    QPushButton *deleteButton = new QPushButton(stringValue(payload, "deleteChatTitle", QStringLiteral("Delete chat")));
    deleteButton->setObjectName(QStringLiteral("secondaryButton"));
    QPushButton *clearAllButton = new QPushButton(stringValue(payload, "clearAllTitle", QStringLiteral("Clear all")));
    clearAllButton->setObjectName(QStringLiteral("secondaryButton"));
    conversationActions->addWidget(deleteButton);
    conversationActions->addWidget(clearAllButton);
    sidebarLayout->addLayout(conversationActions);

    QFrame *chatPane = QuillQtWidgets::frame(QStringLiteral("chatPane"));
    QVBoxLayout *chatLayout = new QVBoxLayout(chatPane);
    chatLayout->setContentsMargins(0, 0, 0, 0);
    chatLayout->setSpacing(0);

    QFrame *header = QuillQtWidgets::frame(QStringLiteral("chatHeader"));
    QHBoxLayout *headerLayout = new QHBoxLayout(header);
    const int headerPadding = intValue(style, "headerPadding", 18);
    headerLayout->setContentsMargins(headerPadding, headerPadding, headerPadding, headerPadding);
    headerLayout->setSpacing(12);
    QVBoxLayout *titleLayout = new QVBoxLayout();
    titleLayout->setSpacing(4);
    const QString initialConversationID = currentConversationID(conversationList, selectedConversationID);
    QLabel *currentTitle = label(
        selectedConversationTitle(
            conversations,
            initialConversationID,
            QStringLiteral("New conversation")
        ),
        QStringLiteral("currentTitle")
    );
    QLabel *modelStatus = label(
        modelStatusText(stringValue(payload, "selectedModel")),
        QStringLiteral("caption")
    );
    titleLayout->addWidget(currentTitle);
    titleLayout->addWidget(modelStatus);
    headerLayout->addLayout(titleLayout, 1);
    QPushButton *refreshButton = new QPushButton(stringValue(payload, "refreshModelsTitle", QStringLiteral("Refresh models")));
    refreshButton->setObjectName(QStringLiteral("secondaryButton"));
    refreshButton->setEnabled(!isLoading);
    headerLayout->addWidget(refreshButton);
    chatLayout->addWidget(header);

    QScrollArea *scrollArea = new QScrollArea();
    scrollArea->setWidgetResizable(true);
    QWidget *transcript = new QWidget();
    QVBoxLayout *messageLayout = new QVBoxLayout(transcript);
    const int contentPadding = intValue(style, "contentPadding", 22);
    messageLayout->setContentsMargins(contentPadding, contentPadding, contentPadding, contentPadding);
    messageLayout->setSpacing(14);
    scrollArea->setWidget(transcript);
    chatLayout->addWidget(scrollArea, 1);

    QFrame *composer = QuillQtWidgets::frame(QStringLiteral("composer"));
    QVBoxLayout *composerLayout = new QVBoxLayout(composer);
    composerLayout->setContentsMargins(18, 14, 18, 18);
    composerLayout->setSpacing(9);

    QFrame *dropTarget = QuillQtWidgets::frame(QStringLiteral("dropTarget"));
    QHBoxLayout *dropLayout = new QHBoxLayout(dropTarget);
    dropLayout->setContentsMargins(10, 7, 10, 7);
    dropLayout->setSpacing(8);
    QLineEdit *attachmentPath = new QLineEdit();
    attachmentPath->setPlaceholderText(stringValue(
        payload,
        "attachmentPlaceholder",
        QStringLiteral("Image path or drop files here")
    ));
    QPushButton *attachButton = new QPushButton(stringValue(payload, "attachTitle", QStringLiteral("Attach")));
    attachButton->setObjectName(QStringLiteral("secondaryButton"));
    QPushButton *clearAttachmentsButton = new QPushButton(stringValue(payload, "clearAttachmentsTitle", QStringLiteral("Clear")));
    clearAttachmentsButton->setObjectName(QStringLiteral("secondaryButton"));
    dropLayout->addWidget(attachmentPath, 1);
    dropLayout->addWidget(attachButton);
    dropLayout->addWidget(clearAttachmentsButton);
    composerLayout->addWidget(dropTarget);

    QFrame *attachmentTray = QuillQtWidgets::frame(QStringLiteral("attachmentTray"));
    QVBoxLayout *attachmentTrayLayout = new QVBoxLayout(attachmentTray);
    attachmentTrayLayout->setContentsMargins(0, 0, 0, 0);
    attachmentTrayLayout->setSpacing(7);
    attachmentTrayLayout->addWidget(fieldLabel(stringValue(payload, "attachmentsTitle", QStringLiteral("Attachments"))));
    QFrame *attachmentChip = QuillQtWidgets::frame(QStringLiteral("attachmentChip"));
    QHBoxLayout *attachmentChipLayout = new QHBoxLayout(attachmentChip);
    attachmentChipLayout->setContentsMargins(10, 7, 10, 7);
    QLabel *attachmentChipText = label(QString(), QStringLiteral("caption"));
    attachmentChipLayout->addWidget(attachmentChipText);
    attachmentTrayLayout->addWidget(attachmentChip);
    attachmentTray->setVisible(false);
    composerLayout->addWidget(attachmentTray);

    QHBoxLayout *promptRow = new QHBoxLayout();
    promptRow->setSpacing(10);
    QPlainTextEdit *promptEditor = new QPlainTextEdit();
    promptEditor->setPlaceholderText(stringValue(
        payload,
        "composerPlaceholder",
        QStringLiteral("Ask a local model...")
    ));
    promptEditor->setFixedHeight(intValue(style, "composerHeight", 84));
    const QString sendTitle = stringValue(payload, "sendTitle", QStringLiteral("Send"));
    const QString stopTitle = stringValue(payload, "stopTitle", QStringLiteral("Stop"));
    const QString stoppingStatus = stringValue(payload, "stoppingStatus", QStringLiteral("Stopping..."));
    QPushButton *sendButton = new QPushButton();
    sendButton->setObjectName(QStringLiteral("sendButton"));
    sendButton->setProperty("loading", isLoading);
    sendButton->setText(isLoading ? stopTitle : sendTitle);
    sendButton->setMinimumWidth(86);
    promptRow->addWidget(promptEditor, 1);
    promptRow->addWidget(sendButton);
    composerLayout->addLayout(promptRow);
    chatLayout->addWidget(composer);

    QString pendingAttachmentSummary;
    const QString attachmentDefaultPrompt = stringValue(
        payload,
        "attachmentDefaultPrompt",
        QStringLiteral("Describe this image.")
    );
    const QString attachmentSummaryTitle = stringValue(
        payload,
        "attachmentSummaryTitle",
        QStringLiteral("[Attached images]")
    );
    QJsonArray fallbackMessages = arrayValue(payload, "messages");
    const QJsonArray prompts = arrayValue(payload, "prompts");
    const QString emptyStateTitle = stringValue(payload, "emptyStateTitle", QStringLiteral("Ask your local model"));
    const QString emptyStateSubtitle = stringValue(
        payload,
        "emptyStateSubtitle",
        QStringLiteral("This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.")
    );
    bool showingPromptCards = false;
    QStringList pendingAttachmentPaths;
    std::function<bool(const QString &, const QString &, const QString &, const QStringList &)> requestHistoryAction;
    auto renderLocalUserMessage = [&](const QString &rawText) {
        const QString text = rawText.trimmed();
        if (text.isEmpty()) {
            return;
        }

        QJsonObject message;
        message.insert(QStringLiteral("role"), QStringLiteral("user"));
        message.insert(QStringLiteral("content"), text);
        if (showingPromptCards) {
            clearLayout(messageLayout);
            showingPromptCards = false;
        }
        addMessageBubble(messageLayout, message, style);
        promptEditor->clear();
    };
    auto appendUserMessage = [&](const QString &rawText) {
        const QString text = rawText.trimmed();
        if (text.isEmpty()) {
            return;
        }

        if (requestHistoryAction
            && requestHistoryAction(
                QStringLiteral("sendMessage"),
                currentConversationID(conversationList, selectedConversationID),
                text,
                QStringList()
            )) {
            promptEditor->clear();
            return;
        }

        renderLocalUserMessage(text);
    };
    auto appendComposerMessage = [&](const QString &rawPrompt) {
        const QString fallbackContent = attachmentDisplayContent(
            rawPrompt,
            pendingAttachmentSummary,
            attachmentDefaultPrompt,
            attachmentSummaryTitle
        );
        if (fallbackContent.trimmed().isEmpty()) {
            return;
        }

        if (requestHistoryAction
            && requestHistoryAction(
                QStringLiteral("sendMessage"),
                currentConversationID(conversationList, selectedConversationID),
                rawPrompt,
                pendingAttachmentPaths
            )) {
            promptEditor->clear();
            return;
        }

        renderLocalUserMessage(fallbackContent);
    };
    auto updateComposerControlState = [&]() {
        attachButton->setEnabled(hasTrimmedText(attachmentPath));
        clearAttachmentsButton->setEnabled(hasTrimmedText(attachmentPath) || !pendingAttachmentSummary.isEmpty());
        sendButton->setEnabled(isLoading || hasTrimmedText(promptEditor) || !pendingAttachmentSummary.isEmpty());
    };
    auto clearAttachmentState = [&]() {
        attachmentPath->clear();
        pendingAttachmentSummary.clear();
        pendingAttachmentPaths.clear();
        attachmentTray->setVisible(false);
        attachmentChipText->clear();
        updateComposerControlState();
    };
    auto renderMessageSet = [&](const QJsonArray &messages) {
        renderMessages(
            messageLayout,
            messages,
            prompts,
            style,
            emptyStateTitle,
            emptyStateSubtitle,
            appendUserMessage
        );
        showingPromptCards = messages.isEmpty();
    };
    auto updateConversationActionState = [&]() {
        const bool hasConversations = conversationList->count() > 0;
        deleteButton->setEnabled(conversationList->currentItem() != nullptr);
        clearAllButton->setEnabled(hasConversations);
        conversationList->setVisible(hasConversations);
        emptyHistory->setVisible(!hasConversations);
    };
    auto applySnapshot = [&](const QJsonObject &snapshot) {
        payload = snapshot;
        models = arrayValue(payload, "models");
        conversations = arrayValue(payload, "conversations");
        selectedConversationID = stringValue(payload, "selectedConversationID");
        fallbackMessages = arrayValue(payload, "messages");
        const QString endpointText = stringValue(payload, "endpoint");
        if (endpointField->text() != endpointText) {
            QSignalBlocker blocker(endpointField);
            endpointField->setText(endpointText);
        }
        populateModelPicker(models, stringValue(payload, "selectedModel"));
        statusDot->setObjectName(
            modelPicker->count() > 0 ? QStringLiteral("statusDot") : QStringLiteral("statusDotWarning")
        );
        refreshStyle(statusDot);

        populateConversations(
            conversationList,
            conversations,
            selectedConversationID
        );
        const QString selectedID = currentConversationID(conversationList, selectedConversationID);
        currentTitle->setText(selectedConversationTitle(
            conversations,
            selectedID,
            QStringLiteral("New conversation")
        ));
        statusText->setText(stringValue(payload, "status"));
        modelStatus->setText(modelStatusText(
            modelPicker->currentText().trimmed().isEmpty()
                ? stringValue(payload, "selectedModel")
                : modelPicker->currentText()
        ));
        renderMessageSet(selectedConversationMessages(
            conversations,
            selectedID,
            fallbackMessages
        ));
        updateConversationActionState();
    };
    requestHistoryAction = [&](const QString &actionName, const QString &conversationID, const QString &messageText, const QStringList &attachmentPaths) -> bool {
        QJsonObject action;
        action.insert(QStringLiteral("action"), actionName);
        action.insert(QStringLiteral("endpoint"), endpointField->text().trimmed());
        const QString currentModel = modelPicker->currentText().trimmed();
        if (!currentModel.isEmpty()) {
            action.insert(QStringLiteral("selectedModel"), currentModel);
        }
        action.insert(QStringLiteral("models"), currentModelList(modelPicker));
        if (!conversationID.isEmpty()) {
            action.insert(QStringLiteral("conversationID"), conversationID);
        }
        const QString trimmedMessageText = messageText.trimmed();
        if (!trimmedMessageText.isEmpty()) {
            action.insert(QStringLiteral("messageText"), trimmedMessageText);
        }
        QJsonArray encodedAttachmentPaths;
        for (const QString &path : attachmentPaths) {
            const QString trimmedPath = path.trimmed();
            if (!trimmedPath.isEmpty()) {
                encodedAttachmentPaths.append(trimmedPath);
            }
        }
        if (!encodedAttachmentPaths.isEmpty()) {
            action.insert(QStringLiteral("attachmentPaths"), encodedAttachmentPaths);
        }

        bool succeeded = false;
        const QJsonObject snapshot = actionSnapshot(action, actionCallback, freeString, &succeeded);
        if (!succeeded) {
            return false;
        }

        applySnapshot(snapshot);
        return true;
    };

    const QJsonArray initialMessages = selectedConversationMessages(
        conversations,
        initialConversationID,
        fallbackMessages
    );
    renderMessageSet(initialMessages);

    splitter->addWidget(sidebar);
    splitter->addWidget(chatPane);
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);

    QObject::connect(newChatButton, &QPushButton::clicked, [&]() {
        if (requestHistoryAction(QStringLiteral("newConversation"), QString(), QString(), QStringList())) {
            return;
        }

        conversationList->clearSelection();
        conversationList->setCurrentRow(-1);
        updateConversationSelectionStyles(conversationList);
        currentTitle->setText(QStringLiteral("New conversation"));
        renderMessageSet(QJsonArray());
        updateConversationActionState();
    });
    QObject::connect(deleteButton, &QPushButton::clicked, [&]() {
        const int deletedRow = conversationList->currentRow();
        if (deletedRow < 0) {
            return;
        }

        const QString deletedConversationID = currentConversationID(conversationList, selectedConversationID);
        if (requestHistoryAction(QStringLiteral("deleteConversation"), deletedConversationID, QString(), QStringList())) {
            return;
        }

        removeConversationRow(conversationList, deletedRow);
        if (conversationList->count() > 0) {
            const int nextRow = deletedRow >= conversationList->count() ? conversationList->count() - 1 : deletedRow;
            conversationList->setCurrentRow(nextRow);
        } else {
            conversationList->setCurrentRow(-1);
            currentTitle->setText(QStringLiteral("New conversation"));
            renderMessageSet(QJsonArray());
        }
        updateConversationSelectionStyles(conversationList);
        updateConversationActionState();
    });
    QObject::connect(clearAllButton, &QPushButton::clicked, [&]() {
        if (requestHistoryAction(QStringLiteral("deleteAllConversations"), QString(), QString(), QStringList())) {
            return;
        }

        conversationList->clear();
        conversationList->setCurrentRow(-1);
        updateConversationSelectionStyles(conversationList);
        currentTitle->setText(QStringLiteral("New conversation"));
        renderMessageSet(QJsonArray());
        updateConversationActionState();
    });
    QObject::connect(conversationList, &QListWidget::currentRowChanged, [&](int row) {
        updateConversationActionState();
        updateConversationSelectionStyles(conversationList);
        QListWidgetItem *item = conversationList->item(row);
        if (item == nullptr) {
            return;
        }

        const QString selectedID = item->data(Qt::UserRole).toString();
        currentTitle->setText(selectedConversationTitle(
            conversations,
            selectedID,
            QStringLiteral("New conversation")
        ));
        const QJsonArray selectedMessages = selectedConversationMessages(
            conversations,
            selectedID,
            fallbackMessages
        );
        renderMessageSet(selectedMessages);
    });
    QObject::connect(endpointField, &QLineEdit::editingFinished, [&]() {
        requestHistoryAction(
            QStringLiteral("configureEndpoint"),
            currentConversationID(conversationList, selectedConversationID),
            QString(),
            QStringList()
        );
    });
    QObject::connect(refreshButton, &QPushButton::clicked, [&]() {
        requestHistoryAction(
            QStringLiteral("refreshModels"),
            currentConversationID(conversationList, selectedConversationID),
            QString(),
            QStringList()
        );
    });
    QObject::connect(modelPicker, &QComboBox::currentTextChanged, [&](const QString &model) {
        modelStatus->setText(modelStatusText(model));
        requestHistoryAction(
            QStringLiteral("selectModel"),
            currentConversationID(conversationList, selectedConversationID),
            QString(),
            QStringList()
        );
    });
    QObject::connect(attachButton, &QPushButton::clicked, [&]() {
        const QString rawPath = attachmentPath->text().trimmed();
        const QString displayName = attachmentDisplayName(rawPath);
        if (displayName.isEmpty()) {
            return;
        }

        pendingAttachmentSummary = QStringLiteral("- %1").arg(displayName);
        pendingAttachmentPaths.clear();
        pendingAttachmentPaths.append(rawPath);
        attachmentChipText->setText(displayName);
        attachmentPath->clear();
        attachmentTray->setVisible(true);
        updateComposerControlState();
    });
    QObject::connect(clearAttachmentsButton, &QPushButton::clicked, [&]() {
        clearAttachmentState();
    });
    QObject::connect(attachmentPath, &QLineEdit::textChanged, [&]() {
        updateComposerControlState();
    });
    QObject::connect(promptEditor, &QPlainTextEdit::textChanged, [&]() {
        updateComposerControlState();
    });
    QObject::connect(sendButton, &QPushButton::clicked, [&]() {
        if (isLoading) {
            statusText->setText(stoppingStatus);
            return;
        }

        appendComposerMessage(promptEditor->toPlainText());
        clearAttachmentState();
    });
    updateComposerControlState();
    updateConversationActionState();

    window.show();
    return app.exec();
}
