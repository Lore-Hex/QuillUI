#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QComboBox>
#include <QFrame>
#include <QHBoxLayout>
#include <QJsonArray>
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
#include <QSplitter>
#include <QString>
#include <QVBoxLayout>
#include <QWidget>

#include <algorithm>

namespace {

using QuillQtWidgets::clearLayout;
using QuillQtWidgets::label;

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

QJsonObject objectValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonObjectValue(object, key);
}

QJsonArray arrayValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonArrayValue(object, key);
}

QSize resolvedMinimumWindowSize(const QJsonObject &payload) {
    return QSize(
        intValue(payload, "minimumWidth", 980),
        intValue(payload, "minimumHeight", 680)
    );
}

QSize resolvedDefaultWindowSize(const QJsonObject &payload, const QSize &minimumSize) {
    return QSize(
        std::max(intValue(payload, "defaultWidth", minimumSize.width()), minimumSize.width()),
        std::max(intValue(payload, "defaultHeight", minimumSize.height()), minimumSize.height())
    );
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
        QLabel#caption, QLabel#fieldLabel, QLabel#statusText, QLabel#messageRole, QLabel#conversationPreview { color: %8; font-size: 12px; }
        QLabel#sectionTitle { color: %2; font-size: 15px; font-weight: 700; }
        QLabel#currentTitle { color: %2; font-size: 20px; font-weight: 650; }
        QLabel#messageText { color: %2; font-size: 14px; }
        QFrame#messageAssistant, QFrame#messageSystem, QFrame#promptCard { background: %5; border: 1px solid #E0E5DD; border-radius: 8px; }
        QFrame#messageUser { background: %7; border: 1px solid #D4DFE8; border-radius: 8px; }
        QPushButton#primaryButton, QPushButton#sendButton { background: %6; color: white; border: 0; border-radius: 8px; padding: 9px 12px; text-align: left; }
        QPushButton#secondaryButton, QPushButton#promptButton { background: transparent; color: %2; border: 1px solid #CDD5CA; border-radius: 7px; padding: 7px 10px; text-align: left; }
    )")
        .arg(canvas, ink, sidebar, header, card, primary, system, muted);

    sheet += QStringLiteral(R"(
        QListWidget#conversationList { background: transparent; border: 0; outline: 0; }
        QListWidget#conversationList::item { border-radius: 8px; margin: 2px 0; padding: 8px; }
        QListWidget#conversationList::item:selected { background: %1; color: %2; }
        QLineEdit, QComboBox, QPlainTextEdit { background: %3; color: %2; border: 1px solid #CDD5CA; border-radius: 7px; padding: 7px; }
        QLabel#statusDot { color: %4; font-size: 18px; }
        QLabel#warningText { color: %5; font-size: 12px; }
        QFrame#dropTarget { background: %6; border: 1px solid #C8DED3; border-radius: 8px; }
        QSplitter::handle { background: #D8DDD5; }
        QScrollArea { background: %7; border: 0; }
    )")
        .arg(selected, ink, card, success, warning, dropTarget, canvas);

    return sheet;
}

QFrame *conversationRowWidget(const QJsonObject &conversation) {
    QFrame *row = QuillQtWidgets::frame(QStringLiteral("conversationRow"));
    QVBoxLayout *layout = new QVBoxLayout(row);
    layout->setContentsMargins(2, 3, 2, 3);
    layout->setSpacing(3);

    QLabel *title = label(
        stringValue(conversation, "title", QStringLiteral("New conversation")),
        QStringLiteral("sectionTitle")
    );
    title->setWordWrap(false);

    QLabel *preview = label(
        stringValue(conversation, "lastMessage", QStringLiteral("No messages yet")),
        QStringLiteral("conversationPreview")
    );

    layout->addWidget(title);
    layout->addWidget(preview);
    return row;
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
    layout->addWidget(label(role.toUpper(), QStringLiteral("messageRole")));
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

void addPromptCards(QVBoxLayout *messageLayout, const QJsonArray &prompts) {
    QFrame *card = QuillQtWidgets::frame(QStringLiteral("promptCard"));
    QVBoxLayout *layout = new QVBoxLayout(card);
    layout->setContentsMargins(18, 16, 18, 16);
    layout->setSpacing(9);
    layout->addWidget(label(QStringLiteral("Ask your local model"), QStringLiteral("currentTitle")));
    layout->addWidget(label(
        QStringLiteral("Start with a prompt, attach an image path, or select an existing conversation."),
        QStringLiteral("caption")
    ));

    for (const QJsonValue &value : prompts) {
        QPushButton *button = new QPushButton(value.toString());
        button->setObjectName(QStringLiteral("promptButton"));
        layout->addWidget(button);
    }
    messageLayout->addWidget(card);
    messageLayout->addStretch(1);
}

void renderMessages(
    QVBoxLayout *messageLayout,
    const QJsonArray &messages,
    const QJsonArray &prompts,
    const QJsonObject &style
) {
    clearLayout(messageLayout);
    if (messages.isEmpty()) {
        addPromptCards(messageLayout, prompts);
        return;
    }

    for (const QJsonValue &value : messages) {
        addMessageBubble(messageLayout, value.toObject(), style);
    }
}

QLabel *fieldLabel(const QString &text) {
    return label(text, QStringLiteral("fieldLabel"));
}

void addSidebarField(QVBoxLayout *layout, const QString &title, QWidget *field) {
    layout->addWidget(fieldLabel(title));
    layout->addWidget(field);
}

} // namespace

extern "C" int quill_enchanted_qt_run_app_json(
    int argc,
    char **argv,
    const char *payload_json
) {
    QJsonObject payload;
    int payloadExitCode = 65;
    if (!QuillQtWidgets::parseJsonObjectPayload(
        payload_json,
        "quill-enchanted-qt",
        65,
        65,
        &payload,
        &payloadExitCode
    )) {
        return payloadExitCode;
    }

    QApplication app(argc, argv);
    const QJsonObject style = objectValue(payload, "style");
    app.setApplicationName(stringValue(payload, "windowTitle", QStringLiteral("Quill Enchanted")));
    app.setStyleSheet(appStyleSheet(style));

    QWidget window;
    window.setObjectName(QStringLiteral("enchantedRoot"));
    window.setWindowTitle(stringValue(payload, "windowTitle", QStringLiteral("Quill Enchanted")));
    const QSize minimumWindowSize = resolvedMinimumWindowSize(payload);
    const QSize defaultWindowSize = resolvedDefaultWindowSize(payload, minimumWindowSize);
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

    QComboBox *modelPicker = new QComboBox();
    const QJsonArray models = arrayValue(payload, "models");
    for (const QJsonValue &model : models) {
        modelPicker->addItem(model.toString());
    }
    const int selectedModelIndex = modelPicker->findText(stringValue(payload, "selectedModel"));
    if (selectedModelIndex >= 0) {
        modelPicker->setCurrentIndex(selectedModelIndex);
    }
    addSidebarField(
        sidebarLayout,
        stringValue(payload, "modelLabel", QStringLiteral("Model")),
        modelPicker
    );

    QHBoxLayout *statusLayout = new QHBoxLayout();
    statusLayout->setContentsMargins(0, 0, 0, 0);
    statusLayout->setSpacing(8);
    statusLayout->addWidget(label(QStringLiteral("*"), QStringLiteral("statusDot")));
    statusLayout->addWidget(label(stringValue(payload, "status"), QStringLiteral("statusText")));
    sidebarLayout->addLayout(statusLayout);

    sidebarLayout->addWidget(label(
        stringValue(payload, "conversationsTitle", QStringLiteral("Conversations")),
        QStringLiteral("sectionTitle")
    ));

    const QJsonArray conversations = arrayValue(payload, "conversations");
    const QString selectedConversationID = stringValue(payload, "selectedConversationID");
    QListWidget *conversationList = new QListWidget();
    conversationList->setObjectName(QStringLiteral("conversationList"));
    populateConversations(
        conversationList,
        conversations,
        selectedConversationID
    );
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
            QStringLiteral("QuillUI backend parity")
        ),
        QStringLiteral("currentTitle")
    );
    QLabel *modelStatus = label(
        QStringLiteral("Using %1").arg(stringValue(payload, "selectedModel", QStringLiteral("local model"))),
        QStringLiteral("caption")
    );
    titleLayout->addWidget(currentTitle);
    titleLayout->addWidget(modelStatus);
    headerLayout->addLayout(titleLayout, 1);
    QPushButton *refreshButton = new QPushButton(stringValue(payload, "refreshModelsTitle", QStringLiteral("Refresh models")));
    refreshButton->setObjectName(QStringLiteral("secondaryButton"));
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

    const QJsonArray fallbackMessages = arrayValue(payload, "messages");
    const QJsonArray prompts = arrayValue(payload, "prompts");
    const QJsonArray initialMessages = selectedConversationMessages(
        conversations,
        initialConversationID,
        fallbackMessages
    );
    renderMessages(messageLayout, initialMessages, prompts, style);
    bool showingPromptCards = initialMessages.isEmpty();

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
    QPushButton *attachButton = new QPushButton(QStringLiteral("Attach"));
    attachButton->setObjectName(QStringLiteral("secondaryButton"));
    dropLayout->addWidget(attachmentPath, 1);
    dropLayout->addWidget(attachButton);
    composerLayout->addWidget(dropTarget);

    QHBoxLayout *promptRow = new QHBoxLayout();
    promptRow->setSpacing(10);
    QPlainTextEdit *promptEditor = new QPlainTextEdit();
    promptEditor->setPlaceholderText(stringValue(
        payload,
        "composerPlaceholder",
        QStringLiteral("Ask a local model...")
    ));
    promptEditor->setFixedHeight(intValue(style, "composerHeight", 84));
    QPushButton *sendButton = new QPushButton(stringValue(payload, "sendTitle", QStringLiteral("Send")));
    sendButton->setObjectName(QStringLiteral("sendButton"));
    sendButton->setMinimumWidth(86);
    promptRow->addWidget(promptEditor, 1);
    promptRow->addWidget(sendButton);
    composerLayout->addLayout(promptRow);
    chatLayout->addWidget(composer);

    splitter->addWidget(sidebar);
    splitter->addWidget(chatPane);
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);

    QObject::connect(newChatButton, &QPushButton::clicked, [&]() {
        currentTitle->setText(QStringLiteral("New conversation"));
        renderMessages(messageLayout, QJsonArray(), prompts, style);
        showingPromptCards = true;
    });
    QObject::connect(conversationList, &QListWidget::currentRowChanged, [&](int row) {
        QListWidgetItem *item = conversationList->item(row);
        if (item == nullptr) {
            return;
        }

        const QString selectedID = item->data(Qt::UserRole).toString();
        currentTitle->setText(selectedConversationTitle(
            conversations,
            selectedID,
            QStringLiteral("QuillUI backend parity")
        ));
        const QJsonArray selectedMessages = selectedConversationMessages(
            conversations,
            selectedID,
            fallbackMessages
        );
        renderMessages(messageLayout, selectedMessages, prompts, style);
        showingPromptCards = selectedMessages.isEmpty();
    });
    QObject::connect(attachButton, &QPushButton::clicked, [attachmentPath]() {
        attachmentPath->setText(QStringLiteral("/tmp/reference-image.png"));
    });
    QObject::connect(sendButton, &QPushButton::clicked, [&]() {
        const QString text = promptEditor->toPlainText().trimmed();
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
    });

    window.show();
    return app.exec();
}
