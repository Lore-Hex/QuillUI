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
#include <QSizePolicy>
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

    QString sheet = QStringLiteral(R"(
        QWidget#genericRoot { background: %1; color: %2; font-size: %3; }
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
        QFrame#card { background: %1; border: 1px solid %2; border-radius: %3; }
        QFrame#messageCard { background: %1; border: 1px solid %2; border-radius: %4; }
    )").arg(
        card,
        border,
        cardRadius,
        messageCardRadius
    );

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
        QFrame#activeCard { background: %1; border: 1px solid %2; border-radius: %3; }
    )").arg(activeCard, selectedBorder, activeCardRadius);

    sheet += QStringLiteral(R"(
        QListWidget#itemList { background: transparent; border: 0; outline: 0; }
        QListWidget#itemList::item { border-radius: %1; margin: %2 0; padding: %3; }
        QListWidget#itemList::item:selected { background: %4; color: %5; }
    )").arg(listItemRadius, listItemVerticalMargin, listItemPadding, selected, ink);

    sheet += QStringLiteral(R"(
        QPushButton#primaryButton { background: %1; color: white; border: 0; border-radius: %2; padding: %3 %4; text-align: left; }
        QPushButton#secondaryButton { background: transparent; color: %5; border: 1px solid %6; border-radius: %7; padding: %8 %9; text-align: left; }
    )").arg(
        primary,
        primaryButtonRadius,
        primaryButtonVerticalPadding,
        primaryButtonHorizontalPadding,
        ink,
        controlBorder,
        secondaryButtonRadius,
        secondaryButtonVerticalPadding,
        secondaryButtonHorizontalPadding
    );

    sheet += QStringLiteral(R"(
        QScrollArea { background: %1; border: 0; }
        QSplitter::handle { background: %2; }
    )").arg(canvas, divider);

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

QFrame *itemRowWidget(const QJsonObject &item, const QJsonObject &style) {
    const QString titleText = stringValue(item, "title", QStringLiteral("Untitled"));
    const QString subtitleText = stringValue(item, "subtitle");
    const QString badgeText = stringValue(item, "badge");
    const QString secondaryText = accessibilitySummary(subtitleText, badgeText);
    const QString rowSummary = accessibilitySummary(titleText, secondaryText);
    const int horizontalPadding = intValue(style, "itemRowHorizontalPadding", 2);
    const int verticalPadding = intValue(style, "itemRowVerticalPadding", 4);

    QFrame *row = QuillQtWidgets::frame(QStringLiteral("itemRow"));
    applyAccessibleText(row, titleText, rowSummary);
    QVBoxLayout *layout = new QVBoxLayout(row);
    layout->setContentsMargins(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding);
    layout->setSpacing(intValue(style, "itemRowSpacing", 4));

    QLabel *title = label(titleText, QStringLiteral("sectionTitle"));
    applyAccessibleText(title, titleText, rowSummary);
    title->setWordWrap(false);
    layout->addWidget(title);

    QLabel *subtitle = label(subtitleText, QStringLiteral("itemSubtitle"));
    applyAccessibleText(subtitle, subtitleText, subtitleText);
    layout->addWidget(subtitle);

    if (!badgeText.isEmpty()) {
        QLabel *badge = label(badgeText, QStringLiteral("badge"));
        applyAccessibleText(badge, badgeText, badgeText);
        layout->addWidget(badge);
    }
    return row;
}

QListWidget *listWidget(const QJsonArray &items, int selectedIndex, const QJsonObject &style) {
    QListWidget *list = new QListWidget();
    list->setObjectName(QStringLiteral("itemList"));
    applyAccessibleText(list, QStringLiteral("App items"), QStringLiteral("App items"));
    list->setSpacing(intValue(style, "listSpacing", 4));
    list->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);

    for (const QJsonValue &value : items) {
        const QJsonObject item = value.toObject();
        QListWidgetItem *listItem = new QListWidgetItem();
        listItem->setSizeHint(QSize(264, intValue(item, "height", 76)));
        list->addItem(listItem);
        list->setItemWidget(listItem, itemRowWidget(item, style));
    }

    const int boundedIndex = boundedSelectedIndex(items, selectedIndex);
    if (boundedIndex >= 0) {
        list->setCurrentRow(boundedIndex);
    }
    return list;
}

QWidget *sidebarWidget(const QJsonObject &payload, QListWidget *list, const QJsonObject &style) {
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
    QLabel *status = label(statusText, QStringLiteral("statusText"));
    applyAccessibleText(status, statusText, statusText);
    layout->addWidget(status);
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

void populateDetailContent(
    QVBoxLayout *layout,
    const GenericSelection &selection,
    const QJsonObject &style
) {
    clearLayout(layout);

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

void applySelection(GenericDetailPane &detailPane, const GenericSelection &selection, const QJsonObject &style) {
    const QString detailSummary = accessibilitySummary(selection.detailTitle, selection.detailSubtitle);
    detailPane.titleLabel->setText(selection.detailTitle);
    detailPane.subtitleLabel->setText(selection.detailSubtitle);
    applyAccessibleText(detailPane.view, selection.detailTitle, detailSummary);
    applyAccessibleText(detailPane.titleLabel, selection.detailTitle, detailSummary);
    applyAccessibleText(detailPane.subtitleLabel, selection.detailSubtitle, selection.detailSubtitle);
    populateDetailContent(detailPane.contentLayout, selection, style);
}

GenericDetailPane detailWidget(
    const QJsonObject &payload,
    const QJsonArray &items,
    int selectedIndex,
    const QJsonObject &style
) {
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

    return GenericDetailPane { detail, title, subtitle, contentLayout };
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
    const int selectedIndex = boundedSelectedIndex(items, rawSelectedIndex);
    QListWidget *itemList = listWidget(items, selectedIndex, style);
    GenericDetailPane detailPane = detailWidget(payload, items, selectedIndex, style);
    QObject::connect(itemList, &QListWidget::currentRowChanged, [&](int row) {
        applySelection(detailPane, selectionForRow(payload, items, row), style);
    });

    QSplitter *splitter = new QSplitter(Qt::Horizontal);
    splitter->addWidget(sidebarWidget(payload, itemList, style));
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
