#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QComboBox>
#include <QDir>
#include <QDragEnterEvent>
#include <QDragLeaveEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QEvent>
#include <QFileInfo>
#include <QFrame>
#include <QHBoxLayout>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QKeyEvent>
#include <QKeySequence>
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
#include <QShortcut>
#include <QSignalBlocker>
#include <QSplitter>
#include <QString>
#include <QStringList>
#include <QStyle>
#include <QTimer>
#include <QUrl>
#include <QVBoxLayout>
#include <QWidget>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <functional>

namespace {

using QuillQtWidgets::clearLayout;
using QuillQtWidgets::label;
using QuillQtWidgets::refreshStyle;
using QuillQtWidgets::scrollAreaToBottomLater;
using PromptAction = std::function<void(const QString &)>;

[[noreturn]] void failRequiredPayloadField(const char *key, const char *expectedType) {
    std::fprintf(
        stderr,
        "quill-enchanted-qt: missing required %s payload field: %s\n",
        expectedType,
        key
    );
    std::abort();
}

QJsonValue requiredValue(const QJsonObject &object, const char *key, const char *expectedType) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    if (!value.isUndefined() && !value.isNull()) {
        return value;
    }
    failRequiredPayloadField(key, expectedType);
}

QString requiredStringValue(const QJsonObject &object, const char *key) {
    const QJsonValue value = requiredValue(object, key, "string");
    if (value.isString()) {
        return value.toString();
    }
    failRequiredPayloadField(key, "string");
}

int requiredIntValue(const QJsonObject &object, const char *key) {
    const QJsonValue value = requiredValue(object, key, "integer");
    if (value.isDouble()) {
        return value.toInt();
    }
    failRequiredPayloadField(key, "integer");
}

bool requiredBoolValue(const QJsonObject &object, const char *key) {
    const QJsonValue value = requiredValue(object, key, "boolean");
    if (value.isBool()) {
        return value.toBool();
    }
    failRequiredPayloadField(key, "boolean");
}

QJsonObject requiredObjectValue(const QJsonObject &object, const char *key) {
    const QJsonValue value = requiredValue(object, key, "object");
    if (value.isObject()) {
        return value.toObject();
    }
    failRequiredPayloadField(key, "object");
}

QJsonObject requiredObjectValue(const QJsonValue &value, const char *key) {
    if (value.isObject()) {
        return value.toObject();
    }
    failRequiredPayloadField(key, "object");
}

QJsonArray requiredArrayValue(const QJsonObject &object, const char *key) {
    const QJsonValue value = requiredValue(object, key, "array");
    if (value.isArray()) {
        return value.toArray();
    }
    failRequiredPayloadField(key, "array");
}

QStringList requiredStringListValue(const QJsonObject &object, const char *key) {
    const QJsonValue value = requiredValue(object, key, "string array");
    if (!value.isArray()) {
        failRequiredPayloadField(key, "string array");
    }

    QStringList list;
    for (const QJsonValue &entry : value.toArray()) {
        if (!entry.isString()) {
            failRequiredPayloadField(key, "string array");
        }

        const QString item = entry.toString().trimmed().toLower();
        if (!item.isEmpty() && !list.contains(item)) {
            list.append(item);
        }
    }

    if (!list.isEmpty()) {
        return list;
    }
    failRequiredPayloadField(key, "non-empty string array");
}

QString styleValue(const QJsonObject &style, const char *key) {
    return requiredStringValue(style, key);
}

QString payloadString(const QJsonObject &payload, const char *key) {
    return requiredStringValue(payload, key);
}

bool payloadBool(const QJsonObject &payload, const char *key) {
    return requiredBoolValue(payload, key);
}

QJsonObject payloadObject(const QJsonObject &payload, const char *key) {
    return requiredObjectValue(payload, key);
}

QJsonArray payloadArray(const QJsonObject &payload, const char *key) {
    return requiredArrayValue(payload, key);
}

int styleInt(const QJsonObject &style, const char *key) {
    return requiredIntValue(style, key);
}

QString stylePixels(const QJsonObject &style, const char *key) {
    return QStringLiteral("%1px").arg(styleInt(style, key));
}

QSize requiredWindowSize(const QJsonObject &payload, const char *widthKey, const char *heightKey) {
    return QSize(requiredIntValue(payload, widthKey), requiredIntValue(payload, heightKey));
}

QSize clampedDefaultWindowSize(const QJsonObject &payload, const QSize &minimumSize) {
    const QSize requested = requiredWindowSize(payload, "defaultWidth", "defaultHeight");
    return QSize(
        std::max(requested.width(), minimumSize.width()),
        std::max(requested.height(), minimumSize.height())
    );
}

int intValue(const QJsonObject &object, const char *key, int fallback) {
    return QuillQtWidgets::jsonIntValue(object, key, fallback);
}

QIcon themedActionIcon(const QString &themeName, QStyle::StandardPixmap fallback) {
    return QIcon::fromTheme(themeName, QApplication::style()->standardIcon(fallback));
}

QString requiredIconName(const QJsonObject &icons, const char *key) {
    const QString value = requiredStringValue(icons, key).trimmed();
    if (!value.isEmpty()) {
        return value;
    }
    failRequiredPayloadField(key, "non-empty string");
}

QIcon systemImageIcon(const QString &systemImage) {
    const QString normalized = systemImage.trimmed().toLower();
    if (normalized.contains(QStringLiteral("square.and.pencil"))) {
        return themedActionIcon(QStringLiteral("document-new-symbolic"), QStyle::SP_FileIcon);
    }
    if (normalized.contains(QStringLiteral("folder.badge.plus"))) {
        return themedActionIcon(QStringLiteral("folder-new-symbolic"), QStyle::SP_FileDialogNewFolder);
    }
    if (normalized == QStringLiteral("folder") || normalized.contains(QStringLiteral("folder."))) {
        return themedActionIcon(QStringLiteral("folder-symbolic"), QStyle::SP_DirIcon);
    }
    if (normalized.contains(QStringLiteral("xmark.circle.fill"))) {
        return themedActionIcon(QStringLiteral("window-close-symbolic"), QStyle::SP_DialogCloseButton);
    }
    if (normalized.contains(QStringLiteral("square.fill"))) {
        return themedActionIcon(QStringLiteral("process-stop-symbolic"), QStyle::SP_MediaStop);
    }
    if (normalized.contains(QStringLiteral("arrow.forward.circle.fill"))) {
        return themedActionIcon(QStringLiteral("go-next-symbolic"), QStyle::SP_MediaPlay);
    }
    if (normalized.contains(QStringLiteral("character.cursor.ibeam")) || normalized.contains(QStringLiteral("ibeam"))) {
        return themedActionIcon(QStringLiteral("accessories-text-editor-symbolic"), QStyle::SP_FileDialogDetailedView);
    }
    if (normalized.contains(QStringLiteral("keyboard"))) {
        return themedActionIcon(QStringLiteral("input-keyboard-symbolic"), QStyle::SP_ComputerIcon);
    }
    if (normalized.contains(QStringLiteral("gearshape"))) {
        return themedActionIcon(QStringLiteral("preferences-system-symbolic"), QStyle::SP_MessageBoxInformation);
    }
    if (normalized.contains(QStringLiteral("questionmark"))) {
        return themedActionIcon(QStringLiteral("help-about-symbolic"), QStyle::SP_MessageBoxQuestion);
    }
    if (normalized.contains(QStringLiteral("lightbulb"))) {
        return themedActionIcon(QStringLiteral("dialog-information-symbolic"), QStyle::SP_MessageBoxInformation);
    }
    return themedActionIcon(QStringLiteral("starred-symbolic"), QStyle::SP_DialogYesButton);
}

QIcon newConversationButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "newConversation"));
}

QIcon attachButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "attach"));
}

QIcon dropTargetIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "dropTarget"));
}

QIcon attachmentChipIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "attachment"));
}

QIcon promptButtonIcon(const QString &systemImage) {
    return systemImageIcon(systemImage);
}

QIcon utilityButtonIcon(const QJsonObject &icons, const char *key) {
    return systemImageIcon(requiredIconName(icons, key));
}

QIcon sendButtonIcon(const QJsonObject &icons, bool isLoading) {
    const char *key = isLoading ? "stop" : "send";
    return systemImageIcon(requiredIconName(icons, key));
}

QIcon removeAttachmentButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "removeAttachment"));
}

QJsonObject requiredPromptObject(const QJsonValue &value) {
    return requiredObjectValue(value, "prompts[]");
}

QString promptTitle(const QJsonObject &prompt) {
    const QString title = requiredStringValue(prompt, "title");
    if (!title.trimmed().isEmpty()) {
        return title;
    }
    failRequiredPayloadField("title", "non-empty string");
}

QString promptSystemImage(const QJsonObject &prompt) {
    const QString systemImage = requiredStringValue(prompt, "systemImage").trimmed();
    if (!systemImage.isEmpty()) {
        return systemImage;
    }
    failRequiredPayloadField("systemImage", "non-empty string");
}

int buttonIconSize(const QJsonObject &style) {
    return styleInt(style, "actionButtonIconSize");
}

QLabel *iconLabel(const QIcon &icon, const QString &objectName, const QJsonObject &style) {
    const int iconSize = buttonIconSize(style);
    QLabel *view = new QLabel();
    view->setObjectName(objectName);
    view->setPixmap(icon.pixmap(iconSize, iconSize));
    view->setFixedSize(iconSize, iconSize);
    return view;
}

void applyButtonIconSize(QPushButton *button, const QJsonObject &style) {
    const int iconSize = buttonIconSize(style);
    button->setIconSize(QSize(iconSize, iconSize));
}

void updateSendButtonPresentation(
    QPushButton *button,
    const QJsonObject &icons,
    bool isLoading,
    const QString &sendTitle,
    const QString &stopTitle
) {
    button->setProperty("loading", isLoading);
    button->setText(isLoading ? stopTitle : sendTitle);
    button->setIcon(sendButtonIcon(icons, isLoading));
}

class LoadingSpinner final : public QWidget {
public:
    explicit LoadingSpinner(const QJsonObject &style, QWidget *parent = nullptr)
        : QWidget(parent),
          color(styleValue(style, "primaryColor")) {
        setObjectName(QStringLiteral("loadingSpinner"));
        const int spinnerSize = styleInt(style, "loadingSpinnerSize");
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

class ReturnSubmitFilter final : public QObject {
public:
    explicit ReturnSubmitFilter(const std::function<void()> &onSubmit, QObject *parent = nullptr)
        : QObject(parent),
          onSubmit(onSubmit) {}

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (event->type() != QEvent::KeyPress) {
            return QObject::eventFilter(watched, event);
        }

        QKeyEvent *keyEvent = static_cast<QKeyEvent *>(event);
        const int key = keyEvent->key();
        if (key != Qt::Key_Return && key != Qt::Key_Enter) {
            return QObject::eventFilter(watched, event);
        }

        if (keyEvent->modifiers().testFlag(Qt::ShiftModifier)) {
            return false;
        }

        onSubmit();
        return true;
    }

private:
    std::function<void()> onSubmit;
};

QString appStyleSheet(const QJsonObject &style) {
    const QString canvas = styleValue(style, "canvasColor");
    const QString ink = styleValue(style, "inkColor");
    const QString sidebar = styleValue(style, "sidebarColor");
    const QString header = styleValue(style, "headerColor");
    const QString card = styleValue(style, "cardColor");
    const QString primary = styleValue(style, "primaryColor");
    const QString system = styleValue(style, "systemColor");
    const QString muted = styleValue(style, "mutedColor");
    const QString selected = styleValue(style, "selectedMutedColor");
    const QString warning = styleValue(style, "warningColor");
    const QString success = styleValue(style, "successColor");
    const QString dropTarget = styleValue(style, "dropTargetColor");
    const QString quoteRule = styleValue(style, "quoteRuleColor");
    const QString codeBlock = styleValue(style, "codeBlockColor");
    const QString divider = styleValue(style, "dividerColor");
    const QString cardBorder = styleValue(style, "cardBorderColor");
    const QString messageBorder = styleValue(style, "messageBorderColor");
    const QString controlBorder = styleValue(style, "controlBorderColor");
    const QString dropTargetBorder = styleValue(style, "dropTargetBorderColor");
    const QString disabledButtonBackground = styleValue(style, "disabledButtonBackgroundColor");
    const QString disabledButtonForeground = styleValue(style, "disabledButtonForegroundColor");
    const QString disabledText = styleValue(style, "disabledTextColor");
    const QString rootFontSize = stylePixels(style, "rootFontSize");
    const QString appTitleFontSize = stylePixels(style, "appTitleFontSize");
    const QString appTitleFontWeight = QString::number(styleInt(style, "appTitleFontWeight"));
    const QString captionFontSize = stylePixels(style, "captionFontSize");
    const QString sectionTitleFontSize = stylePixels(style, "sectionTitleFontSize");
    const QString sectionTitleFontWeight = QString::number(styleInt(style, "sectionTitleFontWeight"));
    const QString currentTitleFontSize = stylePixels(style, "currentTitleFontSize");
    const QString currentTitleFontWeight = QString::number(styleInt(style, "currentTitleFontWeight"));
    const QString messageBodyFontSize = stylePixels(style, "messageBodyFontSize");
    const QString markdownHeading1FontSize = stylePixels(style, "markdownHeading1FontSize");
    const QString markdownHeading2FontSize = stylePixels(style, "markdownHeading2FontSize");
    const QString markdownHeadingFontSize = stylePixels(style, "markdownHeadingFontSize");
    const QString markdownHeadingFontWeight = QString::number(styleInt(style, "markdownHeadingFontWeight"));
    const QString markdownCodeLanguageFontSize = stylePixels(style, "markdownCodeLanguageFontSize");
    const QString markdownCodeFontSize = stylePixels(style, "markdownCodeFontSize");
    const QString attachmentNameFontSize = stylePixels(style, "attachmentNameFontSize");
    const QString attachmentSizeFontSize = stylePixels(style, "attachmentSizeFontSize");
    const QString conversationTitleFontSize = stylePixels(style, "conversationTitleFontSize");
    const QString conversationTitleFontWeight = QString::number(styleInt(style, "conversationTitleFontWeight"));
    const QString conversationPreviewFontSize = stylePixels(style, "conversationPreviewFontSize");
    const QString warningTextFontSize = stylePixels(style, "warningTextFontSize");
    const QString chipRemoveButtonFontWeight = QString::number(styleInt(style, "chipRemoveButtonFontWeight"));
    const QString statusDotSize = stylePixels(style, "statusDotSize");
    const QString statusDotRadius = stylePixels(style, "statusDotRadius");
    const QString conversationRowRadius = stylePixels(style, "conversationRowRadius");
    const QString conversationListItemRadius = stylePixels(style, "conversationListItemRadius");
    const QString conversationListItemVerticalMargin = stylePixels(style, "conversationListItemVerticalMargin");
    const QString conversationListItemPadding = stylePixels(style, "conversationListItemPadding");
    const QString emptyHistoryRadius = stylePixels(style, "emptyHistoryRadius");
    const QString messageBubbleRadius = stylePixels(style, "messageBubbleRadius");
    const QString attachmentChipRadius = stylePixels(style, "attachmentChipRadius");
    const QString markdownQuoteRuleRadius = stylePixels(style, "markdownQuoteRuleRadius");
    const QString markdownCodeBlockRadius = stylePixels(style, "markdownCodeBlockRadius");
    const QString dropTargetRadius = stylePixels(style, "dropTargetRadius");
    const QString promptButtonPadding = stylePixels(style, "promptButtonPadding");
    const QString promptButtonRadius = stylePixels(style, "promptButtonRadius");
    const QString primaryButtonVerticalPadding = stylePixels(style, "primaryButtonVerticalPadding");
    const QString primaryButtonHorizontalPadding = stylePixels(style, "primaryButtonHorizontalPadding");
    const QString primaryButtonRadius = stylePixels(style, "primaryButtonRadius");
    const QString secondaryButtonVerticalPadding = stylePixels(style, "secondaryButtonVerticalPadding");
    const QString secondaryButtonHorizontalPadding = stylePixels(style, "secondaryButtonHorizontalPadding");
    const QString secondaryButtonRadius = stylePixels(style, "secondaryButtonRadius");
    const QString chipRemoveButtonVerticalPadding = stylePixels(style, "chipRemoveButtonVerticalPadding");
    const QString chipRemoveButtonHorizontalPadding = stylePixels(style, "chipRemoveButtonHorizontalPadding");
    const QString controlPadding = stylePixels(style, "controlPadding");
    const QString controlRadius = stylePixels(style, "controlRadius");
    const QString composerEditorRadius = stylePixels(style, "composerEditorRadius");

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
        QFrame#emptyHistory, QFrame#sidebarUtilityPanel { background: %1; border: 1px solid %2; border-radius: %3; }
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
        QLabel#promptButtonIcon, QLabel#promptButtonText { color: %2; font-size: %6; }
    )")
        .arg(card, ink, cardBorder, promptButtonRadius, promptButtonPadding, rootFontSize);

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
        QLineEdit, QComboBox { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; }
        QPlainTextEdit { background: %1; color: %2; border: 1px solid %3; border-radius: %6; padding: %5; }
    )")
        .arg(card, ink, controlBorder, controlRadius, controlPadding, composerEditorRadius);

    return sheet;
}

QString conversationID(const QJsonObject &conversation) {
    return requiredStringValue(conversation, "id");
}

QString conversationTitle(const QJsonObject &conversation) {
    return requiredStringValue(conversation, "title");
}

QString conversationLastMessage(const QJsonObject &conversation) {
    return requiredStringValue(conversation, "lastMessage");
}

QString messageRole(const QJsonObject &message) {
    return requiredStringValue(message, "role");
}

QString messageContent(const QJsonObject &message) {
    return requiredStringValue(message, "content");
}

QFrame *conversationRowWidget(
    const QJsonObject &conversation,
    const QJsonObject &style
) {
    QFrame *row = QuillQtWidgets::frame(QStringLiteral("conversationRow"));
    row->setProperty("active", false);
    QVBoxLayout *layout = new QVBoxLayout(row);
    const int conversationRowPadding = styleInt(style, "conversationRowPadding");
    const int conversationRowSpacing = styleInt(style, "conversationRowSpacing");
    layout->setContentsMargins(
        conversationRowPadding,
        conversationRowPadding,
        conversationRowPadding,
        conversationRowPadding
    );
    layout->setSpacing(conversationRowSpacing);

    QLabel *title = label(conversationTitle(conversation), QStringLiteral("conversationTitle"));
    title->setWordWrap(false);
    title->setProperty("active", false);

    const QString previewText = conversationLastMessage(conversation);

    layout->addWidget(title);
    if (!previewText.isEmpty()) {
        QLabel *preview = label(previewText, QStringLiteral("conversationPreview"));
        preview->setProperty("active", false);
        layout->addWidget(preview);
    }
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
    const int emptyHistoryPadding = styleInt(style, "emptyHistoryPadding");
    const int emptyHistorySpacing = styleInt(style, "emptyHistorySpacing");
    layout->setContentsMargins(
        emptyHistoryPadding,
        emptyHistoryPadding,
        emptyHistoryPadding,
        emptyHistoryPadding
    );
    layout->setSpacing(emptyHistorySpacing);
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
        if (conversationID(conversation) == selectedConversationID) {
            return conversationTitle(conversation);
        }
    }
    return fallback;
}

QString modelStatusText(
    const QString &selectedModel,
    const QString &chooseLocalModelStatus,
    const QString &usingModelStatusPrefix
) {
    const QString trimmedModel = selectedModel.trimmed();
    if (trimmedModel.isEmpty()) {
        return chooseLocalModelStatus;
    }

    return QStringLiteral("%1 %2").arg(usingModelStatusPrefix, trimmedModel);
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

QString messageRoleTitle(
    const QString &role,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel
) {
    if (role == QStringLiteral("user")) {
        return userRoleLabel;
    }
    if (role == QStringLiteral("system")) {
        return systemRoleLabel;
    }

    return assistantRoleLabel;
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
    const int markdownListItemSpacing = styleInt(style, "markdownListItemSpacing");
    const int markdownNumberWidth = styleInt(style, "markdownNumberWidth");
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(markdownListItemSpacing);

    QLabel *markerLabel = label(marker, markerObjectName);
    if (markerObjectName == QStringLiteral("markdownNumber")) {
        markerLabel->setFixedWidth(markdownNumberWidth);
    }
    markerLabel->setAlignment(Qt::AlignTop | Qt::AlignRight);
    layout->addWidget(markerLabel);
    layout->addWidget(markdownLabel(text, QStringLiteral("markdownParagraph")), 1);
    return row;
}

QWidget *markdownQuoteWidget(const QString &text, const QJsonObject &style) {
    QWidget *row = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(row);
    const int verticalPadding = styleInt(style, "markdownQuoteVerticalPadding");
    const int markdownQuoteSpacing = styleInt(style, "markdownQuoteSpacing");
    const int markdownQuoteRuleWidth = styleInt(style, "markdownQuoteRuleWidth");
    layout->setContentsMargins(0, verticalPadding, 0, verticalPadding);
    layout->setSpacing(markdownQuoteSpacing);

    QFrame *rule = QuillQtWidgets::frame(QStringLiteral("markdownQuoteRule"));
    rule->setFixedWidth(markdownQuoteRuleWidth);
    layout->addWidget(rule);
    layout->addWidget(markdownLabel(text, QStringLiteral("markdownQuote")), 1);
    return row;
}

QWidget *markdownCodeBlockWidget(const MarkdownBlock &block, const QJsonObject &style) {
    QFrame *codeBlock = QuillQtWidgets::frame(QStringLiteral("markdownCodeBlock"));
    QVBoxLayout *layout = new QVBoxLayout(codeBlock);
    const int codeBlockPadding = styleInt(style, "markdownCodeBlockPadding");
    const int markdownCodeBlockSpacing = styleInt(style, "markdownCodeBlockSpacing");
    layout->setContentsMargins(codeBlockPadding, codeBlockPadding, codeBlockPadding, codeBlockPadding);
    layout->setSpacing(markdownCodeBlockSpacing);

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
    const int markdownBlockSpacing = styleInt(style, "markdownBlockSpacing");
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(markdownBlockSpacing);
    addMarkdownBlocks(layout, markdown, style);
    return container;
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
            conversationID(conversation) == selectedConversationID
            && conversation.contains(QStringLiteral("messages"))
        ) {
            return requiredArrayValue(conversation, "messages");
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
    list->setSpacing(styleInt(style, "conversationListSpacing"));
    int selectedRow = -1;

    for (const QJsonValue &value : conversations) {
        const QJsonObject conversation = value.toObject();
        const QString id = conversationID(conversation);
        QListWidgetItem *item = new QListWidgetItem();
        item->setData(Qt::UserRole, id);
        list->addItem(item);
        QWidget *rowWidget = conversationRowWidget(conversation, style);
        item->setSizeHint(QSize(260, rowWidget->sizeHint().height()));
        list->setItemWidget(item, rowWidget);
        if (id == selectedConversationID) {
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

QFrame *messageBubble(
    const QJsonObject &message,
    const QJsonObject &style,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel
) {
    const QString role = messageRole(message);
    const QString content = messageContent(message);
    QString objectName = QStringLiteral("messageAssistant");
    if (role == QStringLiteral("user")) {
        objectName = QStringLiteral("messageUser");
    } else if (role == QStringLiteral("system")) {
        objectName = QStringLiteral("messageSystem");
    }

    QFrame *bubble = QuillQtWidgets::frame(objectName);
    const int messageMaxWidth = styleInt(style, "messageMaxWidth");
    bubble->setMaximumWidth(messageMaxWidth);

    QVBoxLayout *layout = new QVBoxLayout(bubble);
    const int messageBubblePadding = styleInt(style, "messageBubblePadding");
    const int messageBubbleSpacing = styleInt(style, "messageBubbleSpacing");
    layout->setContentsMargins(
        messageBubblePadding,
        messageBubblePadding,
        messageBubblePadding,
        messageBubblePadding
    );
    layout->setSpacing(messageBubbleSpacing);
    layout->addWidget(label(
        messageRoleTitle(role, userRoleLabel, assistantRoleLabel, systemRoleLabel),
        role == QStringLiteral("user") ? QStringLiteral("messageUserRole") : QStringLiteral("messageRole")
    ));
    if (role == QStringLiteral("user")) {
        layout->addWidget(label(content, QStringLiteral("messageUserText")));
    } else {
        layout->addWidget(markdownMessageWidget(content, style));
    }
    return bubble;
}

void addMessageBubble(
    QVBoxLayout *messageLayout,
    const QJsonObject &message,
    const QJsonObject &style,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel
) {
    const bool isUser = messageRole(message) == QStringLiteral("user");
    QHBoxLayout *row = new QHBoxLayout();
    const int messageBubbleRowSpacing = styleInt(style, "messageBubbleRowSpacing");
    row->setContentsMargins(0, 0, 0, 0);
    row->setSpacing(messageBubbleRowSpacing);
    if (isUser) {
        row->addStretch(1);
    }
    row->addWidget(messageBubble(
        message,
        style,
        userRoleLabel,
        assistantRoleLabel,
        systemRoleLabel
    ));
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
    const int emptyStatePadding = styleInt(style, "emptyStatePadding");
    layout->setContentsMargins(
        emptyStatePadding,
        emptyStatePadding,
        emptyStatePadding,
        emptyStatePadding
    );
    layout->setSpacing(styleInt(style, "emptyStateSpacing"));
    const int promptButtonWidth = styleInt(style, "promptButtonWidth");
    QVBoxLayout *headerLayout = new QVBoxLayout();
    headerLayout->setContentsMargins(0, 0, 0, 0);
    headerLayout->setSpacing(styleInt(style, "emptyStateHeaderSpacing"));
    headerLayout->addWidget(label(title, QStringLiteral("currentTitle")));
    QLabel *subtitleLabel = label(subtitle, QStringLiteral("caption"));
    subtitleLabel->setFixedWidth(promptButtonWidth);
    headerLayout->addWidget(subtitleLabel);
    layout->addLayout(headerLayout);

    QVBoxLayout *promptList = new QVBoxLayout();
    promptList->setContentsMargins(0, 0, 0, 0);
    promptList->setSpacing(styleInt(style, "promptListSpacing"));
    const int promptButtonIconSpacing = styleInt(style, "promptButtonIconSpacing");
    const int promptButtonTextWidth = promptButtonWidth - styleInt(style, "promptButtonTextWidthInset");
    const int promptButtonPadding = styleInt(style, "promptButtonPadding");
    const int promptButtonMinHeight = styleInt(style, "promptButtonMinHeight");
    for (const QJsonValue &value : prompts) {
        const QJsonObject promptPayload = requiredPromptObject(value);
        const QString prompt = promptTitle(promptPayload);
        const QString systemImage = promptSystemImage(promptPayload);
        QPushButton *button = new QPushButton();
        button->setObjectName(QStringLiteral("promptButton"));
        button->setAccessibleName(prompt);
        button->setMinimumHeight(promptButtonMinHeight);
        button->setFixedWidth(promptButtonWidth);
        QHBoxLayout *buttonLayout = new QHBoxLayout(button);
        buttonLayout->setContentsMargins(
            promptButtonPadding,
            promptButtonPadding,
            promptButtonPadding,
            promptButtonPadding
        );
        buttonLayout->setSpacing(promptButtonIconSpacing);
        QLabel *promptIcon = iconLabel(promptButtonIcon(systemImage), QStringLiteral("promptButtonIcon"), style);
        promptIcon->setAttribute(Qt::WA_TransparentForMouseEvents);
        QLabel *promptText = label(prompt, QStringLiteral("promptButtonText"));
        promptText->setWordWrap(true);
        promptText->setFixedWidth(promptButtonTextWidth > 0 ? promptButtonTextWidth : 0);
        promptText->setAttribute(Qt::WA_TransparentForMouseEvents);
        buttonLayout->addWidget(promptIcon, 0, Qt::AlignVCenter);
        buttonLayout->addWidget(promptText, 0, Qt::AlignVCenter);
        buttonLayout->addStretch(1);
        QObject::connect(button, &QPushButton::clicked, [prompt, promptAction]() {
            promptAction(prompt);
        });
        promptList->addWidget(button);
    }

    layout->addLayout(promptList);
    emptyState->setMaximumWidth(styleInt(style, "emptyStateMaxWidth"));
    messageLayout->addWidget(emptyState);
    messageLayout->addStretch(1);
}

QWidget *loadingRowWidget(const QString &status, const QJsonObject &style) {
    QWidget *row = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(row);
    layout->setContentsMargins(0, styleInt(style, "loadingTopPadding"), 0, 0);
    layout->setSpacing(styleInt(style, "loadingRowSpacing"));

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
    bool isLoading,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel
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
        addMessageBubble(
            messageLayout,
            value.toObject(),
            style,
            userRoleLabel,
            assistantRoleLabel,
            systemRoleLabel
        );
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

struct AttachmentPathValidation {
    QStringList acceptedPaths;
    QString lastError;
};

struct AttachmentValidationPolicy {
    qint64 maxByteCount;
    QStringList supportedExtensions;
    QString unsupportedSuffix;
    QString unreadablePrefix;
    QString unreadableSuffix;
    QString oversizedMiddle;
    QString oversizedSuffix;
};

QString formattedAttachmentByteCount(qint64 byteCount);
QString attachmentDisplaySize(const QString &rawPath);

AttachmentValidationPolicy attachmentValidationPolicy(const QJsonObject &payload) {
    return AttachmentValidationPolicy{
        requiredIntValue(payload, "attachmentMaxByteCount"),
        requiredStringListValue(payload, "supportedAttachmentExtensions"),
        requiredStringValue(payload, "unsupportedAttachmentSuffix"),
        requiredStringValue(payload, "unreadableAttachmentPrefix"),
        requiredStringValue(payload, "unreadableAttachmentSuffix"),
        requiredStringValue(payload, "oversizedAttachmentMiddle"),
        requiredStringValue(payload, "oversizedAttachmentSuffix")
    };
}

QString normalizedAttachmentPath(const QString &rawPath) {
    QString trimmedPath = rawPath.trimmed();
    if (trimmedPath.isEmpty()) {
        return QString();
    }

    const QUrl url(trimmedPath);
    if (url.isValid() && url.isLocalFile()) {
        trimmedPath = url.toLocalFile();
    } else if (trimmedPath == QStringLiteral("~")) {
        trimmedPath = QDir::homePath();
    } else if (trimmedPath.startsWith(QStringLiteral("~/"))) {
        trimmedPath = QDir::homePath() + QStringLiteral("/") + trimmedPath.mid(2);
    }

    return QFileInfo(trimmedPath).absoluteFilePath();
}

QStringList attachmentPathCandidatesFromInput(const QString &rawText) {
    QString normalizedText = rawText;
    normalizedText.replace(QChar('\r'), QChar('\n'));
    normalizedText.replace(QChar(';'), QChar('\n'));

    QStringList candidates;
    for (const QString &part : normalizedText.split(QChar('\n'), Qt::SkipEmptyParts)) {
        const QString candidate = part.trimmed();
        if (!candidate.isEmpty()) {
            candidates.append(candidate);
        }
    }

    return candidates;
}

bool hasAttachmentPathCandidates(const QLineEdit *field) {
    return field != nullptr && !attachmentPathCandidatesFromInput(field->text()).isEmpty();
}

QString attachmentDisplayName(const QString &rawPath) {
    const QString path = normalizedAttachmentPath(rawPath);
    if (path.isEmpty()) {
        return QString();
    }

    const QFileInfo fileInfo(path);
    const QString fileName = fileInfo.fileName();
    return fileName.isEmpty() ? path : fileName;
}

QStringList normalizedAttachmentPaths(const QStringList &rawPaths) {
    QStringList normalizedPaths;
    for (const QString &rawPath : rawPaths) {
        const QString path = normalizedAttachmentPath(rawPath);
        if (attachmentDisplayName(path).isEmpty() || normalizedPaths.contains(path)) {
            continue;
        }

        normalizedPaths.append(path);
    }

    return normalizedPaths;
}

QString unsupportedAttachmentMessage(const QString &name, const AttachmentValidationPolicy &policy) {
    return name + policy.unsupportedSuffix;
}

QString unreadableAttachmentMessage(const QString &path, const AttachmentValidationPolicy &policy) {
    return policy.unreadablePrefix + path + policy.unreadableSuffix;
}

QString oversizedAttachmentMessage(const QString &name, qint64 byteCount, const AttachmentValidationPolicy &policy) {
    return name + policy.oversizedMiddle + formattedAttachmentByteCount(byteCount) + policy.oversizedSuffix;
}

AttachmentPathValidation validatedAttachmentPaths(
    const QStringList &rawPaths,
    const AttachmentValidationPolicy &policy
) {
    AttachmentPathValidation validation;

    for (const QString &rawPath : rawPaths) {
        const QString path = normalizedAttachmentPath(rawPath);
        if (path.isEmpty()) {
            continue;
        }

        const QFileInfo fileInfo(path);
        const QString displayName = fileInfo.fileName().isEmpty() ? path : fileInfo.fileName();
        if (!policy.supportedExtensions.contains(fileInfo.suffix().toLower())) {
            validation.lastError = unsupportedAttachmentMessage(displayName, policy);
            continue;
        }

        if (!fileInfo.exists() || !fileInfo.isFile() || !fileInfo.isReadable()) {
            validation.lastError = unreadableAttachmentMessage(path, policy);
            continue;
        }

        const qint64 byteCount = fileInfo.size();
        if (byteCount > policy.maxByteCount) {
            validation.lastError = oversizedAttachmentMessage(displayName, byteCount, policy);
            continue;
        }

        if (!validation.acceptedPaths.contains(path)) {
            validation.acceptedPaths.append(path);
        }
    }

    return validation;
}

QStringList attachmentCandidatePathsFromMimeData(
    const QMimeData *mimeData,
    const QStringList &supportedExtensions
) {
    QStringList paths;
    if (mimeData == nullptr || !mimeData->hasUrls()) {
        return paths;
    }

    for (const QUrl &url : mimeData->urls()) {
        if (!url.isLocalFile()) {
            continue;
        }

        const QString path = normalizedAttachmentPath(url.toLocalFile());
        if (path.isEmpty() || paths.contains(path)) {
            continue;
        }

        const QFileInfo fileInfo(path);
        if (!supportedExtensions.contains(fileInfo.suffix().toLower())) {
            continue;
        }

        paths.append(path);
    }

    return paths;
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

    void setSupportedAttachmentExtensions(const QStringList &extensions) {
        supportedAttachmentExtensions = extensions;
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
        const QStringList paths = attachmentCandidatePathsFromMimeData(
            event->mimeData(),
            supportedAttachmentExtensions
        );
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

        const bool acceptsDrop = !attachmentCandidatePathsFromMimeData(
            event->mimeData(),
            supportedAttachmentExtensions
        ).isEmpty();
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
    QStringList supportedAttachmentExtensions;
};

QString attachmentSummaryForPaths(const QStringList &rawPaths) {
    QStringList summaryLines;
    for (const QString &path : normalizedAttachmentPaths(rawPaths)) {
        const QString displayName = attachmentDisplayName(path);
        const QString displaySize = attachmentDisplaySize(path);
        summaryLines.append(
            displaySize.isEmpty()
                ? QStringLiteral("- %1").arg(displayName)
                : QStringLiteral("- %1 (%2)").arg(displayName, displaySize)
        );
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
        QStringLiteral("GB")
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
    const QFileInfo fileInfo(normalizedAttachmentPath(rawPath));
    if (!fileInfo.exists() || !fileInfo.isFile()) {
        return QString();
    }

    return formattedAttachmentByteCount(fileInfo.size());
}

QString attachmentReadyStatus(
    int count,
    const QString &imageReadyStatusSingular,
    const QString &imageReadyStatusPluralUnit
) {
    return count == 1
        ? imageReadyStatusSingular
        : QStringLiteral("%1 %2").arg(count).arg(imageReadyStatusPluralUnit);
}

QString attachmentDefaultPromptForCount(
    int attachmentCount,
    const QString &defaultPrompt,
    const QString &defaultPromptPlural
) {
    return attachmentCount == 1 ? defaultPrompt : defaultPromptPlural;
}

QString attachmentDisplayContent(
    const QString &rawPrompt,
    const QString &attachmentSummary,
    int attachmentCount,
    const QString &defaultPrompt,
    const QString &defaultPromptPlural,
    const QString &summaryTitle
) {
    const QString trimmedPrompt = rawPrompt.trimmed();
    if (attachmentSummary.isEmpty()) {
        return trimmedPrompt;
    }

    const QString prompt = trimmedPrompt.isEmpty()
        ? attachmentDefaultPromptForCount(attachmentCount, defaultPrompt, defaultPromptPlural)
        : trimmedPrompt;
    return QStringLiteral("%1\n\n%2\n%3").arg(prompt, summaryTitle, attachmentSummary);
}

void addSidebarField(
    QVBoxLayout *layout,
    const QString &title,
    QWidget *field,
    const QJsonObject &style
) {
    QWidget *group = new QWidget();
    QVBoxLayout *groupLayout = new QVBoxLayout(group);
    groupLayout->setContentsMargins(0, 0, 0, 0);
    groupLayout->setSpacing(styleInt(style, "sidebarControlGroupSpacing"));
    groupLayout->addWidget(fieldLabel(title));
    groupLayout->addWidget(field);
    layout->addWidget(group);
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
    const QJsonObject style = payloadObject(payload, "style");
    QJsonObject icons = payloadObject(payload, "icons");
    bool isLoading = payloadBool(payload, "isLoading");
    const QString chooseLocalModelStatus = payloadString(payload, "chooseLocalModelStatus");
    const QString usingModelStatusPrefix = payloadString(payload, "usingModelStatusPrefix");
    const QString newConversationButtonTitle = payloadString(payload, "newConversationButtonTitle");
    const QString newConversationTitle = payloadString(payload, "newConversationTitle");
    const QString userRoleLabel = payloadString(payload, "userRoleLabel");
    const QString assistantRoleLabel = payloadString(payload, "assistantRoleLabel");
    const QString systemRoleLabel = payloadString(payload, "systemRoleLabel");
    app.setApplicationName(payloadString(payload, "windowTitle"));
    app.setStyleSheet(appStyleSheet(style));

    QWidget window;
    window.setObjectName(QStringLiteral("enchantedRoot"));
    window.setWindowTitle(payloadString(payload, "windowTitle"));
    const QSize minimumWindowSize = requiredWindowSize(payload, "minimumWidth", "minimumHeight");
    const QSize defaultWindowSize = clampedDefaultWindowSize(payload, minimumWindowSize);
    window.setMinimumSize(minimumWindowSize);
    window.resize(defaultWindowSize);

    QHBoxLayout *rootLayout = new QHBoxLayout(&window);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    QSplitter *splitter = new QSplitter();
    rootLayout->addWidget(splitter);

    QFrame *sidebar = QuillQtWidgets::frame(QStringLiteral("sidebar"));
    const int sidebarWidth = styleInt(style, "sidebarWidth");
    sidebar->setMinimumWidth(sidebarWidth);
    sidebar->setMaximumWidth(sidebarWidth);
    QVBoxLayout *sidebarLayout = new QVBoxLayout(sidebar);
    const int sidebarPadding = styleInt(style, "sidebarPadding");
    sidebarLayout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding);
    sidebarLayout->setSpacing(styleInt(style, "sidebarSpacing"));

    QWidget *sidebarTitleBlock = new QWidget();
    QVBoxLayout *sidebarTitleLayout = new QVBoxLayout(sidebarTitleBlock);
    sidebarTitleLayout->setContentsMargins(0, 0, 0, 0);
    sidebarTitleLayout->setSpacing(styleInt(style, "sidebarTitleSpacing"));
    sidebarTitleLayout->addWidget(label(
        payloadString(payload, "sidebarTitle"),
        QStringLiteral("appTitle")
    ));
    sidebarTitleLayout->addWidget(label(
        payloadString(payload, "sidebarSubtitle"),
        QStringLiteral("caption")
    ));
    sidebarLayout->addWidget(sidebarTitleBlock);

    QPushButton *newConversationButton = new QPushButton(newConversationButtonTitle);
    newConversationButton->setObjectName(QStringLiteral("primaryButton"));
    newConversationButton->setIcon(newConversationButtonIcon(icons));
    applyButtonIconSize(newConversationButton, style);
    sidebarLayout->addWidget(newConversationButton);

    QLineEdit *endpointField = new QLineEdit(payloadString(payload, "endpoint"));
    addSidebarField(
        sidebarLayout,
        payloadString(payload, "endpointLabel"),
        endpointField,
        style
    );

    QJsonArray models = payloadArray(payload, "models");
    const QString modelLabel = payloadString(payload, "modelLabel");
    QComboBox *modelPicker = new QComboBox();
    QLabel *noModelsNotice = label(
        payloadString(payload, "noModelsTitle"),
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
    populateModelPicker(models, payloadString(payload, "selectedModel"));
    addSidebarField(
        sidebarLayout,
        modelLabel,
        modelPicker,
        style
    );
    sidebarLayout->addWidget(noModelsNotice);

    QHBoxLayout *statusLayout = new QHBoxLayout();
    statusLayout->setContentsMargins(0, 0, 0, 0);
    const int statusRowSpacing = styleInt(style, "statusRowSpacing");
    statusLayout->setSpacing(statusRowSpacing);
    QFrame *statusDot = QuillQtWidgets::frame(
        models.isEmpty() ? QStringLiteral("statusDotWarning") : QStringLiteral("statusDot")
    );
    const int statusDotSize = styleInt(style, "statusDotSize");
    statusDot->setFixedSize(statusDotSize, statusDotSize);
    statusLayout->addWidget(statusDot);
    QLabel *statusText = label(payloadString(payload, "status"), QStringLiteral("statusText"));
    const int statusTextWidth = styleInt(style, "statusTextWidth");
    statusText->setFixedWidth(statusTextWidth);
    statusLayout->addWidget(statusText);
    sidebarLayout->addLayout(statusLayout);

    sidebarLayout->addWidget(label(
        payloadString(payload, "conversationsTitle"),
        QStringLiteral("sectionTitle")
    ));

    QJsonArray conversations = payloadArray(payload, "conversations");
    QString selectedConversationID = payloadString(payload, "selectedConversationID");
    QFrame *emptyHistory = emptyHistoryWidget(
        payloadString(payload, "emptyHistoryTitle"),
        payloadString(payload, "emptyHistorySubtitle"),
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
    conversationActions->setContentsMargins(0, 0, 0, 0);
    const int conversationActionsSpacing = styleInt(style, "conversationActionsSpacing");
    conversationActions->setSpacing(conversationActionsSpacing);
    QPushButton *deleteButton = new QPushButton(payloadString(payload, "deleteChatTitle"));
    deleteButton->setObjectName(QStringLiteral("secondaryButton"));
    QPushButton *clearAllButton = new QPushButton(payloadString(payload, "clearAllTitle"));
    clearAllButton->setObjectName(QStringLiteral("secondaryButton"));
    conversationActions->addWidget(deleteButton);
    conversationActions->addWidget(clearAllButton);
    sidebarLayout->addLayout(conversationActions);

    QFrame *sidebarUtilityPanel = QuillQtWidgets::frame(QStringLiteral("sidebarUtilityPanel"));
    QVBoxLayout *sidebarUtilityLayout = new QVBoxLayout(sidebarUtilityPanel);
    const int emptyHistoryPadding = styleInt(style, "emptyHistoryPadding");
    const int emptyHistorySpacing = styleInt(style, "emptyHistorySpacing");
    const int sidebarUtilityPadding = emptyHistoryPadding;
    sidebarUtilityLayout->setContentsMargins(
        sidebarUtilityPadding,
        sidebarUtilityPadding,
        sidebarUtilityPadding,
        sidebarUtilityPadding
    );
    sidebarUtilityLayout->setSpacing(emptyHistorySpacing);
    QLabel *sidebarUtilityTitle = label(QString(), QStringLiteral("sectionTitle"));
    QLabel *sidebarUtilitySubtitle = label(QString(), QStringLiteral("caption"));
    sidebarUtilitySubtitle->setWordWrap(true);
    sidebarUtilityLayout->addWidget(sidebarUtilityTitle);
    sidebarUtilityLayout->addWidget(sidebarUtilitySubtitle);
    sidebarUtilityPanel->setVisible(false);
    sidebarLayout->addWidget(sidebarUtilityPanel);

    QFrame *sidebarBottomNavigation = QuillQtWidgets::frame(QStringLiteral("sidebarBottomNavigation"));
    QVBoxLayout *sidebarBottomNavigationLayout = new QVBoxLayout(sidebarBottomNavigation);
    sidebarBottomNavigationLayout->setContentsMargins(0, 0, 0, 0);
    sidebarBottomNavigationLayout->setSpacing(conversationActionsSpacing);
    QPushButton *completionsButton = new QPushButton(payloadString(payload, "completionsTitle"));
    completionsButton->setObjectName(QStringLiteral("secondaryButton"));
    completionsButton->setIcon(utilityButtonIcon(icons, "completions"));
    applyButtonIconSize(completionsButton, style);
    QPushButton *shortcutsButton = new QPushButton(payloadString(payload, "shortcutsTitle"));
    shortcutsButton->setObjectName(QStringLiteral("secondaryButton"));
    shortcutsButton->setIcon(utilityButtonIcon(icons, "shortcuts"));
    applyButtonIconSize(shortcutsButton, style);
    QPushButton *settingsButton = new QPushButton(payloadString(payload, "settingsTitle"));
    settingsButton->setObjectName(QStringLiteral("secondaryButton"));
    settingsButton->setIcon(utilityButtonIcon(icons, "settings"));
    applyButtonIconSize(settingsButton, style);
    sidebarBottomNavigationLayout->addWidget(completionsButton);
    sidebarBottomNavigationLayout->addWidget(shortcutsButton);
    sidebarBottomNavigationLayout->addWidget(settingsButton);
    sidebarLayout->addWidget(sidebarBottomNavigation);

    QFrame *chatPane = QuillQtWidgets::frame(QStringLiteral("chatPane"));
    QVBoxLayout *chatLayout = new QVBoxLayout(chatPane);
    chatLayout->setContentsMargins(0, 0, 0, 0);
    chatLayout->setSpacing(0);

    QFrame *header = QuillQtWidgets::frame(QStringLiteral("chatHeader"));
    QHBoxLayout *headerLayout = new QHBoxLayout(header);
    const int headerPadding = styleInt(style, "headerPadding");
    headerLayout->setContentsMargins(headerPadding, headerPadding, headerPadding, headerPadding);
    const int headerSpacing = styleInt(style, "headerSpacing");
    headerLayout->setSpacing(headerSpacing);
    QVBoxLayout *titleLayout = new QVBoxLayout();
    titleLayout->setContentsMargins(0, 0, 0, 0);
    const int headerTitleSpacing = styleInt(style, "headerTitleSpacing");
    titleLayout->setSpacing(headerTitleSpacing);
    const QString initialConversationID = currentConversationID(conversationList, selectedConversationID);
    QLabel *currentTitle = label(
        selectedConversationTitle(
            conversations,
            initialConversationID,
            newConversationTitle
        ),
        QStringLiteral("currentTitle")
    );
    QLabel *modelStatus = label(
        modelStatusText(payloadString(payload, "selectedModel"), chooseLocalModelStatus, usingModelStatusPrefix),
        QStringLiteral("caption")
    );
    const int headerTitleWidth = styleInt(style, "headerTitleWidth");
    currentTitle->setFixedWidth(headerTitleWidth);
    modelStatus->setFixedWidth(headerTitleWidth);
    titleLayout->addWidget(currentTitle);
    titleLayout->addWidget(modelStatus);
    headerLayout->addLayout(titleLayout, 1);
    QPushButton *refreshButton = new QPushButton(payloadString(payload, "refreshModelsTitle"));
    refreshButton->setObjectName(QStringLiteral("secondaryButton"));
    refreshButton->setEnabled(!isLoading);
    headerLayout->addWidget(refreshButton);
    chatLayout->addWidget(header);

    QScrollArea *scrollArea = new QScrollArea();
    scrollArea->setWidgetResizable(true);
    QWidget *transcript = new QWidget();
    QVBoxLayout *messageLayout = new QVBoxLayout(transcript);
    const int contentPadding = styleInt(style, "contentPadding");
    messageLayout->setContentsMargins(contentPadding, contentPadding, contentPadding, contentPadding);
    const int messageSpacing = styleInt(style, "messageSpacing");
    messageLayout->setSpacing(messageSpacing);
    scrollArea->setWidget(transcript);
    chatLayout->addWidget(scrollArea, 1);
    auto scrollTranscriptToBottom = [scrollArea]() {
        scrollAreaToBottomLater(scrollArea);
    };

    QFrame *composer = QuillQtWidgets::frame(QStringLiteral("composer"));
    QHBoxLayout *composerBandLayout = new QHBoxLayout(composer);
    composerBandLayout->setContentsMargins(0, 0, 0, 0);
    composerBandLayout->setSpacing(0);
    QWidget *composerContent = new QWidget();
    composerContent->setMinimumWidth(styleInt(style, "composerMinWidth"));
    composerContent->setMaximumWidth(styleInt(style, "composerMaxWidth"));
    QVBoxLayout *composerLayout = new QVBoxLayout(composerContent);
    const int composerPadding = styleInt(style, "composerPadding");
    composerLayout->setContentsMargins(composerPadding, composerPadding, composerPadding, composerPadding);
    composerLayout->setSpacing(styleInt(style, "composerSpacing"));
    composerBandLayout->addStretch(1);
    composerBandLayout->addWidget(composerContent);
    composerBandLayout->addStretch(1);

    const int attachmentInputSpacing = styleInt(style, "attachmentInputSpacing");
    AttachmentDropFrame *dropTarget = new AttachmentDropFrame();
    QVBoxLayout *dropTargetLayout = new QVBoxLayout(dropTarget);
    dropTargetLayout->setContentsMargins(0, 0, 0, 0);
    dropTargetLayout->setSpacing(attachmentInputSpacing);

    QFrame *dropHint = QuillQtWidgets::frame(QStringLiteral("dropTargetHint"));
    QHBoxLayout *dropHintLayout = new QHBoxLayout(dropHint);
    const int dropTargetPadding = styleInt(style, "dropTargetPadding");
    dropHintLayout->setContentsMargins(
        dropTargetPadding,
        dropTargetPadding,
        dropTargetPadding,
        dropTargetPadding
    );
    dropHintLayout->setSpacing(attachmentInputSpacing);
    QLabel *dropTargetIconLabel = iconLabel(
        dropTargetIcon(icons),
        QStringLiteral("dropTargetIcon"),
        style
    );
    QLabel *dropTargetLabel = label(
        payloadString(payload, "dropTargetTitle"),
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
    dropLayout->setSpacing(attachmentInputSpacing);
    QLineEdit *attachmentPath = new QLineEdit();
    attachmentPath->setPlaceholderText(payloadString(payload, "attachmentPlaceholder"));
    attachmentPath->setAcceptDrops(false);
    QPushButton *attachButton = new QPushButton(payloadString(payload, "attachTitle"));
    attachButton->setObjectName(QStringLiteral("secondaryButton"));
    attachButton->setIcon(attachButtonIcon(icons));
    applyButtonIconSize(attachButton, style);
    QPushButton *clearAttachmentsButton = new QPushButton(payloadString(payload, "clearAttachmentsTitle"));
    clearAttachmentsButton->setObjectName(QStringLiteral("secondaryButton"));
    dropLayout->addWidget(attachmentPath, 1);
    dropLayout->addWidget(attachButton);
    dropLayout->addWidget(clearAttachmentsButton);
    dropTargetLayout->addLayout(dropLayout);
    composerLayout->addWidget(dropTarget);

    QFrame *attachmentTray = QuillQtWidgets::frame(QStringLiteral("attachmentTray"));
    QVBoxLayout *attachmentTrayLayout = new QVBoxLayout(attachmentTray);
    attachmentTrayLayout->setContentsMargins(0, 0, 0, 0);
    attachmentTrayLayout->setSpacing(styleInt(style, "attachmentTraySpacing"));
    attachmentTrayLayout->addWidget(fieldLabel(payloadString(payload, "attachmentsTitle")));
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
    attachmentChipListLayout->setSpacing(styleInt(style, "attachmentTrayChipSpacing"));
    attachmentScrollArea->setWidget(attachmentChipList);
    attachmentTrayLayout->addWidget(attachmentScrollArea);
    attachmentTray->setVisible(false);
    composerLayout->addWidget(attachmentTray);

    QHBoxLayout *promptRow = new QHBoxLayout();
    promptRow->setContentsMargins(0, 0, 0, 0);
    promptRow->setSpacing(styleInt(style, "promptRowSpacing"));
    QPlainTextEdit *promptEditor = new QPlainTextEdit();
    promptEditor->setPlaceholderText(payloadString(payload, "composerPlaceholder"));
    promptEditor->setMinimumHeight(styleInt(style, "composerMinHeight"));
    promptEditor->setMaximumHeight(styleInt(style, "composerMaxHeight"));
    const QString sendTitle = payloadString(payload, "sendTitle");
    const QString stopTitle = payloadString(payload, "stopTitle");
    const QString stoppingStatus = payloadString(payload, "stoppingStatus");
    const QString attachmentsClearedStatus = payloadString(payload, "attachmentsClearedStatus");
    const QString attachmentRemovedEmptyStatus = payloadString(payload, "attachmentRemovedEmptyStatus");
    QPushButton *sendButton = new QPushButton();
    sendButton->setObjectName(QStringLiteral("sendButton"));
    updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle);
    applyButtonIconSize(sendButton, style);
    sendButton->setMinimumWidth(styleInt(style, "composerSendButtonMinWidth"));
    promptRow->addWidget(promptEditor, 1);
    promptRow->addWidget(sendButton, 0, Qt::AlignBottom);
    composerLayout->addLayout(promptRow);
    chatLayout->addWidget(composer);

    const QString attachmentDefaultPrompt = payloadString(payload, "attachmentDefaultPrompt");
    const QString attachmentDefaultPromptPlural = payloadString(payload, "attachmentDefaultPromptPlural");
    const QString attachmentSummaryTitle = payloadString(payload, "attachmentSummaryTitle");
    const AttachmentValidationPolicy attachmentPolicy = attachmentValidationPolicy(payload);
    const QString removeAttachmentTooltip = payloadString(payload, "removeAttachmentTooltip");
    const QString imageReadyStatusSingular = payloadString(payload, "imageReadyStatusSingular");
    const QString imageReadyStatusPluralUnit = payloadString(payload, "imageReadyStatusPluralUnit");
    QJsonArray fallbackMessages = payloadArray(payload, "messages");
    const QJsonArray prompts = payloadArray(payload, "prompts");
    const QString emptyStateTitle = payloadString(payload, "emptyStateTitle");
    const QString emptyStateSubtitle = payloadString(payload, "emptyStateSubtitle");
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
        addMessageBubble(
            messageLayout,
            message,
            style,
            userRoleLabel,
            assistantRoleLabel,
            systemRoleLabel
        );
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
            pendingAttachmentPaths.count(),
            attachmentDefaultPrompt,
            attachmentDefaultPromptPlural,
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
        const bool hasAttachmentPathInput = hasAttachmentPathCandidates(attachmentPath);
        attachButton->setEnabled(hasAttachmentPathInput);
        clearAttachmentsButton->setEnabled(hasAttachmentPathInput || hasPendingAttachments);
        sendButton->setEnabled(isLoading || hasTrimmedText(promptEditor) || hasPendingAttachments);
    };
    std::function<void()> renderAttachmentTray;
    renderAttachmentTray = [&]() {
        pendingAttachmentPaths = normalizedAttachmentPaths(pendingAttachmentPaths);
        clearLayout(attachmentChipListLayout);
        for (const QString &path : pendingAttachmentPaths) {
            QFrame *attachmentChip = QuillQtWidgets::frame(QStringLiteral("attachmentChip"));
            QHBoxLayout *attachmentChipLayout = new QHBoxLayout(attachmentChip);
            const int attachmentChipPadding = styleInt(style, "attachmentChipPadding");
            attachmentChipLayout->setContentsMargins(
                attachmentChipPadding,
                attachmentChipPadding,
                attachmentChipPadding,
                attachmentChipPadding
            );
            attachmentChipLayout->setSpacing(styleInt(style, "attachmentChipSpacing"));

            QLabel *attachmentIcon = iconLabel(
                attachmentChipIcon(icons),
                QStringLiteral("attachmentChipIcon"),
                style
            );

            QVBoxLayout *attachmentTextLayout = new QVBoxLayout();
            attachmentTextLayout->setContentsMargins(0, 0, 0, 0);
            attachmentTextLayout->setSpacing(styleInt(style, "attachmentChipTextSpacing"));
            QLabel *attachmentName = label(attachmentDisplayName(path), QStringLiteral("attachmentName"));
            attachmentName->setWordWrap(false);
            attachmentTextLayout->addWidget(attachmentName);

            const QString displaySize = attachmentDisplaySize(path);
            if (!displaySize.isEmpty()) {
                QLabel *attachmentSize = label(displaySize, QStringLiteral("attachmentSize"));
                attachmentSize->setWordWrap(false);
                attachmentTextLayout->addWidget(attachmentSize);
            }

            QPushButton *removeAttachmentButton = new QPushButton();
            removeAttachmentButton->setObjectName(QStringLiteral("chipRemoveButton"));
            removeAttachmentButton->setIcon(removeAttachmentButtonIcon(icons));
            applyButtonIconSize(removeAttachmentButton, style);
            removeAttachmentButton->setToolTip(removeAttachmentTooltip);
            removeAttachmentButton->setAccessibleName(removeAttachmentTooltip);
            removeAttachmentButton->setFixedWidth(styleInt(style, "attachmentRemoveButtonWidth"));
            QObject::connect(removeAttachmentButton, &QPushButton::clicked, [&, path]() {
                pendingAttachmentPaths.removeAll(path);
                statusText->setText(
                    pendingAttachmentPaths.isEmpty()
                        ? attachmentRemovedEmptyStatus
                        : attachmentReadyStatus(
                            pendingAttachmentPaths.count(),
                            imageReadyStatusSingular,
                            imageReadyStatusPluralUnit
                        )
                );
                QTimer::singleShot(0, attachmentTray, renderAttachmentTray);
            });

            attachmentChipLayout->addWidget(attachmentIcon);
            attachmentChipLayout->addLayout(attachmentTextLayout);
            attachmentChipLayout->addWidget(removeAttachmentButton);
            attachmentChipListLayout->addWidget(attachmentChip);
        }
        attachmentChipListLayout->addStretch(1);
        attachmentTray->setVisible(!pendingAttachmentPaths.isEmpty());
        updateComposerControlState();
    };
    auto addPendingAttachmentPaths = [&](const QStringList &rawPaths) -> bool {
        const AttachmentPathValidation validation = validatedAttachmentPaths(rawPaths, attachmentPolicy);
        bool accepted = false;
        for (const QString &path : validation.acceptedPaths) {
            if (pendingAttachmentPaths.contains(path)) {
                continue;
            }

            pendingAttachmentPaths.append(path);
            accepted = true;
        }

        if (!accepted) {
            if (!validation.lastError.isEmpty()) {
                statusText->setText(validation.lastError);
            }
            return false;
        }

        renderAttachmentTray();
        statusText->setText(attachmentReadyStatus(
            pendingAttachmentPaths.count(),
            imageReadyStatusSingular,
            imageReadyStatusPluralUnit
        ));
        return true;
    };
    dropTarget->setSupportedAttachmentExtensions(attachmentPolicy.supportedExtensions);
    dropTarget->setDropHandler([&](const QStringList &paths) {
        addPendingAttachmentPaths(paths);
    });
    auto clearAttachmentState = [&](const QString &nextStatus) {
        attachmentPath->clear();
        pendingAttachmentPaths.clear();
        clearLayout(attachmentChipListLayout);
        attachmentTray->setVisible(false);
        if (!nextStatus.isEmpty()) {
            statusText->setText(nextStatus);
        }
        updateComposerControlState();
    };
    auto triggerSendOrStop = [&]() {
        if (isLoading) {
            statusText->setText(stoppingStatus);
            return;
        }

        appendComposerMessage(promptEditor->toPlainText());
        clearAttachmentState(QString());
    };
    auto attachPendingPath = [&]() {
        const QStringList rawPaths = attachmentPathCandidatesFromInput(attachmentPath->text());
        if (rawPaths.isEmpty()) {
            return;
        }

        if (addPendingAttachmentPaths(rawPaths)) {
            attachmentPath->clear();
        }
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
            payloadString(payload, "status"),
            isLoading,
            userRoleLabel,
            assistantRoleLabel,
            systemRoleLabel
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
        icons = payloadObject(payload, "icons");
        isLoading = payloadBool(payload, "isLoading");
        models = payloadArray(payload, "models");
        conversations = payloadArray(payload, "conversations");
        selectedConversationID = payloadString(payload, "selectedConversationID");
        fallbackMessages = payloadArray(payload, "messages");
        const QString endpointText = payloadString(payload, "endpoint");
        if (endpointField->text() != endpointText) {
            QSignalBlocker blocker(endpointField);
            endpointField->setText(endpointText);
        }
        populateModelPicker(models, payloadString(payload, "selectedModel"));
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
            newConversationTitle
        ));
        statusText->setText(payloadString(payload, "status"));
        refreshButton->setEnabled(!isLoading);
        updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle);
        refreshStyle(sendButton);
        updateComposerControlState();
        modelStatus->setText(modelStatusText(
            modelPicker->currentText().trimmed().isEmpty()
                ? payloadString(payload, "selectedModel")
                : modelPicker->currentText(),
            chooseLocalModelStatus,
            usingModelStatusPrefix
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

    auto showSidebarUtilityPanel = [&](const QString &title, const QString &subtitle, const QString &status) {
        sidebarUtilityTitle->setText(title);
        sidebarUtilitySubtitle->setText(subtitle);
        sidebarUtilityPanel->setVisible(true);
        statusText->setText(status);
    };

    QObject::connect(newConversationButton, &QPushButton::clicked, [&]() {
        if (requestHistoryAction(QStringLiteral("newConversation"), QString(), QString(), QStringList())) {
            return;
        }

        conversationList->clearSelection();
        conversationList->setCurrentRow(-1);
        updateConversationSelectionStyles(conversationList);
        currentTitle->setText(newConversationTitle);
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
            currentTitle->setText(newConversationTitle);
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
        currentTitle->setText(newConversationTitle);
        renderMessageSet(QJsonArray());
        updateConversationActionState();
    });
    QObject::connect(completionsButton, &QPushButton::clicked, [&]() {
        showSidebarUtilityPanel(
            payloadString(payload, "completionsTitle"),
            payloadString(payload, "completionsPanelSubtitle"),
            payloadString(payload, "completionsStatus")
        );
    });
    QObject::connect(shortcutsButton, &QPushButton::clicked, [&]() {
        showSidebarUtilityPanel(
            payloadString(payload, "shortcutsTitle"),
            payloadString(payload, "shortcutsPanelSubtitle"),
            payloadString(payload, "shortcutsStatus")
        );
    });
    QObject::connect(settingsButton, &QPushButton::clicked, [&]() {
        showSidebarUtilityPanel(
            payloadString(payload, "settingsTitle"),
            payloadString(payload, "settingsPanelSubtitle"),
            payloadString(payload, "settingsStatus")
        );
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
            newConversationTitle
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
        modelStatus->setText(modelStatusText(model, chooseLocalModelStatus, usingModelStatusPrefix));
        requestHistoryAction(
            QStringLiteral("selectModel"),
            currentConversationID(conversationList, selectedConversationID),
            QString(),
            QStringList()
        );
    });
    QObject::connect(attachButton, &QPushButton::clicked, attachPendingPath);
    QObject::connect(attachmentPath, &QLineEdit::returnPressed, attachPendingPath);
    QObject::connect(clearAttachmentsButton, &QPushButton::clicked, [&]() {
        clearAttachmentState(attachmentsClearedStatus);
    });
    QObject::connect(attachmentPath, &QLineEdit::textChanged, [&]() {
        updateComposerControlState();
    });
    QObject::connect(promptEditor, &QPlainTextEdit::textChanged, [&]() {
        updateComposerControlState();
    });
    QShortcut *sendShortcut = new QShortcut(QKeySequence(QStringLiteral("Ctrl+Return")), promptEditor);
    sendShortcut->setContext(Qt::WidgetShortcut);
    QObject::connect(sendShortcut, &QShortcut::activated, triggerSendOrStop);
    promptEditor->installEventFilter(new ReturnSubmitFilter(triggerSendOrStop, promptEditor));
    QObject::connect(sendButton, &QPushButton::clicked, triggerSendOrStop);
    updateComposerControlState();
    updateConversationActionState();

    window.show();
    return app.exec();
}
