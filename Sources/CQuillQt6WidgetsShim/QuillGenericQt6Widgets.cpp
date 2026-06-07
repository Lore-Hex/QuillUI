#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QColor>
#include <QFrame>
#include <QFontMetrics>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QIcon>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLayout>
#include <QLinearGradient>
#include <QList>
#include <QListWidget>
#include <QListWidgetItem>
#include <QLineEdit>
#include <QAbstractItemView>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPushButton>
#include <QPixmap>
#include <QScrollArea>
#include <QSize>
#include <QSizePolicy>
#include <QSplitter>
#include <QStyle>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

#include <algorithm>
#include <cstdlib>

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
        QFrame#promptCard { background: %1; border: 0; border-radius: %2; }
        QFrame#notice { background: %3; border: 0; border-radius: %2; }
        QFrame#composerFrame { background: %4; border: 1px solid %6; border-radius: %7; }
        QLineEdit#composerEditor { background: transparent; color: %5; border: 0; padding-left: 0; padding-right: 0; }
        QLabel#composerAccessoryIcon { background: transparent; border: 0; }
        QFrame#settingsPanel { background: %1; border: 0; border-radius: %2; }
        QLineEdit#settingsField { background: white; color: %5; border: 1px solid %6; border-radius: %2; padding: %8; }
        QPushButton#settingsOptionButton { background: white; color: %5; border: 1px solid %6; border-radius: %2; padding: %8; }
        QPushButton#settingsPrimaryButton { background: %5; color: white; border: 0; border-radius: %2; padding: %8; font-weight: 650; }
    )").arg(
        promptCard,
        promptButtonRadius,
        notice,
        canvas,
        ink,
        controlBorder,
        composerEditorRadius,
        promptButtonPadding
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
        QLabel#badge { color: %3; font-size: %4; font-weight: %5; }
    )").arg(ink, messageBodyFontSize, badge, captionFontSize, sectionTitleFontWeight);

    sheet += QStringLiteral(R"(
        QFrame#activeCard { background: %1; border: 1px solid %2; border-radius: %3; }
    )").arg(activeCard, selectedBorder, activeCardRadius);

    sheet += QStringLiteral(R"(
        QFrame#messageUserBubble { background: %1; border: 0; border-radius: %4; }
        QFrame#messageAssistantBubble { background: %2; border: 0; border-radius: %4; }
        QFrame#messageSystemBubble { background: %3; border: 0; border-radius: %4; }
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

QFrame *promptCardWidget(const QJsonObject &prompt, const QJsonObject &style) {
    const QString titleText = stringValue(prompt, "title", QStringLiteral("Prompt"));
    const QString systemImage = stringValue(prompt, "systemImage");
    const QString accessoryText = promptAccessoryText(systemImage);

    QFrame *card = QuillQtWidgets::frame(QStringLiteral("promptCard"));
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

    QLabel *body = label(bodyText, isUser ? QStringLiteral("messageTextInverted") : QStringLiteral("messageText"));
    body->setWordWrap(true);
    applyAccessibleText(body, bodyText, bodyText);
    layout->addWidget(body);

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
    return panel;
}

void populateSettingsContent(
    QVBoxLayout *layout,
    const QJsonObject &payload,
    const QJsonObject &style
) {
    clearLayout(layout);
    layout->addStretch(1);
    layout->addWidget(settingsPaneWidget(payload, style), 0, Qt::AlignCenter);
    layout->addStretch(1);
}

void populateDetailContent(
    QVBoxLayout *layout,
    const GenericSelection &selection,
    const QJsonObject &style,
    bool chatMode = false
) {
    clearLayout(layout);

    if (chatMode && !selection.messages.isEmpty()) {
        layout->addStretch(1);
        populateChatMessages(layout, selection.messages, style);
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
    if (chatMode && activeNavigationIdentifier(payload) == QStringLiteral("settings")) {
        populateSettingsContent(detailPane.contentLayout, payload, style);
    } else if (chatMode && !selection.hasSelection) {
        populateEmptyStateContent(detailPane.contentLayout, payload, style);
    } else {
        populateDetailContent(detailPane.contentLayout, selection, style, chatMode);
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
    headerLayout->addWidget(headerIconButton(
        QStringLiteral("chevron.down"),
        QStringLiteral("Conversation menu"),
        style
    ));
    headerLayout->addWidget(headerIconButton(
        QStringLiteral("ellipsis"),
        QStringLiteral("More options"),
        style
    ));
    headerLayout->addWidget(headerIconButton(
        QStringLiteral("chevron.down"),
        QStringLiteral("More options menu"),
        style
    ));
    headerLayout->addWidget(headerIconButton(
        QStringLiteral("square.and.pencil"),
        QStringLiteral("New chat"),
        style
    ));
    layout->addWidget(header);

    QWidget *body = new QWidget();
    QVBoxLayout *bodyLayout = new QVBoxLayout(body);
    const int contentPadding = intValue(style, "contentPadding", 22);
    bodyLayout->setContentsMargins(contentPadding, contentPadding, contentPadding, contentPadding);
    bodyLayout->setSpacing(intValue(style, "messageSpacing", 14));

    QWidget *conversationHost = new QWidget();
    QVBoxLayout *conversationLayout = new QVBoxLayout(conversationHost);
    conversationLayout->setContentsMargins(0, 0, 0, 0);
    conversationLayout->setSpacing(intValue(style, "detailContentSpacing", 14));
    if (activeNavigationIdentifier(payload) == QStringLiteral("settings")) {
        populateSettingsContent(conversationLayout, payload, style);
    } else if (selectedIndex >= 0) {
        populateDetailContent(conversationLayout, selection, style, true);
    } else {
        populateEmptyStateContent(conversationLayout, payload, style);
    }
    bodyLayout->addWidget(conversationHost, 1);

    if (QFrame *notice = noticeWidget(payload, style)) {
        bodyLayout->addWidget(notice);
    }

    bodyLayout->addWidget(composerWidget(payload, style), 0, Qt::AlignCenter);
    layout->addWidget(body, 1);

    QLabel *subtitle = label(selection.detailSubtitle, QStringLiteral("caption"));
    subtitle->setParent(detail);
    subtitle->hide();
    return GenericDetailPane { detail, title, subtitle, conversationLayout, true };
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

    return GenericDetailPane { detail, title, subtitle, contentLayout, false };
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
    QWidget *sidebar = sidebarWidget(payload, itemList, style);
    splitter->addWidget(sidebar);
    splitter->addWidget(scrollWrapped(detailPane.view));
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);
    QList<int> splitSizes;
    splitSizes << intValue(payload, "sidebarWidth", 320) << intValue(payload, "detailWidth", 720);
    splitter->setSizes(splitSizes);
    rootLayout->addWidget(splitter);

    for (QPushButton *button : sidebar->findChildren<QPushButton *>()) {
        const QString navigationAction = button->property("navigationAction").toString();
        if (navigationAction == QStringLiteral("settings")) {
            QObject::connect(button, &QPushButton::clicked, [&]() {
                const bool blocked = itemList->blockSignals(true);
                itemList->setCurrentRow(-1);
                itemList->blockSignals(blocked);
                updateChatSelectionDots(itemList);
                populateSettingsContent(detailPane.contentLayout, payload, style);
            });
        }
    }

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
