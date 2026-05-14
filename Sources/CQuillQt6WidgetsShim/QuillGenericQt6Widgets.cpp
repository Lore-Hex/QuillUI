#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QFrame>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLayout>
#include <QList>
#include <QListWidget>
#include <QListWidgetItem>
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
using QuillQtWidgets::jsonArrayValue;
using QuillQtWidgets::jsonIntValue;
using QuillQtWidgets::jsonStringValue;
using QuillQtWidgets::label;

QString stringValue(const QJsonObject &object, const char *key, const QString &fallback = QString()) {
    return jsonStringValue(object, key, fallback);
}

int intValue(const QJsonObject &object, const char *key, int fallback) {
    return jsonIntValue(object, key, fallback);
}

struct GenericDetailPane {
    QWidget *view;
    QLabel *titleLabel;
    QLabel *subtitleLabel;
    QVBoxLayout *contentLayout;
};

QString genericStyleSheet() {
    return QStringLiteral(R"(
        QWidget#genericRoot { background: #F7F8F4; color: #182027; font-size: 14px; }
        QFrame#sidebar { background: #EEF2EA; border-right: 1px solid #D8DDD4; }
        QLabel#appTitle { color: #182027; font-size: 25px; font-weight: 700; }
        QLabel#subtitle, QLabel#caption, QLabel#statusText, QLabel#itemSubtitle, QLabel#messageMeta { color: #65707A; font-size: 12px; }
        QLabel#sectionTitle { color: #182027; font-size: 15px; font-weight: 700; }
        QLabel#detailTitle { color: #182027; font-size: 22px; font-weight: 700; }
        QLabel#headline { color: #182027; font-size: 16px; font-weight: 650; }
        QLabel#bodyText, QLabel#messageText { color: #182027; font-size: 14px; line-height: 140%; }
        QLabel#badge { color: #295A7A; font-size: 12px; font-weight: 700; }
        QFrame#card, QFrame#messageCard { background: #FFFFFF; border: 1px solid #E0E4DC; border-radius: 8px; }
        QFrame#activeCard { background: #E7F0FA; border: 1px solid #CBDDEB; border-radius: 8px; }
        QListWidget#itemList { background: transparent; border: 0; outline: 0; }
        QListWidget#itemList::item { border-radius: 8px; margin: 2px 0; padding: 8px; }
        QListWidget#itemList::item:selected { background: #DDEBFA; color: #182027; }
        QPushButton#primaryButton { background: #2E5B78; color: white; border: 0; border-radius: 8px; padding: 8px 12px; text-align: left; }
        QPushButton#secondaryButton { background: transparent; color: #182027; border: 1px solid #CDD5CA; border-radius: 7px; padding: 7px 10px; text-align: left; }
        QScrollArea { background: #F7F8F4; border: 0; }
        QSplitter::handle { background: #D8DDD4; }
    )");
}

QSize minimumWindowSize(const QJsonObject &payload) {
    return QSize(
        intValue(payload, "minimumWidth", 900),
        intValue(payload, "minimumHeight", 620)
    );
}

QSize defaultWindowSize(const QJsonObject &payload, const QSize &minimumSize) {
    return QSize(
        std::max(intValue(payload, "defaultWidth", minimumSize.width()), minimumSize.width()),
        std::max(intValue(payload, "defaultHeight", minimumSize.height()), minimumSize.height())
    );
}

int boundedSelectedIndex(const QJsonArray &items, int selectedIndex) {
    if (items.isEmpty()) {
        return -1;
    }
    return std::min(std::max(selectedIndex, 0), static_cast<int>(items.size()) - 1);
}

QJsonObject selectedItem(const QJsonArray &items, int row) {
    if (row < 0 || row >= items.size()) {
        return QJsonObject();
    }
    return items.at(row).toObject();
}

QString selectedDetailTitle(const QJsonObject &payload, const QJsonArray &items, int row) {
    const QString baseTitle = stringValue(payload, "detailTitle", QStringLiteral("Qt preview"));
    const QJsonObject item = selectedItem(items, row);
    const QString itemDetailTitle = stringValue(item, "detailTitle");
    if (!itemDetailTitle.isEmpty()) {
        return itemDetailTitle;
    }

    const QString itemTitle = stringValue(item, "title");
    if (itemTitle.isEmpty()) {
        return baseTitle;
    }
    return baseTitle + QStringLiteral(": ") + itemTitle;
}

QString selectedDetailSubtitle(const QJsonObject &payload, const QJsonArray &items, int row) {
    const QString baseSubtitle = stringValue(payload, "detailSubtitle");
    const QJsonObject item = selectedItem(items, row);
    const QString itemDetailSubtitle = stringValue(item, "detailSubtitle");
    if (!itemDetailSubtitle.isEmpty()) {
        return itemDetailSubtitle;
    }

    const QString itemSubtitle = stringValue(item, "subtitle");
    if (baseSubtitle.isEmpty()) {
        return itemSubtitle;
    }
    if (itemSubtitle.isEmpty()) {
        return baseSubtitle;
    }
    return baseSubtitle + QStringLiteral("\n") + itemSubtitle;
}

QJsonArray selectedSections(const QJsonObject &payload, const QJsonArray &items, int row) {
    const QJsonObject item = selectedItem(items, row);
    if (item.contains(QStringLiteral("sections"))) {
        return jsonArrayValue(item, "sections");
    }
    return jsonArrayValue(payload, "sections");
}

QJsonArray selectedMessages(const QJsonObject &payload, const QJsonArray &items, int row) {
    const QJsonObject item = selectedItem(items, row);
    if (item.contains(QStringLiteral("messages"))) {
        return jsonArrayValue(item, "messages");
    }
    return jsonArrayValue(payload, "messages");
}

QFrame *itemRowWidget(const QJsonObject &item) {
    QFrame *row = QuillQtWidgets::frame(QStringLiteral("itemRow"));
    QVBoxLayout *layout = new QVBoxLayout(row);
    layout->setContentsMargins(2, 4, 2, 4);
    layout->setSpacing(4);

    QLabel *title = label(stringValue(item, "title", QStringLiteral("Untitled")), QStringLiteral("sectionTitle"));
    title->setWordWrap(false);
    layout->addWidget(title);
    layout->addWidget(label(stringValue(item, "subtitle"), QStringLiteral("itemSubtitle")));

    const QString badge = stringValue(item, "badge");
    if (!badge.isEmpty()) {
        layout->addWidget(label(badge, QStringLiteral("badge")));
    }
    return row;
}

QListWidget *listWidget(const QJsonArray &items, int selectedIndex) {
    QListWidget *list = new QListWidget();
    list->setObjectName(QStringLiteral("itemList"));
    list->setSpacing(4);

    for (const QJsonValue &value : items) {
        const QJsonObject item = value.toObject();
        QListWidgetItem *listItem = new QListWidgetItem();
        listItem->setSizeHint(QSize(264, intValue(item, "height", 76)));
        list->addItem(listItem);
        list->setItemWidget(listItem, itemRowWidget(item));
    }

    const int boundedIndex = boundedSelectedIndex(items, selectedIndex);
    if (boundedIndex >= 0) {
        list->setCurrentRow(boundedIndex);
    }
    return list;
}

QWidget *sidebarWidget(const QJsonObject &payload, QListWidget *list) {
    QFrame *sidebar = QuillQtWidgets::frame(QStringLiteral("sidebar"));
    QVBoxLayout *layout = new QVBoxLayout(sidebar);
    layout->setContentsMargins(18, 18, 18, 18);
    layout->setSpacing(12);

    layout->addWidget(label(stringValue(payload, "sidebarTitle", QStringLiteral("QuillUI")), QStringLiteral("appTitle")));
    layout->addWidget(label(stringValue(payload, "sidebarSubtitle", QStringLiteral("Qt backend")), QStringLiteral("subtitle")));

    QHBoxLayout *actions = new QHBoxLayout();
    QPushButton *primary = new QPushButton(stringValue(payload, "primaryActionTitle", QStringLiteral("New")));
    primary->setObjectName(QStringLiteral("primaryButton"));
    QPushButton *secondary = new QPushButton(stringValue(payload, "secondaryActionTitle", QStringLiteral("Refresh")));
    secondary->setObjectName(QStringLiteral("secondaryButton"));
    actions->addWidget(primary);
    actions->addWidget(secondary);
    layout->addLayout(actions);

    layout->addWidget(label(stringValue(payload, "listTitle", QStringLiteral("Items")), QStringLiteral("sectionTitle")));
    layout->addWidget(list, 1);
    layout->addWidget(label(stringValue(payload, "status", QStringLiteral("Ready")), QStringLiteral("statusText")));
    return sidebar;
}

QFrame *detailCard(const QJsonObject &section, bool active) {
    QFrame *card = QuillQtWidgets::frame(active ? QStringLiteral("activeCard") : QStringLiteral("card"));
    QVBoxLayout *layout = new QVBoxLayout(card);
    layout->setContentsMargins(16, 14, 16, 14);
    layout->setSpacing(7);
    layout->addWidget(label(stringValue(section, "title", QStringLiteral("Section")), QStringLiteral("headline")));
    layout->addWidget(label(stringValue(section, "body"), QStringLiteral("bodyText")));
    return card;
}

QFrame *messageCard(const QJsonObject &message) {
    QFrame *card = QuillQtWidgets::frame(QStringLiteral("messageCard"));
    QVBoxLayout *layout = new QVBoxLayout(card);
    layout->setContentsMargins(14, 10, 14, 10);
    layout->setSpacing(6);
    layout->addWidget(label(stringValue(message, "sender", QStringLiteral("System")), QStringLiteral("messageMeta")));
    layout->addWidget(label(stringValue(message, "body"), QStringLiteral("messageText")));
    return card;
}

void populateDetailContent(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonArray &items,
    int row
) {
    clearLayout(layout);

    const QJsonArray sections = selectedSections(payload, items, row);
    int sectionIndex = 0;
    for (const QJsonValue &value : sections) {
        layout->addWidget(detailCard(value.toObject(), sectionIndex == 0));
        sectionIndex += 1;
    }

    const QJsonArray messages = selectedMessages(payload, items, row);
    if (!messages.isEmpty()) {
        layout->addWidget(label(stringValue(payload, "messagesTitle", QStringLiteral("Activity")), QStringLiteral("sectionTitle")));
        for (const QJsonValue &value : messages) {
            layout->addWidget(messageCard(value.toObject()));
        }
    }

    layout->addStretch(1);
}

GenericDetailPane detailWidget(const QJsonObject &payload, const QJsonArray &items, int selectedIndex) {
    QWidget *detail = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(detail);
    layout->setContentsMargins(24, 22, 24, 22);
    layout->setSpacing(14);

    QLabel *title = label(selectedDetailTitle(payload, items, selectedIndex), QStringLiteral("detailTitle"));
    QLabel *subtitle = label(selectedDetailSubtitle(payload, items, selectedIndex), QStringLiteral("caption"));
    layout->addWidget(title);
    layout->addWidget(subtitle);

    QVBoxLayout *contentLayout = new QVBoxLayout();
    contentLayout->setContentsMargins(0, 0, 0, 0);
    contentLayout->setSpacing(14);
    layout->addLayout(contentLayout, 1);
    populateDetailContent(contentLayout, payload, items, selectedIndex);

    return GenericDetailPane { detail, title, subtitle, contentLayout };
}

QWidget *scrollWrapped(QWidget *child) {
    QScrollArea *scroll = new QScrollArea();
    scroll->setWidgetResizable(true);
    scroll->setWidget(child);
    return scroll;
}

} // namespace

extern "C" int quill_generic_qt_run_app_json(int argc, char **argv, const char *payload_json) {
    QJsonObject payload;
    int payloadExitCode = 64;
    if (!QuillQtWidgets::parseJsonObjectPayload(
        payload_json,
        "quill-generic-qt",
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
    root.setWindowTitle(stringValue(payload, "windowTitle", QStringLiteral("QuillUI Qt")));
    root.setStyleSheet(genericStyleSheet());
    const QSize minimumSize = minimumWindowSize(payload);
    root.setMinimumSize(minimumSize);
    root.resize(defaultWindowSize(payload, minimumSize));

    QHBoxLayout *rootLayout = new QHBoxLayout(&root);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    const QJsonArray items = jsonArrayValue(payload, "items");
    const int rawSelectedIndex = intValue(payload, "selectedIndex", 0);
    const int selectedIndex = boundedSelectedIndex(items, rawSelectedIndex);
    QListWidget *itemList = listWidget(items, selectedIndex);
    GenericDetailPane detailPane = detailWidget(payload, items, selectedIndex);
    QObject::connect(itemList, &QListWidget::currentRowChanged, [&](int row) {
        detailPane.titleLabel->setText(selectedDetailTitle(payload, items, row));
        detailPane.subtitleLabel->setText(selectedDetailSubtitle(payload, items, row));
        populateDetailContent(detailPane.contentLayout, payload, items, row);
    });

    QSplitter *splitter = new QSplitter(Qt::Horizontal);
    splitter->addWidget(sidebarWidget(payload, itemList));
    splitter->addWidget(scrollWrapped(detailPane.view));
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);
    QList<int> splitSizes;
    splitSizes << intValue(payload, "sidebarWidth", 320) << intValue(payload, "detailWidth", 720);
    splitter->setSizes(splitSizes);
    rootLayout->addWidget(splitter);

    root.show();
    return app.exec();
}
