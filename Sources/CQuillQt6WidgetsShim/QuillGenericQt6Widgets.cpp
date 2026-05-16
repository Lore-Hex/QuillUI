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

int intValue(const QJsonObject &object, const char *key, int fallback) {
    return jsonIntValue(object, key, fallback);
}

QString styleValue(const QJsonObject &style, const char *key, const char *fallback) {
    return jsonStyleValue(style, key, fallback);
}

struct GenericDetailPane {
    QWidget *view;
    QLabel *titleLabel;
    QLabel *subtitleLabel;
    QVBoxLayout *contentLayout;
};

struct GenericSelection {
    QString detailTitle;
    QString detailSubtitle;
    QString messagesTitle;
    QJsonArray sections;
    QJsonArray messages;
};

QString genericStyleSheet(const QJsonObject &style) {
    const QString canvas = styleValue(style, "canvasColor", "#F7F8F4");
    const QString ink = styleValue(style, "inkColor", "#182027");
    const QString sidebar = styleValue(style, "sidebarColor", "#EEF2EA");
    const QString muted = styleValue(style, "mutedColor", "#65707A");
    const QString badge = styleValue(style, "badgeColor", "#295A7A");
    const QString card = styleValue(style, "cardColor", "#FFFFFF");
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
    const QString messageBodyFontSize = cssPixels(style, "messageBodyFontSize", 14);
    const QString conversationTitleFontSize = cssPixels(style, "conversationTitleFontSize", 15);
    const QString conversationTitleFontWeight = QString::number(intValue(style, "conversationTitleFontWeight", 700));

    QString sheet = QStringLiteral(R"(
        QWidget#genericRoot { background: %1; color: %2; font-size: %3; }
        QFrame#sidebar { background: %4; border-right: 1px solid %5; }
        QLabel#subtitle, QLabel#caption, QLabel#statusText, QLabel#itemSubtitle, QLabel#messageMeta { color: %6; font-size: %7; }
        QFrame#card, QFrame#messageCard { background: %8; border: 1px solid %9; border-radius: 8px; }
    )").arg(canvas, ink, rootFontSize, sidebar, divider, muted, captionFontSize, card, border);

    sheet += QStringLiteral(R"(
        QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }
        QLabel#sectionTitle { color: %1; font-size: %4; font-weight: %5; }
        QLabel#detailTitle { color: %1; font-size: %6; font-weight: %7; }
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
        QLabel#badge { color: %3; font-size: %4; font-weight: %5; }
    )").arg(ink, messageBodyFontSize, badge, captionFontSize, sectionTitleFontWeight);

    sheet += QStringLiteral(R"(
        QFrame#activeCard { background: %1; border: 1px solid %2; border-radius: 8px; }
    )").arg(activeCard, selectedBorder);

    sheet += QStringLiteral(R"(
        QListWidget#itemList { background: transparent; border: 0; outline: 0; }
        QListWidget#itemList::item { border-radius: 8px; margin: 2px 0; padding: 8px; }
        QListWidget#itemList::item:selected { background: %1; color: %2; }
        QPushButton#primaryButton { background: %3; color: white; border: 0; border-radius: 8px; padding: 8px 12px; text-align: left; }
        QPushButton#secondaryButton { background: transparent; color: %2; border: 1px solid %4; border-radius: 7px; padding: 7px 10px; text-align: left; }
        QScrollArea { background: %5; border: 0; }
        QSplitter::handle { background: %6; }
    )").arg(selected, ink, primary, controlBorder, canvas, divider);

    return sheet;
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

GenericSelection selectionForRow(const QJsonObject &payload, const QJsonArray &items, int row) {
    const QString baseTitle = stringValue(payload, "detailTitle", QStringLiteral("Qt preview"));
    const QString baseSubtitle = stringValue(payload, "detailSubtitle");
    const QJsonObject item = selectedItem(items, row);

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
        detailTitle,
        detailSubtitle,
        stringValue(payload, "messagesTitle", QStringLiteral("Activity")),
        sections,
        messages
    };
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
    const GenericSelection &selection
) {
    clearLayout(layout);

    int sectionIndex = 0;
    for (const QJsonValue &value : selection.sections) {
        layout->addWidget(detailCard(value.toObject(), sectionIndex == 0));
        sectionIndex += 1;
    }

    if (!selection.messages.isEmpty()) {
        layout->addWidget(label(selection.messagesTitle, QStringLiteral("sectionTitle")));
        for (const QJsonValue &value : selection.messages) {
            layout->addWidget(messageCard(value.toObject()));
        }
    }

    layout->addStretch(1);
}

void applySelection(GenericDetailPane &detailPane, const GenericSelection &selection) {
    detailPane.titleLabel->setText(selection.detailTitle);
    detailPane.subtitleLabel->setText(selection.detailSubtitle);
    populateDetailContent(detailPane.contentLayout, selection);
}

GenericDetailPane detailWidget(const QJsonObject &payload, const QJsonArray &items, int selectedIndex) {
    QWidget *detail = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(detail);
    layout->setContentsMargins(24, 22, 24, 22);
    layout->setSpacing(14);

    const GenericSelection selection = selectionForRow(payload, items, selectedIndex);
    QLabel *title = label(selection.detailTitle, QStringLiteral("detailTitle"));
    QLabel *subtitle = label(selection.detailSubtitle, QStringLiteral("caption"));
    layout->addWidget(title);
    layout->addWidget(subtitle);

    QVBoxLayout *contentLayout = new QVBoxLayout();
    contentLayout->setContentsMargins(0, 0, 0, 0);
    contentLayout->setSpacing(14);
    layout->addLayout(contentLayout, 1);
    populateDetailContent(contentLayout, selection);

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
    root.setWindowTitle(stringValue(payload, "windowTitle", QStringLiteral("QuillUI Qt")));
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
    const int selectedIndex = boundedSelectedIndex(items, rawSelectedIndex);
    QListWidget *itemList = listWidget(items, selectedIndex);
    GenericDetailPane detailPane = detailWidget(payload, items, selectedIndex);
    QObject::connect(itemList, &QListWidget::currentRowChanged, [&](int row) {
        applySelection(detailPane, selectionForRow(payload, items, row));
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
