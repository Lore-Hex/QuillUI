#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QComboBox>
#include <QDragEnterEvent>
#include <QDragLeaveEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QFileInfo>
#include <QFrame>
#include <QHBoxLayout>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLineEdit>
#include <QList>
#include <QListWidget>
#include <QListWidgetItem>
#include <QMimeData>
#include <QObject>
#include <QPainter>
#include <QPaintEvent>
#include <QPen>
#include <QPlainTextEdit>
#include <QPixmap>
#include <QPointF>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollArea>
#include <QSize>
#include <QSignalBlocker>
#include <QSplitter>
#include <QString>
#include <QStringList>
#include <QStyle>
#include <QTimer>
#include <QUrl>
#include <QVBoxLayout>
#include <QWidget>
#include <functional>

namespace {

using QuillQtWidgets::clearLayout;
using QuillQtWidgets::cssPixels;
using QuillQtWidgets::label;
using QuillQtWidgets::refreshStyle;
using QuillQtWidgets::scrollAreaToBottomLater;
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

QIcon themedActionIcon(const QString &themeName, QStyle::StandardPixmap fallback) {
    return QIcon::fromTheme(themeName, QApplication::style()->standardIcon(fallback));
}

QIcon newChatButtonIcon() {
    return themedActionIcon(QStringLiteral("document-new-symbolic"), QStyle::SP_FileIcon);
}

QIcon attachButtonIcon() {
    return themedActionIcon(QStringLiteral("folder-new-symbolic"), QStyle::SP_FileDialogNewFolder);
}

QIcon dropTargetIcon() {
    return attachButtonIcon();
}

QIcon sendButtonIcon(bool isLoading) {
    return isLoading
        ? themedActionIcon(QStringLiteral("process-stop-symbolic"), QStyle::SP_MediaStop)
        : themedActionIcon(QStringLiteral("go-next-symbolic"), QStyle::SP_MediaPlay);
}

int buttonIconSize(const QJsonObject &style) {
    return intValue(style, "actionButtonIconSize", 16);
}

void applyButtonIconSize(QPushButton *button, const QJsonObject &style) {
    const int iconSize = buttonIconSize(style);
    button->setIconSize(QSize(iconSize, iconSize));
}

void updateSendButtonPresentation(
    QPushButton *button,
    bool isLoading,
    const QString &sendTitle,
    const QString &stopTitle
) {
    button->setProperty("loading", isLoading);
    button->setText(isLoading ? stopTitle : sendTitle);
    button->setIcon(sendButtonIcon(isLoading));
}

class LoadingSpinner final : public QWidget {
public:
    explicit LoadingSpinner(const QJsonObject &style, QWidget *parent = nullptr)
        : QWidget(parent),
          color(styleValue(style, "primaryColor", "#315B7D")) {
        setObjectName(QStringLiteral("loadingSpinner"));
        const int spinnerSize = intValue(style, "loadingSpinnerSize", 16);
        setFixedSize(spinnerSize, spinnerSize);
        timer.setInterval(90);
        QObject::connect(&timer, &QTimer::timeout, this, [this]() {
            rotationDegrees = (rotationDegrees + 30) % 360;
            update();
        });
        timer.start();
    }

protected:
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing, true);
        const double side = width() < height() ? width() : height();
        const double outerRadius = side / 2.0 - 1.0;
        const double innerRadius = outerRadius * 0.48;
        const QPointF center(width() / 2.0, height() / 2.0);

        for (int index = 0; index < 12; ++index) {
            QColor segmentColor = color;
            segmentColor.setAlpha(48 + index * 17);
            QPen segmentPen(segmentColor, 2.0, Qt::SolidLine, Qt::RoundCap);
            painter.setPen(segmentPen);
            painter.save();
            painter.translate(center);
            painter.rotate(rotationDegrees + index * 30);
            painter.drawLine(
                QPointF(0.0, -innerRadius),
                QPointF(0.0, -outerRadius)
            );
            painter.restore();
        }
    }

private:
    QColor color;
    QTimer timer;
    int rotationDegrees = 0;
};

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
    const QString quoteRule = styleValue(style, "quoteRuleColor", "#8AA5B7");
    const QString codeBlock = styleValue(style, "codeBlockColor", "#EEF3F4");
    const QString divider = styleValue(style, "dividerColor", "#D8DDD5");
    const QString cardBorder = styleValue(style, "cardBorderColor", "#E0E5DD");
    const QString messageBorder = styleValue(style, "messageBorderColor", "#D4DFE8");
    const QString controlBorder = styleValue(style, "controlBorderColor", "#CDD5CA");
    const QString dropTargetBorder = styleValue(style, "dropTargetBorderColor", "#C8DED3");
    const QString disabledButtonBackground = styleValue(style, "disabledButtonBackgroundColor", "#AAB5BE");
    const QString disabledButtonForeground = styleValue(style, "disabledButtonForegroundColor", "#F4F6F7");
    const QString disabledText = styleValue(style, "disabledTextColor", "#9CA6AD");
    const QString rootFontSize = cssPixels(style, "rootFontSize", 14);
    const QString appTitleFontSize = cssPixels(style, "appTitleFontSize", 26);
    const QString appTitleFontWeight = QString::number(intValue(style, "appTitleFontWeight", 700));
    const QString captionFontSize = cssPixels(style, "captionFontSize", 12);
    const QString sectionTitleFontSize = cssPixels(style, "sectionTitleFontSize", 15);
    const QString sectionTitleFontWeight = QString::number(intValue(style, "sectionTitleFontWeight", 700));
    const QString currentTitleFontSize = cssPixels(style, "currentTitleFontSize", 20);
    const QString currentTitleFontWeight = QString::number(intValue(style, "currentTitleFontWeight", 650));
    const QString messageBodyFontSize = cssPixels(style, "messageBodyFontSize", 14);
    const QString markdownHeading1FontSize = cssPixels(style, "markdownHeading1FontSize", 17);
    const QString markdownHeading2FontSize = cssPixels(style, "markdownHeading2FontSize", 15);
    const QString markdownHeadingFontSize = cssPixels(style, "markdownHeadingFontSize", 14);
    const QString markdownHeadingFontWeight = QString::number(intValue(style, "markdownHeadingFontWeight", 650));
    const QString markdownCodeLanguageFontSize = cssPixels(style, "markdownCodeLanguageFontSize", 11);
    const QString markdownCodeFontSize = cssPixels(style, "markdownCodeFontSize", 13);
    const QString attachmentNameFontSize = cssPixels(style, "attachmentNameFontSize", 12);
    const QString attachmentSizeFontSize = cssPixels(style, "attachmentSizeFontSize", 11);
    const QString conversationTitleFontSize = cssPixels(style, "conversationTitleFontSize", 15);
    const QString conversationTitleFontWeight = QString::number(intValue(style, "conversationTitleFontWeight", 700));
    const QString conversationPreviewFontSize = cssPixels(style, "conversationPreviewFontSize", 12);
    const QString warningTextFontSize = cssPixels(style, "warningTextFontSize", 12);
    const QString chipRemoveButtonFontWeight = QString::number(intValue(style, "chipRemoveButtonFontWeight", 700));
    const QString statusDotSize = cssPixels(style, "statusDotSize", 9);
    const QString statusDotRadius = cssPixels(style, "statusDotRadius", 9);
    const QString conversationRowRadius = cssPixels(style, "conversationRowRadius", 8);
    const QString conversationListItemRadius = cssPixels(style, "conversationListItemRadius", 8);
    const QString conversationListItemVerticalMargin = cssPixels(style, "conversationListItemVerticalMargin", 2);
    const QString conversationListItemPadding = cssPixels(style, "conversationListItemPadding", 8);
    const QString emptyHistoryRadius = cssPixels(style, "emptyHistoryRadius", 8);
    const QString messageBubbleRadius = cssPixels(style, "messageBubbleRadius", 10);
    const QString attachmentChipRadius = cssPixels(style, "attachmentChipRadius", 8);
    const QString markdownQuoteRuleRadius = cssPixels(style, "markdownQuoteRuleRadius", 1);
    const QString markdownCodeBlockRadius = cssPixels(style, "markdownCodeBlockRadius", 7);
    const QString dropTargetRadius = cssPixels(style, "dropTargetRadius", 8);
    const QString promptButtonPadding = cssPixels(style, "promptButtonPadding", 12);
    const QString promptButtonRadius = cssPixels(style, "promptButtonRadius", 8);
    const QString primaryButtonVerticalPadding = cssPixels(style, "primaryButtonVerticalPadding", 12);
    const QString primaryButtonHorizontalPadding = cssPixels(style, "primaryButtonHorizontalPadding", 12);
    const QString primaryButtonRadius = cssPixels(style, "primaryButtonRadius", 8);
    const QString secondaryButtonVerticalPadding = cssPixels(style, "secondaryButtonVerticalPadding", 7);
    const QString secondaryButtonHorizontalPadding = cssPixels(style, "secondaryButtonHorizontalPadding", 10);
    const QString secondaryButtonRadius = cssPixels(style, "secondaryButtonRadius", 7);
    const QString chipRemoveButtonVerticalPadding = cssPixels(style, "chipRemoveButtonVerticalPadding", 2);
    const QString chipRemoveButtonHorizontalPadding = cssPixels(style, "chipRemoveButtonHorizontalPadding", 6);
    const QString controlPadding = cssPixels(style, "controlPadding", 7);
    const QString controlRadius = cssPixels(style, "controlRadius", 7);

    QString sheet = QStringLiteral(R"(
        QWidget#enchantedRoot { background: %1; color: %2; font-size: %3; }
        QFrame#chatHeader, QFrame#composer { background: %4; }
        QLabel#caption, QLabel#fieldLabel, QLabel#statusText, QLabel#messageRole { color: %5; font-size: %6; }
    )")
        .arg(canvas, ink, rootFontSize, header, muted, captionFontSize);

    sheet += QStringLiteral(R"(
        QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }
        QLabel#sectionTitle { color: %1; font-size: %4; font-weight: %5; }
        QLabel#currentTitle { color: %1; font-size: %6; font-weight: %7; }
        QLabel#messageText, QLabel#markdownParagraph { color: %1; font-size: %8; }
        QLabel#messageUserText { color: white; font-size: %8; }
    )")
        .arg(
            ink,
            appTitleFontSize,
            appTitleFontWeight,
            sectionTitleFontSize,
            sectionTitleFontWeight,
            currentTitleFontSize,
            currentTitleFontWeight,
            messageBodyFontSize
        );

    sheet += QStringLiteral(R"(
        QLabel#markdownHeading1 { color: %1; font-size: %2; font-weight: %5; }
        QLabel#markdownHeading2 { color: %1; font-size: %3; font-weight: %5; }
        QLabel#markdownHeading { color: %1; font-size: %4; font-weight: %5; }
        QLabel#markdownBullet, QLabel#markdownNumber { color: %6; font-size: %4; font-weight: %5; }
        QLabel#markdownQuote { color: %7; font-size: %4; }
        QLabel#markdownCodeLanguage { color: %7; font-size: %8; font-weight: %5; }
        QLabel#markdownCodeText { color: %1; font-family: monospace; font-size: %9; }
    )")
        .arg(
            ink,
            markdownHeading1FontSize,
            markdownHeading2FontSize,
            markdownHeadingFontSize,
            markdownHeadingFontWeight,
            primary,
            muted,
            markdownCodeLanguageFontSize,
            markdownCodeFontSize
        );

    sheet += QStringLiteral(R"(
        QScrollArea#attachmentScrollArea, QWidget#attachmentChipList { background: transparent; border: 0; }
        QLabel#attachmentName { color: %1; font-size: %2; }
        QLabel#attachmentSize { color: %3; font-size: %4; }
    )")
        .arg(ink, attachmentNameFontSize, muted, attachmentSizeFontSize);

    sheet += QStringLiteral(R"(
        QFrame#sidebar { background: %1; border-right: 1px solid %2; }
        QLabel#messageUserRole { color: %3; font-size: %4; }
    )")
        .arg(sidebar, divider, selected, captionFontSize);

    sheet += QStringLiteral(R"(
        QFrame#emptyHistory { background: %1; border: 1px solid %2; border-radius: %3; }
        QFrame#messageAssistant { background: %1; border: 1px solid %2; border-radius: %4; }
        QFrame#messageSystem { background: %5; border: 1px solid %6; border-radius: %4; }
        QFrame#messageUser { background: %7; border: 1px solid %6; border-radius: %4; }
        QFrame#attachmentChip { background: %1; border: 1px solid %2; border-radius: %8; }
    )")
        .arg(card, cardBorder, emptyHistoryRadius, messageBubbleRadius, system, messageBorder, primary, attachmentChipRadius);

    sheet += QStringLiteral(R"(
        QPushButton#primaryButton, QPushButton#sendButton { background: %1; color: white; border: 0; border-radius: %2; padding: %3 %4; text-align: left; }
        QPushButton#sendButton[loading="true"] { background: %5; }
        QPushButton#sendButton:disabled { background: %6; color: %7; }
    )")
        .arg(
            primary,
            primaryButtonRadius,
            primaryButtonVerticalPadding,
            primaryButtonHorizontalPadding,
            warning,
            disabledButtonBackground,
            disabledButtonForeground
        );

    sheet += QStringLiteral(R"(
        QPushButton#secondaryButton { background: transparent; color: %1; border: 1px solid %2; border-radius: %3; padding: %4 %5; text-align: left; }
        QPushButton#secondaryButton:disabled { color: %6; border: 1px solid %7; }
    )")
        .arg(ink)
        .arg(controlBorder)
        .arg(secondaryButtonRadius)
        .arg(secondaryButtonVerticalPadding)
        .arg(secondaryButtonHorizontalPadding)
        .arg(disabledText)
        .arg(divider);

    sheet += QStringLiteral(R"(
        QPushButton#chipRemoveButton { background: transparent; color: %1; border: 0; padding: %2 %3; font-weight: %4; }
    )")
        .arg(muted, chipRemoveButtonVerticalPadding, chipRemoveButtonHorizontalPadding, chipRemoveButtonFontWeight);

    sheet += QStringLiteral(R"(
        QPushButton#promptButton { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; text-align: left; }
    )")
        .arg(card, ink, cardBorder, promptButtonRadius, promptButtonPadding);

    sheet += QStringLiteral(R"(
        QFrame#markdownQuoteRule { background: %1; border-radius: %3; }
        QFrame#markdownCodeBlock { background: %2; border-radius: %4; }
    )")
        .arg(quoteRule, codeBlock, markdownQuoteRuleRadius, markdownCodeBlockRadius);

    sheet += QStringLiteral(R"(
        QListWidget#conversationList { background: transparent; border: 0; outline: 0; }
        QListWidget#conversationList::item { border-radius: %1; margin: %2 0; padding: %3; }
    )")
        .arg(conversationListItemRadius, conversationListItemVerticalMargin, conversationListItemPadding);

    sheet += QStringLiteral(R"(
        QListWidget#conversationList::item:selected { background: transparent; color: %2; }
        QFrame#conversationRow { background: %3; border-radius: %6; }
        QFrame#conversationRow[active="true"] { background: %5; }
        QLabel#conversationTitle { color: %2; font-size: %7; font-weight: %8; }
        QLabel#conversationTitle[active="true"] { color: white; }
        QLabel#conversationPreview { color: %4; font-size: %9; }
        QLabel#conversationPreview[active="true"] { color: %1; }
    )")
        .arg(
            selected,
            ink,
            card,
            muted,
            primary,
            conversationRowRadius,
            conversationTitleFontSize,
            conversationTitleFontWeight,
            conversationPreviewFontSize
        );

    sheet += QStringLiteral(R"(
        QFrame#statusDot, QFrame#statusDotWarning { min-width: %1; max-width: %1; min-height: %1; max-height: %1; border-radius: %2; }
        QFrame#statusDot { background: %3; }
        QFrame#statusDotWarning { background: %4; }
        QLabel#warningText { color: %4; font-size: %6; }
        QScrollArea { background: %5; border: 0; }
    )")
        .arg(statusDotSize, statusDotRadius, success, warning, canvas, warningTextFontSize);

    sheet += QStringLiteral(R"(
        QFrame#dropTarget { background: transparent; border: 0; }
        QFrame#dropTarget[dragActive="true"] { background: transparent; border: 0; }
        QFrame#dropTargetHint { background: %1; border: 1px solid %2; border-radius: %5; }
        QLabel#dropTargetLabel { color: %3; font-size: %6; }
        QSplitter::handle { background: %4; }
    )")
        .arg(dropTarget, dropTargetBorder, primary, divider, dropTargetRadius, captionFontSize);

    sheet += QStringLiteral(R"(
        QLineEdit, QComboBox, QPlainTextEdit { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; }
    )")
        .arg(card, ink, controlBorder, controlRadius, controlPadding);

    return sheet;
}

QFrame *conversationRowWidget(const QJsonObject &conversation, const QJsonObject &style) {
    QFrame *row = QuillQtWidgets::frame(QStringLiteral("conversationRow"));
    row->setProperty("active", false);
    QVBoxLayout *layout = new QVBoxLayout(row);
    const int conversationRowPadding = intValue(style, "conversationRowPadding", 11);
    layout->setContentsMargins(
        conversationRowPadding,
        conversationRowPadding,
        conversationRowPadding,
        conversationRowPadding
    );
    layout->setSpacing(intValue(style, "conversationRowSpacing", 5));

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

QFrame *emptyHistoryWidget(const QString &title, const QString &subtitle, const QJsonObject &style) {
    QFrame *card = QuillQtWidgets::frame(QStringLiteral("emptyHistory"));
    QVBoxLayout *layout = new QVBoxLayout(card);
    const int emptyHistoryPadding = intValue(style, "emptyHistoryPadding", 12);
    layout->setContentsMargins(
        emptyHistoryPadding,
        emptyHistoryPadding,
        emptyHistoryPadding,
        emptyHistoryPadding
    );
    layout->setSpacing(intValue(style, "emptyHistorySpacing", 8));
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

enum class MarkdownBlockKind {
    Paragraph,
    Heading,
    UnorderedListItem,
    OrderedListItem,
    Quote,
    CodeBlock
};

struct MarkdownBlock {
    MarkdownBlockKind kind = MarkdownBlockKind::Paragraph;
    QString text;
    int level = 0;
    int number = 0;
    QString language;
};

struct MarkdownFence {
    QString delimiter;
    QString language;
    bool isActive = false;
};

QString cleanMarkdownInline(QString text) {
    static const QRegularExpression linkPattern(QStringLiteral("\\[([^\\]]+)\\]\\(([^)]+)\\)"));
    text.replace(linkPattern, QStringLiteral("\\1 (\\2)"));

    const QStringList markers = {
        QStringLiteral("**"),
        QStringLiteral("__"),
        QStringLiteral("`"),
        QStringLiteral("~~")
    };
    for (const QString &marker : markers) {
        text.replace(marker, QString());
    }

    return text.trimmed();
}

bool beginMarkdownFence(const QString &rawLine, MarkdownFence *fence) {
    const QString line = rawLine.trimmed();
    QString delimiter;
    if (line.startsWith(QStringLiteral("```"))) {
        delimiter = QStringLiteral("```");
    } else if (line.startsWith(QStringLiteral("~~~"))) {
        delimiter = QStringLiteral("~~~");
    } else {
        return false;
    }

    if (fence != nullptr) {
        fence->delimiter = delimiter;
        fence->language = line.mid(delimiter.size()).trimmed();
        fence->isActive = true;
    }
    return true;
}

bool closesMarkdownFence(const QString &rawLine, const MarkdownFence &fence) {
    return fence.isActive && rawLine.trimmed().startsWith(fence.delimiter);
}

bool parseHeadingLine(const QString &line, int *level, QString *text) {
    int markerCount = 0;
    while (markerCount < line.size() && line.at(markerCount) == QLatin1Char('#')) {
        markerCount += 1;
    }

    if (markerCount < 1 || markerCount > 6 || markerCount >= line.size()) {
        return false;
    }
    if (!line.at(markerCount).isSpace()) {
        return false;
    }

    if (level != nullptr) {
        *level = markerCount;
    }
    if (text != nullptr) {
        *text = cleanMarkdownInline(line.mid(markerCount).trimmed());
    }
    return true;
}

bool parseUnorderedListLine(const QString &line, QString *text) {
    if (line.size() < 3) {
        return false;
    }

    const QChar marker = line.at(0);
    if (marker != QLatin1Char('-') && marker != QLatin1Char('*') && marker != QLatin1Char('+')) {
        return false;
    }
    if (!line.at(1).isSpace()) {
        return false;
    }

    if (text != nullptr) {
        *text = cleanMarkdownInline(line.mid(2).trimmed());
    }
    return true;
}

bool parseOrderedListLine(const QString &line, int *number, QString *text) {
    int index = 0;
    while (index < line.size() && line.at(index).isDigit()) {
        index += 1;
    }
    if (index == 0 || index >= line.size() || line.at(index) != QLatin1Char('.')) {
        return false;
    }

    const int textStart = index + 1;
    if (textStart >= line.size() || !line.at(textStart).isSpace()) {
        return false;
    }

    bool ok = false;
    const int parsedNumber = line.left(index).toInt(&ok);
    if (!ok) {
        return false;
    }

    if (number != nullptr) {
        *number = parsedNumber;
    }
    if (text != nullptr) {
        *text = cleanMarkdownInline(line.mid(textStart + 1).trimmed());
    }
    return true;
}

bool parseQuoteLine(const QString &line, QString *text) {
    if (!line.startsWith(QLatin1Char('>'))) {
        return false;
    }
    if (text != nullptr) {
        *text = cleanMarkdownInline(line.mid(1).trimmed());
    }
    return true;
}

QList<MarkdownBlock> parseMarkdownBlocks(const QString &markdown) {
    QList<MarkdownBlock> blocks;
    QString normalized = markdown;
    normalized.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
    normalized.replace(QLatin1Char('\r'), QLatin1Char('\n'));

    QStringList paragraphLines;
    QStringList codeLines;
    MarkdownFence activeFence;

    auto appendBlock = [&](MarkdownBlockKind kind, const QString &text, int level = 0, int number = 0, const QString &language = QString()) {
        MarkdownBlock block;
        block.kind = kind;
        block.text = text;
        block.level = level;
        block.number = number;
        block.language = language;
        blocks.append(block);
    };

    auto flushParagraph = [&]() {
        if (paragraphLines.isEmpty()) {
            return;
        }

        const QString text = cleanMarkdownInline(paragraphLines.join(QStringLiteral(" ")));
        paragraphLines.clear();
        if (!text.isEmpty()) {
            appendBlock(MarkdownBlockKind::Paragraph, text);
        }
    };

    auto flushCodeBlock = [&]() {
        appendBlock(MarkdownBlockKind::CodeBlock, codeLines.join(QStringLiteral("\n")), 0, 0, activeFence.language);
        codeLines.clear();
        activeFence = MarkdownFence();
    };

    const QStringList lines = normalized.split(QLatin1Char('\n'));
    for (const QString &rawLine : lines) {
        if (activeFence.isActive) {
            if (closesMarkdownFence(rawLine, activeFence)) {
                flushCodeBlock();
            } else {
                codeLines.append(rawLine);
            }
            continue;
        }

        MarkdownFence openingFence;
        if (beginMarkdownFence(rawLine, &openingFence)) {
            flushParagraph();
            activeFence = openingFence;
            continue;
        }

        const QString line = rawLine.trimmed();
        if (line.isEmpty()) {
            flushParagraph();
            continue;
        }

        int level = 0;
        int number = 0;
        QString text;
        if (parseHeadingLine(line, &level, &text)) {
            flushParagraph();
            appendBlock(MarkdownBlockKind::Heading, text, level);
        } else if (parseUnorderedListLine(line, &text)) {
            flushParagraph();
            appendBlock(MarkdownBlockKind::UnorderedListItem, text);
        } else if (parseOrderedListLine(line, &number, &text)) {
            flushParagraph();
            appendBlock(MarkdownBlockKind::OrderedListItem, text, 0, number);
        } else if (parseQuoteLine(line, &text)) {
            flushParagraph();
            appendBlock(MarkdownBlockKind::Quote, text);
        } else {
            paragraphLines.append(line);
        }
    }

    if (activeFence.isActive) {
        flushCodeBlock();
    } else {
        flushParagraph();
    }

    if (blocks.isEmpty()) {
        appendBlock(MarkdownBlockKind::Paragraph, QString());
    }
    return blocks;
}

QLabel *markdownLabel(const QString &text, const QString &objectName) {
    QLabel *view = label(text, objectName);
    view->setTextInteractionFlags(Qt::TextSelectableByMouse);
    return view;
}

QWidget *markdownListItemWidget(
    const QString &marker,
    const QString &text,
    const QString &markerObjectName,
    const QJsonObject &style
) {
    QWidget *row = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(row);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(intValue(style, "markdownListItemSpacing", 8));

    QLabel *markerLabel = label(marker, markerObjectName);
    if (markerObjectName == QStringLiteral("markdownNumber")) {
        markerLabel->setFixedWidth(intValue(style, "markdownNumberWidth", 26));
    }
    markerLabel->setAlignment(Qt::AlignTop | Qt::AlignRight);
    layout->addWidget(markerLabel);
    layout->addWidget(markdownLabel(text, QStringLiteral("markdownParagraph")), 1);
    return row;
}

QWidget *markdownQuoteWidget(const QString &text, const QJsonObject &style) {
    QWidget *row = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(row);
    const int verticalPadding = intValue(style, "markdownQuoteVerticalPadding", 2);
    layout->setContentsMargins(0, verticalPadding, 0, verticalPadding);
    layout->setSpacing(intValue(style, "markdownQuoteSpacing", 9));

    QFrame *rule = QuillQtWidgets::frame(QStringLiteral("markdownQuoteRule"));
    rule->setFixedWidth(intValue(style, "markdownQuoteRuleWidth", 3));
    layout->addWidget(rule);
    layout->addWidget(markdownLabel(text, QStringLiteral("markdownQuote")), 1);
    return row;
}

QWidget *markdownCodeBlockWidget(const MarkdownBlock &block, const QJsonObject &style) {
    QFrame *codeBlock = QuillQtWidgets::frame(QStringLiteral("markdownCodeBlock"));
    QVBoxLayout *layout = new QVBoxLayout(codeBlock);
    const int codeBlockPadding = intValue(style, "markdownCodeBlockPadding", 10);
    layout->setContentsMargins(codeBlockPadding, codeBlockPadding, codeBlockPadding, codeBlockPadding);
    layout->setSpacing(intValue(style, "markdownCodeBlockSpacing", 7));

    if (!block.language.isEmpty()) {
        layout->addWidget(markdownLabel(block.language.toUpper(), QStringLiteral("markdownCodeLanguage")));
    }
    layout->addWidget(markdownLabel(block.text.isEmpty() ? QStringLiteral(" ") : block.text, QStringLiteral("markdownCodeText")));
    return codeBlock;
}

void addMarkdownBlocks(QVBoxLayout *layout, const QString &markdown, const QJsonObject &style) {
    const QList<MarkdownBlock> blocks = parseMarkdownBlocks(markdown);
    for (const MarkdownBlock &block : blocks) {
        switch (block.kind) {
        case MarkdownBlockKind::Heading:
            if (block.level == 1) {
                layout->addWidget(markdownLabel(block.text, QStringLiteral("markdownHeading1")));
            } else if (block.level == 2) {
                layout->addWidget(markdownLabel(block.text, QStringLiteral("markdownHeading2")));
            } else {
                layout->addWidget(markdownLabel(block.text, QStringLiteral("markdownHeading")));
            }
            break;
        case MarkdownBlockKind::UnorderedListItem:
            layout->addWidget(markdownListItemWidget(
                QString::fromUtf8("\xE2\x80\xA2"),
                block.text,
                QStringLiteral("markdownBullet"),
                style
            ));
            break;
        case MarkdownBlockKind::OrderedListItem:
            layout->addWidget(markdownListItemWidget(
                QStringLiteral("%1.").arg(block.number),
                block.text,
                QStringLiteral("markdownNumber"),
                style
            ));
            break;
        case MarkdownBlockKind::Quote:
            layout->addWidget(markdownQuoteWidget(block.text, style));
            break;
        case MarkdownBlockKind::CodeBlock:
            layout->addWidget(markdownCodeBlockWidget(block, style));
            break;
        case MarkdownBlockKind::Paragraph:
            layout->addWidget(markdownLabel(block.text, QStringLiteral("markdownParagraph")));
            break;
        }
    }
}

QWidget *markdownMessageWidget(const QString &markdown, const QJsonObject &style) {
    QWidget *container = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(container);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(intValue(style, "markdownBlockSpacing", 9));
    addMarkdownBlocks(layout, markdown, style);
    return container;
}

QString promptCardPrefix() {
    return QString::fromUtf8("\xE2\x98\x85  ");
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
    const QString &selectedConversationID,
    const QJsonObject &style
) {
    list->clear();
    int selectedRow = -1;

    for (const QJsonValue &value : conversations) {
        const QJsonObject conversation = value.toObject();
        QListWidgetItem *item = new QListWidgetItem();
        item->setData(Qt::UserRole, stringValue(conversation, "id"));
        item->setSizeHint(QSize(260, 88));
        list->addItem(item);
        list->setItemWidget(item, conversationRowWidget(conversation, style));
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
    const int messageBubblePadding = intValue(style, "messageBubblePadding", 13);
    layout->setContentsMargins(
        messageBubblePadding,
        messageBubblePadding,
        messageBubblePadding,
        messageBubblePadding
    );
    layout->setSpacing(intValue(style, "messageBubbleSpacing", 7));
    layout->addWidget(label(
        messageRoleTitle(role),
        role == QStringLiteral("user") ? QStringLiteral("messageUserRole") : QStringLiteral("messageRole")
    ));
    if (role == QStringLiteral("user")) {
        layout->addWidget(label(stringValue(message, "content"), QStringLiteral("messageUserText")));
    } else {
        layout->addWidget(markdownMessageWidget(stringValue(message, "content"), style));
    }
    return bubble;
}

void addMessageBubble(QVBoxLayout *messageLayout, const QJsonObject &message, const QJsonObject &style) {
    const bool isUser = stringValue(message, "role") == QStringLiteral("user");
    QHBoxLayout *row = new QHBoxLayout();
    row->setContentsMargins(0, 0, 0, 0);
    row->setSpacing(intValue(style, "messageBubbleRowSpacing", 10));
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
    const QJsonObject &style,
    const QString &title,
    const QString &subtitle,
    const PromptAction &promptAction
) {
    QWidget *emptyState = new QWidget();
    emptyState->setObjectName(QStringLiteral("promptEmptyState"));
    QVBoxLayout *layout = new QVBoxLayout(emptyState);
    const int emptyStatePadding = intValue(style, "emptyStatePadding", 26);
    layout->setContentsMargins(
        emptyStatePadding,
        emptyStatePadding,
        emptyStatePadding,
        emptyStatePadding
    );
    layout->setSpacing(intValue(style, "emptyStateSpacing", 18));
    layout->addWidget(label(title, QStringLiteral("currentTitle")));
    layout->addWidget(label(
        subtitle,
        QStringLiteral("caption")
    ));

    QVBoxLayout *promptList = new QVBoxLayout();
    promptList->setSpacing(intValue(style, "promptListSpacing", 10));
    for (const QJsonValue &value : prompts) {
        const QString prompt = value.toString();
        QPushButton *button = new QPushButton(QStringLiteral("%1%2").arg(promptCardPrefix(), prompt));
        button->setObjectName(QStringLiteral("promptButton"));
        button->setMinimumHeight(intValue(style, "promptButtonMinHeight", 48));
        button->setFixedWidth(intValue(style, "promptButtonWidth", 620));
        QObject::connect(button, &QPushButton::clicked, [prompt, promptAction]() {
            promptAction(prompt);
        });
        promptList->addWidget(button);
    }

    layout->addLayout(promptList);
    emptyState->setMaximumWidth(intValue(style, "emptyStateMaxWidth", 680));
    messageLayout->addWidget(emptyState);
    messageLayout->addStretch(1);
}

QWidget *loadingRowWidget(const QString &status, const QJsonObject &style) {
    QWidget *row = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(row);
    layout->setContentsMargins(0, intValue(style, "loadingTopPadding", 8), 0, 0);
    layout->setSpacing(intValue(style, "loadingRowSpacing", 8));

    layout->addWidget(new LoadingSpinner(style), 0, Qt::AlignVCenter);
    layout->addWidget(label(status, QStringLiteral("caption")), 0, Qt::AlignVCenter);
    layout->addStretch(1);
    return row;
}

void renderMessages(
    QVBoxLayout *messageLayout,
    const QJsonArray &messages,
    const QJsonArray &prompts,
    const QJsonObject &style,
    const QString &emptyStateTitle,
    const QString &emptyStateSubtitle,
    const PromptAction &promptAction,
    const QString &status,
    bool isLoading
) {
    clearLayout(messageLayout);
    if (messages.isEmpty()) {
        addPromptCards(messageLayout, prompts, style, emptyStateTitle, emptyStateSubtitle, promptAction);
        if (isLoading) {
            messageLayout->addWidget(loadingRowWidget(status, style));
        }
        return;
    }

    for (const QJsonValue &value : messages) {
        addMessageBubble(messageLayout, value.toObject(), style);
    }
    if (isLoading) {
        messageLayout->addWidget(loadingRowWidget(status, style));
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

QStringList normalizedAttachmentPaths(const QStringList &rawPaths) {
    QStringList normalizedPaths;
    for (const QString &rawPath : rawPaths) {
        const QString trimmedPath = rawPath.trimmed();
        if (attachmentDisplayName(trimmedPath).isEmpty() || normalizedPaths.contains(trimmedPath)) {
            continue;
        }

        normalizedPaths.append(trimmedPath);
    }

    return normalizedPaths;
}

QStringList attachmentPathsFromMimeData(const QMimeData *mimeData) {
    QStringList paths;
    if (mimeData == nullptr || !mimeData->hasUrls()) {
        return paths;
    }

    for (const QUrl &url : mimeData->urls()) {
        if (url.isLocalFile()) {
            paths.append(url.toLocalFile());
        }
    }

    return normalizedAttachmentPaths(paths);
}

class AttachmentDropFrame final : public QFrame {
public:
    using DropHandler = std::function<void(const QStringList &)>;

    explicit AttachmentDropFrame(QWidget *parent = nullptr)
        : QFrame(parent)
    {
        setObjectName(QStringLiteral("dropTarget"));
        setAcceptDrops(true);
        setProperty("dragActive", false);
    }

    void setDropHandler(const DropHandler &handler) {
        dropHandler = handler;
    }

    void setDropHint(QWidget *hint) {
        dropHint = hint;
        if (dropHint != nullptr) {
            dropHint->setVisible(property("dragActive").toBool());
        }
    }

protected:
    void dragEnterEvent(QDragEnterEvent *event) override {
        handleDragMove(event);
    }

    void dragMoveEvent(QDragMoveEvent *event) override {
        handleDragMove(event);
    }

    void dragLeaveEvent(QDragLeaveEvent *event) override {
        setDragActive(false);
        QFrame::dragLeaveEvent(event);
    }

    void dropEvent(QDropEvent *event) override {
        setDragActive(false);
        const QStringList paths = attachmentPathsFromMimeData(event->mimeData());
        if (paths.isEmpty()) {
            event->ignore();
            return;
        }

        if (dropHandler) {
            dropHandler(paths);
        }
        event->acceptProposedAction();
    }

private:
    void handleDragMove(QDragMoveEvent *event) {
        if (event == nullptr) {
            return;
        }

        const bool acceptsDrop = !attachmentPathsFromMimeData(event->mimeData()).isEmpty();
        setDragActive(acceptsDrop);
        if (acceptsDrop) {
            event->acceptProposedAction();
        } else {
            event->ignore();
        }
    }

    void setDragActive(bool active) {
        if (property("dragActive").toBool() == active) {
            return;
        }

        setProperty("dragActive", active);
        if (dropHint != nullptr) {
            dropHint->setVisible(active);
        }
        refreshStyle(this);
    }

    DropHandler dropHandler;
    QWidget *dropHint = nullptr;
};

QString attachmentSummaryForPaths(const QStringList &rawPaths) {
    QStringList summaryLines;
    for (const QString &path : normalizedAttachmentPaths(rawPaths)) {
        summaryLines.append(QStringLiteral("- %1").arg(attachmentDisplayName(path)));
    }

    return summaryLines.join(QStringLiteral("\n"));
}

QString formattedAttachmentByteCount(qint64 byteCount) {
    if (byteCount < 1024) {
        return QStringLiteral("%1 bytes").arg(byteCount);
    }

    const QStringList units = {
        QStringLiteral("KB"),
        QStringLiteral("MB"),
        QStringLiteral("GB"),
        QStringLiteral("TB")
    };
    double value = double(byteCount) / 1024.0;
    int unitIndex = 0;
    while (value >= 1024.0 && unitIndex < units.count() - 1) {
        value /= 1024.0;
        unitIndex += 1;
    }

    return QStringLiteral("%1 %2").arg(QString::number(value, 'f', 1), units.at(unitIndex));
}

QString attachmentDisplaySize(const QString &rawPath) {
    const QFileInfo fileInfo(rawPath.trimmed());
    if (!fileInfo.exists() || !fileInfo.isFile()) {
        return QString();
    }

    return formattedAttachmentByteCount(fileInfo.size());
}

QString attachmentReadyStatus(int count) {
    return count == 1
        ? QStringLiteral("1 image ready to send")
        : QStringLiteral("%1 images ready to send").arg(count);
}

QString attachmentDisplayContent(
    const QString &rawPrompt,
    const QString &attachmentSummary,
    const QString &defaultPrompt,
    const QString &summaryTitle
) {
    const QString trimmedPrompt = rawPrompt.trimmed();
    if (attachmentSummary.isEmpty()) {
        return trimmedPrompt;
    }

    const QString prompt = trimmedPrompt.isEmpty() ? defaultPrompt : trimmedPrompt;
    return QStringLiteral("%1\n\n%2\n%3").arg(prompt, summaryTitle, attachmentSummary);
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
    bool isLoading = boolValue(payload, "isLoading", false);
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
    const int sidebarPadding = intValue(style, "sidebarPadding", 18);
    sidebarLayout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding);
    sidebarLayout->setSpacing(intValue(style, "sidebarSpacing", 14));

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
    newChatButton->setIcon(newChatButtonIcon());
    applyButtonIconSize(newChatButton, style);
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
    statusLayout->setSpacing(intValue(style, "statusRowSpacing", 8));
    QFrame *statusDot = QuillQtWidgets::frame(
        models.isEmpty() ? QStringLiteral("statusDotWarning") : QStringLiteral("statusDot")
    );
    const int statusDotSize = intValue(style, "statusDotSize", 9);
    statusDot->setFixedSize(statusDotSize, statusDotSize);
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
        stringValue(payload, "emptyHistorySubtitle", QStringLiteral("Start a chat and it will be saved locally.")),
        style
    );
    emptyHistory->setVisible(conversations.isEmpty());
    sidebarLayout->addWidget(emptyHistory);
    QListWidget *conversationList = new QListWidget();
    conversationList->setObjectName(QStringLiteral("conversationList"));
    populateConversations(
        conversationList,
        conversations,
        selectedConversationID,
        style
    );
    conversationList->setVisible(!conversations.isEmpty());
    sidebarLayout->addWidget(conversationList, 1);

    QHBoxLayout *conversationActions = new QHBoxLayout();
    conversationActions->setSpacing(intValue(style, "conversationActionsSpacing", 8));
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
    headerLayout->setSpacing(intValue(style, "headerSpacing", 12));
    QVBoxLayout *titleLayout = new QVBoxLayout();
    titleLayout->setSpacing(intValue(style, "headerTitleSpacing", 4));
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
    const int headerTitleWidth = intValue(style, "headerTitleWidth", 560);
    currentTitle->setFixedWidth(headerTitleWidth);
    modelStatus->setFixedWidth(headerTitleWidth);
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
    messageLayout->setSpacing(intValue(style, "messageSpacing", 14));
    scrollArea->setWidget(transcript);
    chatLayout->addWidget(scrollArea, 1);
    auto scrollTranscriptToBottom = [scrollArea]() {
        scrollAreaToBottomLater(scrollArea);
    };

    QFrame *composer = QuillQtWidgets::frame(QStringLiteral("composer"));
    QVBoxLayout *composerLayout = new QVBoxLayout(composer);
    const int composerPadding = intValue(style, "composerPadding", 18);
    composerLayout->setContentsMargins(composerPadding, composerPadding, composerPadding, composerPadding);
    composerLayout->setSpacing(intValue(style, "composerSpacing", 10));

    AttachmentDropFrame *dropTarget = new AttachmentDropFrame();
    QVBoxLayout *dropTargetLayout = new QVBoxLayout(dropTarget);
    dropTargetLayout->setContentsMargins(0, 0, 0, 0);
    dropTargetLayout->setSpacing(intValue(style, "attachmentInputSpacing", 8));

    QFrame *dropHint = QuillQtWidgets::frame(QStringLiteral("dropTargetHint"));
    QHBoxLayout *dropHintLayout = new QHBoxLayout(dropHint);
    const int dropTargetPadding = intValue(style, "dropTargetPadding", 8);
    dropHintLayout->setContentsMargins(
        dropTargetPadding,
        dropTargetPadding,
        dropTargetPadding,
        dropTargetPadding
    );
    dropHintLayout->setSpacing(intValue(style, "attachmentInputSpacing", 8));
    const int dropTargetIconSize = buttonIconSize(style);
    QLabel *dropTargetIconLabel = new QLabel();
    dropTargetIconLabel->setObjectName(QStringLiteral("dropTargetIcon"));
    dropTargetIconLabel->setPixmap(dropTargetIcon().pixmap(dropTargetIconSize, dropTargetIconSize));
    dropTargetIconLabel->setFixedSize(dropTargetIconSize, dropTargetIconSize);
    QLabel *dropTargetLabel = label(
        stringValue(payload, "dropTargetTitle", QStringLiteral("Drop image files to attach")),
        QStringLiteral("dropTargetLabel")
    );
    dropHintLayout->addWidget(dropTargetIconLabel);
    dropHintLayout->addWidget(dropTargetLabel);
    dropHintLayout->addStretch(1);
    dropHint->setVisible(false);
    dropTarget->setDropHint(dropHint);
    dropTargetLayout->addWidget(dropHint);

    QHBoxLayout *dropLayout = new QHBoxLayout();
    dropLayout->setContentsMargins(0, 0, 0, 0);
    dropLayout->setSpacing(intValue(style, "attachmentInputSpacing", 8));
    QLineEdit *attachmentPath = new QLineEdit();
    attachmentPath->setPlaceholderText(stringValue(
        payload,
        "attachmentPlaceholder",
        QStringLiteral("Image path or drop files here")
    ));
    attachmentPath->setAcceptDrops(false);
    QPushButton *attachButton = new QPushButton(stringValue(payload, "attachTitle", QStringLiteral("Attach")));
    attachButton->setObjectName(QStringLiteral("secondaryButton"));
    attachButton->setIcon(attachButtonIcon());
    applyButtonIconSize(attachButton, style);
    QPushButton *clearAttachmentsButton = new QPushButton(stringValue(payload, "clearAttachmentsTitle", QStringLiteral("Clear")));
    clearAttachmentsButton->setObjectName(QStringLiteral("secondaryButton"));
    dropLayout->addWidget(attachmentPath, 1);
    dropLayout->addWidget(attachButton);
    dropLayout->addWidget(clearAttachmentsButton);
    dropTargetLayout->addLayout(dropLayout);
    composerLayout->addWidget(dropTarget);

    QFrame *attachmentTray = QuillQtWidgets::frame(QStringLiteral("attachmentTray"));
    QVBoxLayout *attachmentTrayLayout = new QVBoxLayout(attachmentTray);
    attachmentTrayLayout->setContentsMargins(0, 0, 0, 0);
    attachmentTrayLayout->setSpacing(intValue(style, "attachmentTraySpacing", 7));
    attachmentTrayLayout->addWidget(fieldLabel(stringValue(payload, "attachmentsTitle", QStringLiteral("Attachments"))));
    QScrollArea *attachmentScrollArea = new QScrollArea();
    attachmentScrollArea->setObjectName(QStringLiteral("attachmentScrollArea"));
    attachmentScrollArea->setWidgetResizable(true);
    attachmentScrollArea->setFrameShape(QFrame::NoFrame);
    attachmentScrollArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    attachmentScrollArea->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    QWidget *attachmentChipList = new QWidget();
    attachmentChipList->setObjectName(QStringLiteral("attachmentChipList"));
    QHBoxLayout *attachmentChipListLayout = new QHBoxLayout(attachmentChipList);
    attachmentChipListLayout->setContentsMargins(0, 0, 0, 0);
    attachmentChipListLayout->setSpacing(intValue(style, "attachmentTrayChipSpacing", 8));
    attachmentScrollArea->setWidget(attachmentChipList);
    attachmentTrayLayout->addWidget(attachmentScrollArea);
    attachmentTray->setVisible(false);
    composerLayout->addWidget(attachmentTray);

    QHBoxLayout *promptRow = new QHBoxLayout();
    promptRow->setSpacing(intValue(style, "promptRowSpacing", 12));
    QPlainTextEdit *promptEditor = new QPlainTextEdit();
    promptEditor->setPlaceholderText(stringValue(
        payload,
        "composerPlaceholder",
        QStringLiteral("Ask a local model...")
    ));
    promptEditor->setMinimumHeight(intValue(style, "composerMinHeight", 74));
    promptEditor->setMaximumHeight(intValue(style, "composerMaxHeight", 120));
    const QString sendTitle = stringValue(payload, "sendTitle", QStringLiteral("Send"));
    const QString stopTitle = stringValue(payload, "stopTitle", QStringLiteral("Stop"));
    const QString stoppingStatus = stringValue(payload, "stoppingStatus", QStringLiteral("Stopping..."));
    QPushButton *sendButton = new QPushButton();
    sendButton->setObjectName(QStringLiteral("sendButton"));
    updateSendButtonPresentation(sendButton, isLoading, sendTitle, stopTitle);
    applyButtonIconSize(sendButton, style);
    sendButton->setMinimumWidth(intValue(style, "composerSendButtonMinWidth", 86));
    promptRow->addWidget(promptEditor, 1);
    promptRow->addWidget(sendButton);
    composerLayout->addLayout(promptRow);
    chatLayout->addWidget(composer);

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
        scrollTranscriptToBottom();
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
            attachmentSummaryForPaths(pendingAttachmentPaths),
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
        const bool hasPendingAttachments = !pendingAttachmentPaths.isEmpty();
        attachButton->setEnabled(hasTrimmedText(attachmentPath));
        clearAttachmentsButton->setEnabled(hasTrimmedText(attachmentPath) || hasPendingAttachments);
        sendButton->setEnabled(isLoading || hasTrimmedText(promptEditor) || hasPendingAttachments);
    };
    std::function<void()> renderAttachmentTray;
    renderAttachmentTray = [&]() {
        pendingAttachmentPaths = normalizedAttachmentPaths(pendingAttachmentPaths);
        clearLayout(attachmentChipListLayout);
        for (const QString &path : pendingAttachmentPaths) {
            QFrame *attachmentChip = QuillQtWidgets::frame(QStringLiteral("attachmentChip"));
            QHBoxLayout *attachmentChipLayout = new QHBoxLayout(attachmentChip);
            const int attachmentChipPadding = intValue(style, "attachmentChipPadding", 8);
            attachmentChipLayout->setContentsMargins(
                attachmentChipPadding,
                attachmentChipPadding,
                attachmentChipPadding,
                attachmentChipPadding
            );
            attachmentChipLayout->setSpacing(intValue(style, "attachmentChipSpacing", 8));

            QVBoxLayout *attachmentTextLayout = new QVBoxLayout();
            attachmentTextLayout->setContentsMargins(0, 0, 0, 0);
            attachmentTextLayout->setSpacing(intValue(style, "attachmentChipTextSpacing", 2));
            QLabel *attachmentName = label(attachmentDisplayName(path), QStringLiteral("attachmentName"));
            attachmentName->setWordWrap(false);
            attachmentTextLayout->addWidget(attachmentName);

            const QString displaySize = attachmentDisplaySize(path);
            if (!displaySize.isEmpty()) {
                QLabel *attachmentSize = label(displaySize, QStringLiteral("attachmentSize"));
                attachmentSize->setWordWrap(false);
                attachmentTextLayout->addWidget(attachmentSize);
            }

            QPushButton *removeAttachmentButton = new QPushButton(QStringLiteral("x"));
            removeAttachmentButton->setObjectName(QStringLiteral("chipRemoveButton"));
            removeAttachmentButton->setToolTip(QStringLiteral("Remove attachment"));
            removeAttachmentButton->setFixedWidth(intValue(style, "attachmentRemoveButtonWidth", 28));
            QObject::connect(removeAttachmentButton, &QPushButton::clicked, [&, path]() {
                pendingAttachmentPaths.removeAll(path);
                QTimer::singleShot(0, attachmentTray, renderAttachmentTray);
            });

            attachmentChipLayout->addLayout(attachmentTextLayout);
            attachmentChipLayout->addWidget(removeAttachmentButton);
            attachmentChipListLayout->addWidget(attachmentChip);
        }
        attachmentChipListLayout->addStretch(1);
        attachmentTray->setVisible(!pendingAttachmentPaths.isEmpty());
        updateComposerControlState();
    };
    auto addPendingAttachmentPaths = [&](const QStringList &rawPaths) -> bool {
        const QStringList attachmentPaths = normalizedAttachmentPaths(rawPaths);
        bool accepted = false;
        for (const QString &path : attachmentPaths) {
            if (pendingAttachmentPaths.contains(path)) {
                continue;
            }

            pendingAttachmentPaths.append(path);
            accepted = true;
        }

        if (!accepted) {
            return false;
        }

        renderAttachmentTray();
        statusText->setText(attachmentReadyStatus(pendingAttachmentPaths.count()));
        return true;
    };
    dropTarget->setDropHandler([&](const QStringList &paths) {
        addPendingAttachmentPaths(paths);
    });
    auto clearAttachmentState = [&]() {
        attachmentPath->clear();
        pendingAttachmentPaths.clear();
        clearLayout(attachmentChipListLayout);
        attachmentTray->setVisible(false);
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
            appendUserMessage,
            stringValue(payload, "status"),
            isLoading
        );
        showingPromptCards = messages.isEmpty();
        scrollTranscriptToBottom();
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
        isLoading = boolValue(payload, "isLoading", false);
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
            selectedConversationID,
            style
        );
        const QString selectedID = currentConversationID(conversationList, selectedConversationID);
        currentTitle->setText(selectedConversationTitle(
            conversations,
            selectedID,
            QStringLiteral("New conversation")
        ));
        statusText->setText(stringValue(payload, "status"));
        refreshButton->setEnabled(!isLoading);
        updateSendButtonPresentation(sendButton, isLoading, sendTitle, stopTitle);
        refreshStyle(sendButton);
        updateComposerControlState();
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

        if (addPendingAttachmentPaths(QStringList{rawPath})) {
            attachmentPath->clear();
        }
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
