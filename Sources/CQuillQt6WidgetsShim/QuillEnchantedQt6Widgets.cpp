#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QAction>
#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QComboBox>
#include <QClipboard>
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
#include <QMenu>
#include <QMimeData>
#include <QObject>
#include <QPainter>
#include <QPaintEvent>
#include <QPen>
#include <QPlainTextEdit>
#include <QPixmap>
#include <QPointF>
#include <QPushButton>
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
using MessageEditAction = std::function<void(const QString &, const QString &)>;
using MessageCancelEditAction = std::function<void()>;

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
    if (normalized.contains(QStringLiteral("sidebar.left"))) {
        return themedActionIcon(QStringLiteral("view-sidebar-symbolic"), QStyle::SP_TitleBarMenuButton);
    }
    if (normalized.contains(QStringLiteral("line.3.horizontal"))) {
        return themedActionIcon(QStringLiteral("open-menu-symbolic"), QStyle::SP_TitleBarMenuButton);
    }
    if (normalized.contains(QStringLiteral("xmark.circle"))
        || normalized.contains(QStringLiteral("x.circle"))
        || normalized == QStringLiteral("xmark")) {
        return themedActionIcon(QStringLiteral("window-close-symbolic"), QStyle::SP_DialogCloseButton);
    }
    if (normalized.contains(QStringLiteral("pencil"))) {
        return themedActionIcon(QStringLiteral("document-edit-symbolic"), QStyle::SP_FileIcon);
    }
    if (normalized.contains(QStringLiteral("checkmark.square"))) {
        return themedActionIcon(QStringLiteral("checkbox-checked-symbolic"), QStyle::SP_DialogApplyButton);
    }
    if (normalized == QStringLiteral("square")) {
        return themedActionIcon(QStringLiteral("checkbox-symbolic"), QStyle::SP_TitleBarNormalButton);
    }
    if (normalized.contains(QStringLiteral("square.fill"))
        || normalized.contains(QStringLiteral("stop.fill"))) {
        return themedActionIcon(QStringLiteral("process-stop-symbolic"), QStyle::SP_MediaStop);
    }
    if (normalized.contains(QStringLiteral("speaker.slash"))) {
        return themedActionIcon(QStringLiteral("audio-volume-muted-symbolic"), QStyle::SP_MediaVolumeMuted);
    }
    if (normalized.contains(QStringLiteral("speaker.wave"))) {
        return themedActionIcon(QStringLiteral("audio-volume-high-symbolic"), QStyle::SP_MediaVolume);
    }
    if (normalized.contains(QStringLiteral("arrow.forward.circle.fill"))) {
        return themedActionIcon(QStringLiteral("go-next-symbolic"), QStyle::SP_MediaPlay);
    }
    if (normalized.contains(QStringLiteral("arrow.clockwise"))) {
        return themedActionIcon(QStringLiteral("view-refresh-symbolic"), QStyle::SP_BrowserReload);
    }
    if (normalized.contains(QStringLiteral("trash"))) {
        return themedActionIcon(QStringLiteral("user-trash-symbolic"), QStyle::SP_TrashIcon);
    }
    if (normalized.contains(QStringLiteral("doc.on.doc"))) {
        return themedActionIcon(QStringLiteral("edit-copy-symbolic"), QStyle::SP_FileIcon);
    }
    if (normalized.contains(QStringLiteral("selection.pin"))) {
        return themedActionIcon(QStringLiteral("edit-select-all-symbolic"), QStyle::SP_FileDialogDetailedView);
    }
    if (normalized.contains(QStringLiteral("doc.text"))) {
        return themedActionIcon(QStringLiteral("text-x-generic-symbolic"), QStyle::SP_FileIcon);
    }
    if (normalized.contains(QStringLiteral("curlybraces"))) {
        return themedActionIcon(QStringLiteral("applications-development-symbolic"), QStyle::SP_FileDialogDetailedView);
    }
    if (normalized.contains(QStringLiteral("ellipsis"))) {
        return themedActionIcon(QStringLiteral("view-more-symbolic"), QStyle::SP_TitleBarMenuButton);
    }
    if (normalized.contains(QStringLiteral("chevron.down"))) {
        return themedActionIcon(QStringLiteral("pan-down-symbolic"), QStyle::SP_ArrowDown);
    }
    if (normalized.contains(QStringLiteral("checkmark"))) {
        return themedActionIcon(QStringLiteral("emblem-ok-symbolic"), QStyle::SP_DialogApplyButton);
    }
    if (normalized.contains(QStringLiteral("paperplane"))) {
        return themedActionIcon(QStringLiteral("mail-send-symbolic"), QStyle::SP_CommandLink);
    }
    if (normalized.contains(QStringLiteral("photo"))) {
        return themedActionIcon(QStringLiteral("image-x-generic-symbolic"), QStyle::SP_FileIcon);
    }
    if (normalized.contains(QStringLiteral("water.waves"))) {
        return themedActionIcon(QStringLiteral("preferences-desktop-sound-symbolic"), QStyle::SP_MediaVolume);
    }
    if (normalized.contains(QStringLiteral("sun.max"))) {
        return themedActionIcon(QStringLiteral("weather-clear-symbolic"), QStyle::SP_DesktopIcon);
    }
    if (normalized.contains(QStringLiteral("waveform"))) {
        return themedActionIcon(QStringLiteral("audio-input-microphone-symbolic"), QStyle::SP_MediaPlay);
    }
    if (normalized.contains(QStringLiteral("info.circle"))) {
        return themedActionIcon(QStringLiteral("dialog-information-symbolic"), QStyle::SP_MessageBoxInformation);
    }
    if (normalized.contains(QStringLiteral("link"))) {
        return themedActionIcon(QStringLiteral("insert-link-symbolic"), QStyle::SP_CommandLink);
    }
    if (normalized.contains(QStringLiteral("character.cursor.ibeam"))
        || normalized.contains(QStringLiteral("textformat"))
        || normalized.contains(QStringLiteral("ibeam"))) {
        return themedActionIcon(QStringLiteral("accessories-text-editor-symbolic"), QStyle::SP_FileDialogDetailedView);
    }
    if (normalized == QStringLiteral("space")) {
        return themedActionIcon(QStringLiteral("input-keyboard-symbolic"), QStyle::SP_ComputerIcon);
    }
    if (normalized.contains(QStringLiteral("keyboard"))) {
        return themedActionIcon(QStringLiteral("input-keyboard-symbolic"), QStyle::SP_ComputerIcon);
    }
    if (normalized.contains(QStringLiteral("gearshape"))
        || normalized == QStringLiteral("gear")
        || normalized.contains(QStringLiteral("gear."))) {
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

QIcon unavailableModelButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "unavailableModel"));
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

QIcon refreshModelsButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "refreshModels"));
}

QIcon deleteChatButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "deleteChat"));
}

QIcon clearAllButtonIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "clearAll"));
}

QIcon copyMessageActionIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "copyMessage"));
}

QIcon editMessageActionIcon(const QJsonObject &icons) {
    return systemImageIcon(requiredIconName(icons, "editMessage"));
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

void addIconTextButtonContent(
    QPushButton *button,
    const QIcon &icon,
    const QString &title,
    const QString &iconObjectName,
    const QString &textObjectName,
    const char *spacingKey,
    const char *verticalPaddingKey,
    const char *horizontalPaddingKey,
    const QJsonObject &style
) {
    button->setAccessibleName(title);
    button->setAccessibleDescription(title);
    button->setToolTip(title);
    button->setStatusTip(title);

    QHBoxLayout *layout = new QHBoxLayout(button);
    const int verticalPadding = styleInt(style, verticalPaddingKey);
    const int horizontalPadding = styleInt(style, horizontalPaddingKey);
    layout->setContentsMargins(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding);
    layout->setSpacing(styleInt(style, spacingKey));

    QLabel *buttonIcon = iconLabel(icon, iconObjectName, style);
    buttonIcon->setAttribute(Qt::WA_TransparentForMouseEvents);
    QLabel *buttonText = label(title, textObjectName);
    buttonText->setAttribute(Qt::WA_TransparentForMouseEvents);
    layout->addWidget(buttonIcon, 0, Qt::AlignVCenter);
    layout->addWidget(buttonText, 0, Qt::AlignVCenter);
    layout->addStretch(1);
}

void updateIconTextButtonContent(
    QPushButton *button,
    const QIcon &icon,
    const QString &title,
    const QString &iconObjectName,
    const QString &textObjectName,
    const QJsonObject &style
) {
    button->setAccessibleName(title);
    button->setAccessibleDescription(title);
    button->setToolTip(title);
    button->setStatusTip(title);
    button->setText(QString());
    button->setIcon(QIcon());

    QLabel *buttonIcon = button->findChild<QLabel *>(iconObjectName);
    if (buttonIcon != nullptr) {
        const int iconSize = buttonIconSize(style);
        buttonIcon->setPixmap(icon.pixmap(iconSize, iconSize));
        buttonIcon->setFixedSize(iconSize, iconSize);
    }

    QLabel *buttonText = button->findChild<QLabel *>(textObjectName);
    if (buttonText != nullptr) {
        buttonText->setText(title);
    }
}

void updateSendButtonPresentation(
    QPushButton *button,
    const QJsonObject &icons,
    bool isLoading,
    const QString &sendTitle,
    const QString &stopTitle,
    const QJsonObject &style
) {
    const QString title = isLoading ? stopTitle : sendTitle;
    button->setProperty("loading", isLoading);
    updateIconTextButtonContent(
        button,
        sendButtonIcon(icons, isLoading),
        title,
        QStringLiteral("sendButtonIcon"),
        QStringLiteral("sendButtonText"),
        style
    );
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
    const QString messageEditBorderWidth = stylePixels(style, "messageEditBorderWidth");
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
        QFrame#messageUser[editing="true"] { border: %2 solid %1; }
    )")
        .arg(selected, messageEditBorderWidth);

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
        QLabel#primaryButtonIcon, QLabel#primaryButtonText, QLabel#sendButtonIcon, QLabel#sendButtonText { color: white; font-size: %1; }
        QLabel#sendButtonIcon:disabled, QLabel#sendButtonText:disabled { color: %2; }
    )")
        .arg(rootFontSize, disabledButtonForeground);

    sheet += QStringLiteral(R"(
        QPushButton#secondaryButton { background: transparent; color: %1; border: 1px solid %2; border-radius: %3; padding: %4 %5; text-align: left; }
        QPushButton#secondaryButton:disabled { color: %6; border: 1px solid %7; }
        QLabel#attachButtonIcon, QLabel#attachButtonText, QLabel#utilityButtonIcon, QLabel#utilityButtonText, QLabel#refreshButtonIcon, QLabel#refreshButtonText, QLabel#deleteButtonIcon, QLabel#deleteButtonText, QLabel#clearAllButtonIcon, QLabel#clearAllButtonText { color: %1; font-size: %8; }
        QLabel#attachButtonIcon:disabled, QLabel#attachButtonText:disabled, QLabel#utilityButtonIcon:disabled, QLabel#utilityButtonText:disabled, QLabel#refreshButtonIcon:disabled, QLabel#refreshButtonText:disabled, QLabel#deleteButtonIcon:disabled, QLabel#deleteButtonText:disabled, QLabel#clearAllButtonIcon:disabled, QLabel#clearAllButtonText:disabled { color: %6; }
    )")
        .arg(ink)
        .arg(controlBorder)
        .arg(secondaryButtonRadius)
        .arg(secondaryButtonVerticalPadding)
        .arg(secondaryButtonHorizontalPadding)
        .arg(disabledText)
        .arg(divider)
        .arg(rootFontSize);

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
        QFrame#markdownDivider { background: %1; border-radius: %3; }
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
        QFrame#dropTargetHint { background: %1; border: 0; border-radius: %4; }
        QLabel#dropTargetIcon, QLabel#dropTargetLabel { color: %2; font-size: %5; }
        QSplitter::handle { background: %3; }
    )")
        .arg(dropTarget, primary, divider, dropTargetRadius, captionFontSize);

    sheet += QStringLiteral(R"(
        QLineEdit, QComboBox { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; }
        QPlainTextEdit { background: %1; color: %2; border: 0; border-radius: %6; padding: %5; }
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

QString accessibilitySummary(const QString &title, const QString &detail) {
    const QString trimmedDetail = detail.trimmed();
    if (trimmedDetail.isEmpty()) {
        return title;
    }
    return title + QStringLiteral("\n") + trimmedDetail;
}

void applyActionAccessibility(QAction *action, const QString &title, const QString &objectName) {
    action->setObjectName(objectName);
    action->setToolTip(title);
    action->setStatusTip(title);
    action->setWhatsThis(title);
}

QString messageRole(const QJsonObject &message) {
    return requiredStringValue(message, "role");
}

QString messageContent(const QJsonObject &message) {
    return requiredStringValue(message, "content");
}

QString messageID(const QJsonObject &message) {
    return requiredStringValue(message, "id");
}

bool isEditableMessageRole(const QString &role) {
    return role == QStringLiteral("user");
}

void showMessageContextMenu(
    QWidget *anchor,
    const QPoint &position,
    const QString &id,
    const QString &role,
    const QString &content,
    const QJsonObject &icons,
    const QString &copyMessageTitle,
    const QString &editMessageTitle,
    const QString &unselectMessageTitle,
    const QString &editingMessageID,
    const MessageEditAction &editMessage,
    const MessageCancelEditAction &cancelEdit
) {
    QMenu menu(anchor);
    menu.setObjectName(QStringLiteral("message.contextMenu"));
    menu.setAccessibleName(copyMessageTitle);
    menu.setAccessibleDescription(copyMessageTitle);
    menu.setToolTipsVisible(true);
    QAction *copyAction = menu.addAction(copyMessageTitle);
    copyAction->setIcon(copyMessageActionIcon(icons));
    applyActionAccessibility(copyAction, copyMessageTitle, QStringLiteral("message.copy"));
    QObject::connect(copyAction, &QAction::triggered, anchor, [content](bool) {
        if (QClipboard *clipboard = QApplication::clipboard()) {
            clipboard->setText(content);
        }
    });
    if (isEditableMessageRole(role)) {
        QAction *editAction = menu.addAction(editMessageTitle);
        editAction->setIcon(editMessageActionIcon(icons));
        applyActionAccessibility(editAction, editMessageTitle, QStringLiteral("message.edit"));
        QObject::connect(editAction, &QAction::triggered, anchor, [id, content, editMessage](bool) {
            if (editMessage) {
                editMessage(id, content);
            }
        });
        if (!editingMessageID.isEmpty() && id == editingMessageID) {
            QAction *unselectAction = menu.addAction(unselectMessageTitle);
            unselectAction->setIcon(editMessageActionIcon(icons));
            applyActionAccessibility(unselectAction, unselectMessageTitle, QStringLiteral("message.unselect"));
            QObject::connect(unselectAction, &QAction::triggered, anchor, [cancelEdit](bool) {
                if (cancelEdit) {
                    cancelEdit();
                }
            });
        }
    }
    menu.exec(anchor->mapToGlobal(position));
}

void installMessageContextMenu(
    QWidget *widget,
    const QString &id,
    const QString &role,
    const QString &content,
    const QJsonObject &icons,
    const QString &copyMessageTitle,
    const QString &editMessageTitle,
    const QString &unselectMessageTitle,
    const QString &editingMessageID,
    const MessageEditAction &editMessage,
    const MessageCancelEditAction &cancelEdit
) {
    widget->setContextMenuPolicy(Qt::CustomContextMenu);
    QObject::connect(
        widget,
        &QWidget::customContextMenuRequested,
        widget,
        [
            widget,
            id,
            role,
            content,
            icons,
            copyMessageTitle,
            editMessageTitle,
            unselectMessageTitle,
            editingMessageID,
            editMessage,
            cancelEdit
        ](const QPoint &position) {
            showMessageContextMenu(
                widget,
                position,
                id,
                role,
                content,
                icons,
                copyMessageTitle,
                editMessageTitle,
                unselectMessageTitle,
                editingMessageID,
                editMessage,
                cancelEdit
            );
        }
    );
}

void installMessageContextMenuRecursively(
    QWidget *widget,
    const QString &id,
    const QString &role,
    const QString &content,
    const QJsonObject &icons,
    const QString &copyMessageTitle,
    const QString &editMessageTitle,
    const QString &unselectMessageTitle,
    const QString &editingMessageID,
    const MessageEditAction &editMessage,
    const MessageCancelEditAction &cancelEdit
) {
    installMessageContextMenu(
        widget,
        id,
        role,
        content,
        icons,
        copyMessageTitle,
        editMessageTitle,
        unselectMessageTitle,
        editingMessageID,
        editMessage,
        cancelEdit
    );
    const QList<QWidget *> children = widget->findChildren<QWidget *>();
    for (QWidget *child : children) {
        installMessageContextMenu(
            child,
            id,
            role,
            content,
            icons,
            copyMessageTitle,
            editMessageTitle,
            unselectMessageTitle,
            editingMessageID,
            editMessage,
            cancelEdit
        );
    }
}

QFrame *conversationRowWidget(
    const QJsonObject &conversation,
    const QJsonObject &style
) {
    QFrame *row = QuillQtWidgets::frame(QStringLiteral("conversationRow"));
    row->setProperty("active", false);
    const QString titleText = conversationTitle(conversation);
    const QString previewText = conversationLastMessage(conversation);
    const QString rowSummary = accessibilitySummary(titleText, previewText);
    row->setAccessibleName(titleText);
    row->setAccessibleDescription(rowSummary);
    row->setToolTip(rowSummary);
    row->setStatusTip(rowSummary);

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
    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft);

    QLabel *title = label(titleText, QStringLiteral("conversationTitle"));
    title->setWordWrap(false);
    title->setProperty("active", false);
    title->setToolTip(rowSummary);
    title->setStatusTip(rowSummary);

    layout->addWidget(title);
    if (!previewText.isEmpty()) {
        QLabel *preview = label(previewText, QStringLiteral("conversationPreview"));
        preview->setProperty("active", false);
        preview->setWordWrap(true);
        preview->setMaximumHeight(preview->fontMetrics().lineSpacing() * 2);
        preview->setToolTip(rowSummary);
        preview->setStatusTip(rowSummary);
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
    const QString cardSummary = accessibilitySummary(title, subtitle);
    card->setAccessibleName(title);
    card->setAccessibleDescription(cardSummary);
    card->setToolTip(cardSummary);
    card->setStatusTip(cardSummary);

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
    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
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
    const QString &usingModelStatusPrefix,
    const QString &usingModelStatusSeparator
) {
    const QString trimmedModel = selectedModel.trimmed();
    if (trimmedModel.isEmpty()) {
        return chooseLocalModelStatus;
    }

    return usingModelStatusPrefix + usingModelStatusSeparator + trimmedModel;
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

bool modelLikelySupportsImages(const QString &modelName) {
    const QString lowercasedName = modelName.trimmed().toLower();
    const QString gemma3Prefix = QStringLiteral("gemma3:");
    const QString gemma3Tag = lowercasedName.startsWith(gemma3Prefix)
        ? lowercasedName.mid(gemma3Prefix.size()).trimmed()
        : QString();
    const bool likelyVisionGemma3Model = lowercasedName == QStringLiteral("gemma3")
        || (
            lowercasedName.startsWith(gemma3Prefix)
            && (
                gemma3Tag.isEmpty()
                || gemma3Tag == QStringLiteral("latest")
                || gemma3Tag.startsWith(QStringLiteral("4b"))
                || gemma3Tag.startsWith(QStringLiteral("12b"))
                || gemma3Tag.startsWith(QStringLiteral("27b"))
            )
        );

    return likelyVisionGemma3Model
        || lowercasedName.contains(QStringLiteral("llava"))
        || lowercasedName.contains(QStringLiteral("vision"))
        || lowercasedName.contains(QStringLiteral("bakllava"))
        || lowercasedName.contains(QStringLiteral("moondream"))
        || lowercasedName.contains(QStringLiteral("minicpm-v"))
        || lowercasedName.contains(QStringLiteral("qwen2.5vl"))
        || lowercasedName.contains(QStringLiteral("qwen2.5-vl"))
        || lowercasedName.contains(QStringLiteral("qwen2-vl"))
        || lowercasedName.contains(QStringLiteral("qwen3-vl"))
        || lowercasedName.contains(QStringLiteral("qwen-vl"))
        || lowercasedName.contains(QStringLiteral("medgemma"))
        || lowercasedName.contains(QStringLiteral("mistral-small3.1"))
        || lowercasedName.contains(QStringLiteral("mistral-small3.2"));
}

bool selectedModelSupportsImages(QComboBox *modelPicker, const QJsonObject &payload) {
    const QString currentModel = modelPicker == nullptr ? QString() : modelPicker->currentText().trimmed();
    if (!currentModel.isEmpty()) {
        return modelLikelySupportsImages(currentModel);
    }

    return payloadBool(payload, "selectedModelSupportsImages");
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
    Divider,
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
    QChar marker;
    int markerCount = 0;
    QString language;
    bool isActive = false;
};

int markdownFenceMarkerCount(const QString &line, const QChar marker) {
    int count = 0;
    while (count < line.size() && line.at(count) == marker) {
        count += 1;
    }
    return count;
}

QString markdownFenceSuffix(const QString &line, const int markerCount) {
    return line.mid(markerCount);
}

bool isEscapableMarkdownPunctuation(const QChar ch) {
    switch (ch.toLatin1()) {
    case '!':
    case '#':
    case '(':
    case ')':
    case '*':
    case '+':
    case '-':
    case '.':
    case '<':
    case '>':
    case '[':
    case '\\':
    case ']':
    case '_':
    case '`':
    case '{':
    case '|':
    case '}':
    case '~':
        return true;
    default:
        return false;
    }
}

QString protectMarkdownBackslashEscapes(const QString &text) {
    QString protectedText;
    protectedText.reserve(text.size());

    for (int index = 0; index < text.size(); ++index) {
        const QChar character = text.at(index);
        if (character == QLatin1Char('\\') && index + 1 < text.size()) {
            const QChar next = text.at(index + 1);
            if (isEscapableMarkdownPunctuation(next)) {
                protectedText.append(QChar(static_cast<ushort>(0xE000 + next.unicode())));
                index += 1;
                continue;
            }
        }

        protectedText.append(character);
    }

    return protectedText;
}

QString restoreMarkdownBackslashEscapes(const QString &text) {
    QString restoredText;
    restoredText.reserve(text.size());

    for (const QChar character : text) {
        const ushort code = character.unicode();
        if (code >= 0xE000 && code <= 0xE07F) {
            restoredText.append(QChar(static_cast<ushort>(code - 0xE000)));
        } else {
            restoredText.append(character);
        }
    }

    return restoredText;
}

QChar protectedMarkdownCodeSpanCharacter(const QChar character) {
    const ushort code = character.unicode();
    if (code < 128 && (character == QLatin1Char('&') || isEscapableMarkdownPunctuation(character))) {
        return QChar(static_cast<ushort>(0xE000 + code));
    }

    return character;
}

QString protectedMarkdownCodeSpanContent(const QString &text) {
    QString protectedText;
    protectedText.reserve(text.size());

    for (const QChar character : text) {
        protectedText.append(protectedMarkdownCodeSpanCharacter(character));
    }

    return protectedText;
}

QString normalizedMarkdownCodeSpanContent(const QString &text) {
    if (text.size() < 2 || !text.at(0).isSpace() || !text.at(text.size() - 1).isSpace()) {
        return text;
    }

    bool hasContent = false;
    for (const QChar character : text) {
        if (!character.isSpace()) {
            hasContent = true;
            break;
        }
    }
    if (!hasContent) {
        return text;
    }

    return text.mid(1, text.size() - 2);
}

int markdownBacktickRunLength(const QString &text, const int start) {
    if (start >= text.size() || text.at(start) != QLatin1Char('`')) {
        return 0;
    }

    int length = 0;
    while (start + length < text.size() && text.at(start + length) == QLatin1Char('`')) {
        length += 1;
    }
    return length;
}

int matchingMarkdownBacktickRun(const QString &text, const int markerLength, const int start) {
    int index = start;
    while (index < text.size()) {
        if (markdownBacktickRunLength(text, index) == markerLength) {
            return index;
        }
        index += 1;
    }
    return -1;
}

QString removePairedMarkdownCodeSpanMarkers(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        const int markerLength = markdownBacktickRunLength(text, index);
        if (markerLength > 0) {
            const int contentStart = index + markerLength;
            const int closingIndex = matchingMarkdownBacktickRun(text, markerLength, contentStart);
            if (closingIndex > contentStart) {
                const QString content = text.mid(contentStart, closingIndex - contentStart);
                result.append(protectedMarkdownCodeSpanContent(normalizedMarkdownCodeSpanContent(content)));
                index = closingIndex + markerLength;
                continue;
            }
        }

        result.append(text.at(index));
        index += 1;
    }

    return result;
}

int closingMarkdownBracket(const QString &text, const int start) {
    bool escaped = false;
    for (int index = start; index < text.size(); ++index) {
        const QChar character = text.at(index);
        if (escaped) {
            escaped = false;
        } else if (character == QLatin1Char('\\')) {
            escaped = true;
        } else if (character == QLatin1Char(']')) {
            return index;
        }
    }

    return -1;
}

int closingMarkdownParenthesis(const QString &text, const int start) {
    int depth = 0;
    bool escaped = false;
    for (int index = start; index < text.size(); ++index) {
        const QChar character = text.at(index);
        if (escaped) {
            escaped = false;
        } else if (character == QLatin1Char('\\')) {
            escaped = true;
        } else if (character == QLatin1Char('(')) {
            depth += 1;
        } else if (character == QLatin1Char(')')) {
            if (depth == 0) {
                return index;
            }
            depth -= 1;
        }
    }

    return -1;
}

bool markdownLinkReferenceDefinition(const QString &rawLine) {
    const QString line = rawLine.trimmed();
    if (!line.startsWith(QLatin1Char('['))) {
        return false;
    }

    const int labelStart = 1;
    const int labelEnd = closingMarkdownBracket(line, labelStart);
    if (labelEnd <= labelStart) {
        return false;
    }

    const int colonIndex = labelEnd + 1;
    if (colonIndex >= line.size() || line.at(colonIndex) != QLatin1Char(':')) {
        return false;
    }

    return !line.mid(colonIndex + 1).trimmed().isEmpty();
}

bool isMarkdownImageLabelStart(const QString &text, const int index) {
    if (index <= 0) {
        return false;
    }

    const QChar previous = text.at(index - 1);
    return previous == QLatin1Char('!')
        || previous.unicode() == static_cast<ushort>(0xE000 + static_cast<ushort>('!'));
}

bool markdownImageReplacement(
    const QString &text,
    const int index,
    QString *replacement,
    int *endIndex
) {
    if (text.at(index) != QLatin1Char('!')) {
        return false;
    }

    const int labelStart = index + 1;
    if (labelStart >= text.size() || text.at(labelStart) != QLatin1Char('[')) {
        return false;
    }

    const int labelContentStart = labelStart + 1;
    const int labelEnd = closingMarkdownBracket(text, labelContentStart);
    if (labelEnd < 0) {
        return false;
    }

    const int destinationStartMarker = labelEnd + 1;
    if (destinationStartMarker >= text.size()
        || text.at(destinationStartMarker) != QLatin1Char('(')) {
        return false;
    }

    const int destinationStart = destinationStartMarker + 1;
    const int destinationEnd = closingMarkdownParenthesis(text, destinationStart);
    if (destinationEnd < 0) {
        return false;
    }

    if (replacement != nullptr) {
        *replacement = text.mid(labelContentStart, labelEnd - labelContentStart);
    }
    if (endIndex != nullptr) {
        *endIndex = destinationEnd + 1;
    }
    return true;
}

QString replaceMarkdownImages(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        QString replacement;
        int endIndex = index;
        if (markdownImageReplacement(text, index, &replacement, &endIndex)) {
            result.append(replacement);
            index = endIndex;
        } else {
            result.append(text.at(index));
            index += 1;
        }
    }

    return result;
}

bool markdownLinkReplacement(
    const QString &text,
    const int index,
    QString *replacement,
    int *endIndex
) {
    if (text.at(index) != QLatin1Char('[') || isMarkdownImageLabelStart(text, index)) {
        return false;
    }

    const int labelStart = index;
    const int labelContentStart = labelStart + 1;
    const int labelEnd = closingMarkdownBracket(text, labelContentStart);
    if (labelEnd < 0) {
        return false;
    }

    const int destinationStartMarker = labelEnd + 1;
    if (destinationStartMarker >= text.size()
        || text.at(destinationStartMarker) != QLatin1Char('(')) {
        return false;
    }

    const int destinationStart = destinationStartMarker + 1;
    const int destinationEnd = closingMarkdownParenthesis(text, destinationStart);
    if (destinationEnd < 0) {
        return false;
    }

    const QString label = text.mid(labelContentStart, labelEnd - labelContentStart);
    const QString destination = text.mid(destinationStart, destinationEnd - destinationStart);
    if (replacement != nullptr) {
        *replacement = label.isEmpty()
            ? QStringLiteral("(") + destination + QStringLiteral(")")
            : label + QStringLiteral(" (") + destination + QStringLiteral(")");
    }
    if (endIndex != nullptr) {
        *endIndex = destinationEnd + 1;
    }
    return true;
}

QString replaceMarkdownLinks(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        QString replacement;
        int endIndex = index;
        if (markdownLinkReplacement(text, index, &replacement, &endIndex)) {
            result.append(replacement);
            index = endIndex;
        } else {
            result.append(text.at(index));
            index += 1;
        }
    }

    return result;
}

bool markdownReferenceReplacement(
    const QString &text,
    const int labelStart,
    QString *replacement,
    int *endIndex
) {
    const int labelContentStart = labelStart + 1;
    const int labelEnd = closingMarkdownBracket(text, labelContentStart);
    if (labelEnd < 0) {
        return false;
    }

    const int referenceStart = labelEnd + 1;
    if (referenceStart >= text.size() || text.at(referenceStart) != QLatin1Char('[')) {
        return false;
    }

    const int referenceContentStart = referenceStart + 1;
    const int referenceEnd = closingMarkdownBracket(text, referenceContentStart);
    if (referenceEnd < 0) {
        return false;
    }

    const QString label = text.mid(labelContentStart, labelEnd - labelContentStart);
    if (label.isEmpty()) {
        return false;
    }

    if (replacement != nullptr) {
        *replacement = label;
    }
    if (endIndex != nullptr) {
        *endIndex = referenceEnd + 1;
    }
    return true;
}

bool markdownReferenceImageReplacement(
    const QString &text,
    const int index,
    QString *replacement,
    int *endIndex
) {
    if (text.at(index) != QLatin1Char('!')) {
        return false;
    }

    const int labelStart = index + 1;
    if (labelStart >= text.size() || text.at(labelStart) != QLatin1Char('[')) {
        return false;
    }

    return markdownReferenceReplacement(text, labelStart, replacement, endIndex);
}

QString replaceMarkdownReferenceImages(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        QString replacement;
        int endIndex = index;
        if (markdownReferenceImageReplacement(text, index, &replacement, &endIndex)) {
            result.append(replacement);
            index = endIndex;
        } else {
            result.append(text.at(index));
            index += 1;
        }
    }

    return result;
}

bool markdownReferenceLinkReplacement(
    const QString &text,
    const int index,
    QString *replacement,
    int *endIndex
) {
    if (text.at(index) != QLatin1Char('[') || isMarkdownImageLabelStart(text, index)) {
        return false;
    }

    return markdownReferenceReplacement(text, index, replacement, endIndex);
}

QString replaceMarkdownReferenceLinks(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        QString replacement;
        int endIndex = index;
        if (markdownReferenceLinkReplacement(text, index, &replacement, &endIndex)) {
            result.append(replacement);
            index = endIndex;
        } else {
            result.append(text.at(index));
            index += 1;
        }
    }

    return result;
}

bool isMarkdownAutolinkContent(const QString &text) {
    if (text.isEmpty()) {
        return false;
    }
    for (const QChar character : text) {
        if (character.isSpace()
            || character == QLatin1Char('<')
            || character == QLatin1Char('>')) {
            return false;
        }
    }

    const int colonIndex = text.indexOf(QLatin1Char(':'));
    if (colonIndex >= 0) {
        if (colonIndex < 2 || colonIndex > 32 || colonIndex + 1 >= text.size()) {
            return false;
        }
        if (!text.at(0).isLetter()) {
            return false;
        }
        for (int index = 0; index < colonIndex; ++index) {
            const QChar character = text.at(index);
            if (!character.isLetter()
                && !character.isNumber()
                && character != QLatin1Char('+')
                && character != QLatin1Char('.')
                && character != QLatin1Char('-')) {
                return false;
            }
        }
        return true;
    }

    const int atIndex = text.indexOf(QLatin1Char('@'));
    if (atIndex >= 0) {
        const QString localPart = text.left(atIndex);
        const QString domainPart = text.mid(atIndex + 1);
        return !localPart.isEmpty()
            && !domainPart.isEmpty()
            && domainPart.contains(QLatin1Char('.'));
    }

    return false;
}

QString replaceMarkdownAutolinks(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        if (text.at(index) == QLatin1Char('<')) {
            const int closingIndex = text.indexOf(QLatin1Char('>'), index + 1);
            if (closingIndex >= 0) {
                const QString content = text.mid(index + 1, closingIndex - index - 1);
                if (isMarkdownAutolinkContent(content)) {
                    result.append(content);
                    index = closingIndex + 1;
                    continue;
                }
            }
        }

        result.append(text.at(index));
        index += 1;
    }

    return result;
}

bool isAsciiMarkdownHtmlTagStart(const QChar ch) {
    const ushort scalar = ch.unicode();
    return (scalar >= 'A' && scalar <= 'Z') || (scalar >= 'a' && scalar <= 'z');
}

bool isAsciiMarkdownHtmlTagNameCharacter(const QChar ch) {
    const ushort scalar = ch.unicode();
    return (scalar >= 'A' && scalar <= 'Z')
        || (scalar >= 'a' && scalar <= 'z')
        || (scalar >= '0' && scalar <= '9')
        || scalar == '-';
}

bool isMarkdownInlineHtmlTagName(const QString &tagName) {
    return tagName == QStringLiteral("a")
        || tagName == QStringLiteral("abbr")
        || tagName == QStringLiteral("b")
        || tagName == QStringLiteral("br")
        || tagName == QStringLiteral("button")
        || tagName == QStringLiteral("code")
        || tagName == QStringLiteral("del")
        || tagName == QStringLiteral("div")
        || tagName == QStringLiteral("em")
        || tagName == QStringLiteral("i")
        || tagName == QStringLiteral("kbd")
        || tagName == QStringLiteral("li")
        || tagName == QStringLiteral("mark")
        || tagName == QStringLiteral("ol")
        || tagName == QStringLiteral("p")
        || tagName == QStringLiteral("pre")
        || tagName == QStringLiteral("s")
        || tagName == QStringLiteral("span")
        || tagName == QStringLiteral("strong")
        || tagName == QStringLiteral("sub")
        || tagName == QStringLiteral("sup")
        || tagName == QStringLiteral("u")
        || tagName == QStringLiteral("ul");
}

bool markdownInlineHtmlTagInsertsSpace(const QString &tagName) {
    return tagName == QStringLiteral("br")
        || tagName == QStringLiteral("div")
        || tagName == QStringLiteral("li")
        || tagName == QStringLiteral("p");
}

bool markdownInlineHtmlTagReplacement(
    const QString &text,
    const int index,
    int *endIndex,
    bool *insertsSpace
) {
    if (index >= text.size() || text.at(index) != QLatin1Char('<')) {
        return false;
    }

    int cursor = index + 1;
    if (cursor < text.size() && text.at(cursor) == QLatin1Char('/')) {
        cursor += 1;
    }
    if (cursor >= text.size() || !isAsciiMarkdownHtmlTagStart(text.at(cursor))) {
        return false;
    }

    const int tagStart = cursor;
    while (cursor < text.size() && isAsciiMarkdownHtmlTagNameCharacter(text.at(cursor))) {
        cursor += 1;
    }

    const QString tagName = text.mid(tagStart, cursor - tagStart).toLower();
    if (!isMarkdownInlineHtmlTagName(tagName)) {
        return false;
    }

    while (cursor < text.size() && text.at(cursor) != QLatin1Char('>')) {
        if (text.at(cursor) == QLatin1Char('<')) {
            return false;
        }
        cursor += 1;
    }
    if (cursor >= text.size()) {
        return false;
    }

    if (endIndex != nullptr) {
        *endIndex = cursor + 1;
    }
    if (insertsSpace != nullptr) {
        *insertsSpace = markdownInlineHtmlTagInsertsSpace(tagName);
    }
    return true;
}

QString removeMarkdownInlineHtml(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        if (text.at(index) == QLatin1Char('<')) {
            if (text.mid(index, 4) == QStringLiteral("<!--")) {
                const int closingIndex = text.indexOf(QStringLiteral("-->"), index + 4);
                if (closingIndex >= 0) {
                    index = closingIndex + 3;
                    continue;
                }
            }

            int endIndex = index;
            bool insertsSpace = false;
            if (markdownInlineHtmlTagReplacement(text, index, &endIndex, &insertsSpace)) {
                if (insertsSpace) {
                    result.append(QLatin1Char(' '));
                }
                index = endIndex;
                continue;
            }
        }

        result.append(text.at(index));
        index += 1;
    }

    return result;
}

bool markdownHtmlCommentBlock(const QString &rawLine, bool *continues) {
    const QString line = rawLine.trimmed();
    if (!line.startsWith(QStringLiteral("<!--"))) {
        return false;
    }

    if (continues != nullptr) {
        *continues = !line.contains(QStringLiteral("-->"));
    }
    return true;
}

bool closesMarkdownHtmlCommentBlock(const QString &rawLine) {
    return rawLine.contains(QStringLiteral("-->"));
}

QString markdownCodePointString(const uint codePoint) {
    const char32_t scalar = static_cast<char32_t>(codePoint);
    return QString::fromUcs4(&scalar, 1);
}

QString decodedMarkdownCharacterReference(const QString &reference) {
    if (reference == QStringLiteral("amp")) {
        return QStringLiteral("&");
    }
    if (reference == QStringLiteral("lt")) {
        return QStringLiteral("<");
    }
    if (reference == QStringLiteral("gt")) {
        return QStringLiteral(">");
    }
    if (reference == QStringLiteral("quot")) {
        return QStringLiteral("\"");
    }
    if (reference == QStringLiteral("apos")) {
        return QStringLiteral("'");
    }
    if (reference == QStringLiteral("nbsp")) {
        return markdownCodePointString(0x00A0);
    }
    if (reference == QStringLiteral("copy")) {
        return markdownCodePointString(0x00A9);
    }
    if (reference == QStringLiteral("reg")) {
        return markdownCodePointString(0x00AE);
    }
    if (reference == QStringLiteral("trade")) {
        return markdownCodePointString(0x2122);
    }
    if (reference == QStringLiteral("ndash")) {
        return markdownCodePointString(0x2013);
    }
    if (reference == QStringLiteral("mdash")) {
        return markdownCodePointString(0x2014);
    }
    if (reference == QStringLiteral("lsquo")) {
        return markdownCodePointString(0x2018);
    }
    if (reference == QStringLiteral("rsquo")) {
        return markdownCodePointString(0x2019);
    }
    if (reference == QStringLiteral("ldquo")) {
        return markdownCodePointString(0x201C);
    }
    if (reference == QStringLiteral("rdquo")) {
        return markdownCodePointString(0x201D);
    }
    if (reference == QStringLiteral("hellip")) {
        return markdownCodePointString(0x2026);
    }

    bool ok = false;
    uint codePoint = 0;
    if (reference.startsWith(QStringLiteral("#x")) || reference.startsWith(QStringLiteral("#X"))) {
        codePoint = reference.mid(2).toUInt(&ok, 16);
    } else if (reference.startsWith(QLatin1Char('#'))) {
        codePoint = reference.mid(1).toUInt(&ok, 10);
    }

    if (!ok
        || codePoint == 0
        || codePoint > 0x10FFFF
        || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
        return QString();
    }

    return markdownCodePointString(codePoint);
}

QString decodeMarkdownCharacterReferences(const QString &text) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        if (text.at(index) == QLatin1Char('&')) {
            const int semicolonIndex = text.indexOf(QLatin1Char(';'), index + 1);
            if (semicolonIndex >= 0) {
                const QString reference = text.mid(index + 1, semicolonIndex - index - 1);
                const QString decoded = decodedMarkdownCharacterReference(reference);
                if (!decoded.isEmpty()) {
                    result.append(decoded);
                    index = semicolonIndex + 1;
                    continue;
                }
            }
        }

        result.append(text.at(index));
        index += 1;
    }

    return result;
}

QString removePairedMarkdownSingleMarkers(QString text, const QChar marker) {
    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        if (text.at(index) == marker) {
            const int contentStart = index + 1;
            const int closingIndex = text.indexOf(marker, contentStart);
            if (closingIndex > contentStart) {
                result.append(text.mid(contentStart, closingIndex - contentStart));
                index = closingIndex + 1;
                continue;
            }
        }

        result.append(text.at(index));
        index += 1;
    }

    return result;
}

QString removePairedMarkdownMarkers(QString text, const QString &marker) {
    if (marker.isEmpty()) {
        return text;
    }

    QString result;
    result.reserve(text.size());

    int index = 0;
    while (index < text.size()) {
        if (text.mid(index, marker.size()) == marker) {
            const int contentStart = index + marker.size();
            const int closingIndex = text.indexOf(marker, contentStart);
            if (closingIndex > contentStart) {
                result.append(text.mid(contentStart, closingIndex - contentStart));
                index = closingIndex + marker.size();
                continue;
            }
        }

        result.append(text.at(index));
        index += 1;
    }

    return result;
}

QString cleanMarkdownInline(QString text) {
    text = protectMarkdownBackslashEscapes(text);
    text = removePairedMarkdownCodeSpanMarkers(text);
    text = replaceMarkdownImages(text);
    text = replaceMarkdownLinks(text);
    text = replaceMarkdownReferenceImages(text);
    text = replaceMarkdownReferenceLinks(text);
    text = replaceMarkdownAutolinks(text);
    text = removeMarkdownInlineHtml(text);
    text = decodeMarkdownCharacterReferences(text);
    text = removePairedMarkdownMarkers(text, QStringLiteral("**"));
    text = removePairedMarkdownMarkers(text, QStringLiteral("__"));
    text = removePairedMarkdownMarkers(text, QStringLiteral("`"));
    text = removePairedMarkdownMarkers(text, QStringLiteral("~~"));
    text = removePairedMarkdownSingleMarkers(text, QLatin1Char('*'));
    text = removePairedMarkdownSingleMarkers(text, QLatin1Char('_'));

    return restoreMarkdownBackslashEscapes(text).trimmed();
}

bool isMarkdownTaskListMarker(const QChar marker) {
    return marker == QLatin1Char(' ') || marker == QLatin1Char('x') || marker == QLatin1Char('X');
}

QString markdownTaskListItemText(const QString &text) {
    const QString trimmed = text.trimmed();
    if (trimmed.size() < 3 || trimmed.at(0) != QLatin1Char('[')) {
        return text;
    }
    if (!isMarkdownTaskListMarker(trimmed.at(1)) || trimmed.at(2) != QLatin1Char(']')) {
        return text;
    }
    if (trimmed.size() > 3 && !trimmed.at(3).isSpace()) {
        return text;
    }

    const QString remainder = trimmed.mid(3).trimmed();
    return remainder.isEmpty() ? text : remainder;
}

bool beginMarkdownFence(const QString &rawLine, MarkdownFence *fence) {
    const QString line = rawLine.trimmed();
    if (line.isEmpty()) {
        return false;
    }

    const QChar marker = line.at(0);
    if (marker != QLatin1Char('`') && marker != QLatin1Char('~')) {
        return false;
    }

    const int markerCount = markdownFenceMarkerCount(line, marker);
    if (markerCount < 3) {
        return false;
    }

    if (fence != nullptr) {
        fence->marker = marker;
        fence->markerCount = markerCount;
        fence->language = markdownFenceSuffix(line, markerCount).trimmed();
        fence->isActive = true;
    }
    return true;
}

bool closesMarkdownFence(const QString &rawLine, const MarkdownFence &fence) {
    if (!fence.isActive) {
        return false;
    }

    const QString line = rawLine.trimmed();
    const int closingCount = markdownFenceMarkerCount(line, fence.marker);
    if (closingCount < fence.markerCount) {
        return false;
    }

    return markdownFenceSuffix(line, closingCount).trimmed().isEmpty();
}

QString normalizedMarkdownHeadingText(QString text) {
    const QString normalized = text.trimmed();
    if (!normalized.endsWith(QLatin1Char('#'))) {
        return normalized;
    }

    int hashStart = normalized.size();
    while (hashStart > 0 && normalized.at(hashStart - 1) == QLatin1Char('#')) {
        hashStart -= 1;
    }

    if (hashStart <= 0 || !normalized.at(hashStart - 1).isSpace()) {
        return normalized;
    }

    const QString candidate = normalized.left(hashStart).trimmed();
    return candidate.isEmpty() ? normalized : candidate;
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
        *text = cleanMarkdownInline(normalizedMarkdownHeadingText(line.mid(markerCount)));
    }
    return true;
}

int setextMarkdownHeadingLevel(const QString &rawLine) {
    const QString line = rawLine.trimmed();
    if (line.isEmpty()) {
        return 0;
    }

    const QChar marker = line.at(0);
    if (marker != QLatin1Char('=') && marker != QLatin1Char('-')) {
        return 0;
    }

    for (const QChar character : line) {
        if (character != marker) {
            return 0;
        }
    }

    return marker == QLatin1Char('=') ? 1 : 2;
}

bool isMarkdownThematicBreak(const QString &rawLine) {
    const QString line = rawLine.trimmed();
    if (line.isEmpty()) {
        return false;
    }

    const QChar marker = line.at(0);
    if (marker != QLatin1Char('-') && marker != QLatin1Char('*') && marker != QLatin1Char('_')) {
        return false;
    }

    int markerCount = 0;
    for (const QChar character : line) {
        if (character == marker) {
            markerCount += 1;
        } else if (!character.isSpace()) {
            return false;
        }
    }

    return markerCount >= 3;
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

    const QString parsedText = cleanMarkdownInline(markdownTaskListItemText(line.mid(2).trimmed()));
    if (parsedText.isEmpty()) {
        return false;
    }
    if (text != nullptr) {
        *text = parsedText;
    }
    return true;
}

bool parseOrderedListLine(const QString &line, int *number, QString *text) {
    int index = 0;
    while (index < line.size() && line.at(index).isDigit()) {
        index += 1;
    }
    if (index == 0 || index >= line.size()) {
        return false;
    }

    const QChar marker = line.at(index);
    if (marker != QLatin1Char('.') && marker != QLatin1Char(')')) {
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
    const QString parsedText = cleanMarkdownInline(markdownTaskListItemText(line.mid(textStart + 1).trimmed()));
    if (parsedText.isEmpty()) {
        return false;
    }

    if (text != nullptr) {
        *text = parsedText;
    }
    return true;
}

QString normalizedMarkdownQuoteText(const QString &line) {
    if (!line.startsWith(QLatin1Char('>'))) {
        return QString();
    }
    return line.mid(1).trimmed();
}

bool parseQuoteLine(const QString &line, QString *text) {
    const QString quoteText = normalizedMarkdownQuoteText(line);
    if (quoteText.isEmpty()) {
        return false;
    }
    if (text != nullptr) {
        *text = cleanMarkdownInline(quoteText);
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
    bool skippingHtmlCommentBlock = false;

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
    for (int lineIndex = 0; lineIndex < lines.size(); ++lineIndex) {
        const QString &rawLine = lines.at(lineIndex);
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

        if (skippingHtmlCommentBlock) {
            if (closesMarkdownHtmlCommentBlock(rawLine)) {
                skippingHtmlCommentBlock = false;
            }
            continue;
        }

        bool commentContinues = false;
        if (markdownHtmlCommentBlock(rawLine, &commentContinues)) {
            flushParagraph();
            skippingHtmlCommentBlock = commentContinues;
            continue;
        }

        if (markdownLinkReferenceDefinition(rawLine)) {
            flushParagraph();
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
        } else if (isMarkdownThematicBreak(line)) {
            flushParagraph();
            appendBlock(MarkdownBlockKind::Divider, QString());
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
            const int setextLevel = lineIndex + 1 < lines.size()
                ? setextMarkdownHeadingLevel(lines.at(lineIndex + 1))
                : 0;
            if (setextLevel > 0) {
                paragraphLines.append(line);
                const QString headingText = cleanMarkdownInline(paragraphLines.join(QStringLiteral(" ")));
                paragraphLines.clear();
                if (!headingText.isEmpty()) {
                    appendBlock(MarkdownBlockKind::Heading, headingText, setextLevel);
                }
                ++lineIndex;
            } else {
                paragraphLines.append(line);
            }
        }
    }

    if (activeFence.isActive) {
        flushCodeBlock();
    } else {
        flushParagraph();
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

QWidget *markdownDividerWidget(const QJsonObject &style) {
    QWidget *container = new QWidget();
    QVBoxLayout *layout = new QVBoxLayout(container);
    const int verticalPadding = styleInt(style, "markdownQuoteVerticalPadding");
    const int markdownQuoteRuleWidth = styleInt(style, "markdownQuoteRuleWidth");
    layout->setContentsMargins(0, verticalPadding, 0, verticalPadding);
    layout->setSpacing(0);

    QFrame *rule = QuillQtWidgets::frame(QStringLiteral("markdownDivider"));
    rule->setFixedHeight(markdownQuoteRuleWidth);
    rule->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    layout->addWidget(rule);
    return container;
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
    QList<MarkdownBlock> blocks = parseMarkdownBlocks(markdown);
    if (blocks.isEmpty()) {
        MarkdownBlock emptyParagraph;
        emptyParagraph.kind = MarkdownBlockKind::Paragraph;
        blocks.append(emptyParagraph);
    }

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
        case MarkdownBlockKind::Divider:
            layout->addWidget(markdownDividerWidget(style));
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
        const QSize rowSizeHint = rowWidget->sizeHint();
        item->setSizeHint(QSize(0, rowSizeHint.height()));
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
    const QJsonObject &icons,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel,
    const QString &copyMessageTitle,
    const QString &editMessageTitle,
    const QString &unselectMessageTitle,
    const QString &editingMessageID,
    const MessageEditAction &editMessage,
    const MessageCancelEditAction &cancelEdit
) {
    const QString id = messageID(message);
    const QString role = messageRole(message);
    const QString content = messageContent(message);
    QString objectName = QStringLiteral("messageAssistant");
    if (role == QStringLiteral("user")) {
        objectName = QStringLiteral("messageUser");
    } else if (role == QStringLiteral("system")) {
        objectName = QStringLiteral("messageSystem");
    }

    QFrame *bubble = QuillQtWidgets::frame(objectName);
    bubble->setProperty(
        "editing",
        isEditableMessageRole(role) && !editingMessageID.isEmpty() && id == editingMessageID
    );
    const QString title = messageRoleTitle(role, userRoleLabel, assistantRoleLabel, systemRoleLabel);
    const QString summary = accessibilitySummary(title, content);
    bubble->setAccessibleName(title);
    bubble->setAccessibleDescription(summary);
    bubble->setToolTip(summary);
    bubble->setStatusTip(summary);

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
    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    layout->addWidget(label(
        title,
        role == QStringLiteral("user") ? QStringLiteral("messageUserRole") : QStringLiteral("messageRole")
    ));
    if (role == QStringLiteral("user")) {
        layout->addWidget(label(content, QStringLiteral("messageUserText")));
    } else {
        layout->addWidget(markdownMessageWidget(content, style));
    }
    installMessageContextMenuRecursively(
        bubble,
        id,
        role,
        content,
        icons,
        copyMessageTitle,
        editMessageTitle,
        unselectMessageTitle,
        editingMessageID,
        editMessage,
        cancelEdit
    );
    return bubble;
}

void addMessageBubble(
    QVBoxLayout *messageLayout,
    const QJsonObject &message,
    const QJsonObject &style,
    const QJsonObject &icons,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel,
    const QString &copyMessageTitle,
    const QString &editMessageTitle,
    const QString &unselectMessageTitle,
    const QString &editingMessageID,
    const MessageEditAction &editMessage,
    const MessageCancelEditAction &cancelEdit
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
        icons,
        userRoleLabel,
        assistantRoleLabel,
        systemRoleLabel,
        copyMessageTitle,
        editMessageTitle,
        unselectMessageTitle,
        editingMessageID,
        editMessage,
        cancelEdit
    ), 0, Qt::AlignTop);
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
    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    const int promptButtonWidth = styleInt(style, "promptButtonWidth");
    QVBoxLayout *headerLayout = new QVBoxLayout();
    headerLayout->setContentsMargins(0, 0, 0, 0);
    headerLayout->setSpacing(styleInt(style, "emptyStateHeaderSpacing"));
    headerLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    headerLayout->addWidget(label(title, QStringLiteral("currentTitle")));
    QLabel *subtitleLabel = label(subtitle, QStringLiteral("caption"));
    subtitleLabel->setFixedWidth(promptButtonWidth);
    subtitleLabel->setVisible(!subtitle.trimmed().isEmpty());
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
        button->setAccessibleDescription(prompt);
        button->setToolTip(prompt);
        button->setStatusTip(prompt);
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
    messageLayout->addWidget(emptyState, 0, Qt::AlignLeft | Qt::AlignTop);
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
    const QJsonObject &icons,
    const QString &emptyStateTitle,
    const QString &emptyStateSubtitle,
    const PromptAction &promptAction,
    const QString &status,
    bool isLoading,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel,
    const QString &copyMessageTitle,
    const QString &editMessageTitle,
    const QString &unselectMessageTitle,
    const QString &editingMessageID,
    const MessageEditAction &editMessage,
    const MessageCancelEditAction &cancelEdit
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
            icons,
            userRoleLabel,
            assistantRoleLabel,
            systemRoleLabel,
            copyMessageTitle,
            editMessageTitle,
            unselectMessageTitle,
            editingMessageID,
            editMessage,
            cancelEdit
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

    void resetDragState() {
        setDragActive(false);
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
    groupLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    field->setAccessibleName(title);
    field->setAccessibleDescription(title);
    field->setToolTip(title);
    field->setStatusTip(title);
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
    const QString usingModelStatusSeparator = payloadString(payload, "usingModelStatusSeparator");
    const QString newConversationButtonTitle = payloadString(payload, "newConversationButtonTitle");
    const QString newConversationTitle = payloadString(payload, "newConversationTitle");
    const QString userRoleLabel = payloadString(payload, "userRoleLabel");
    const QString assistantRoleLabel = payloadString(payload, "assistantRoleLabel");
    const QString systemRoleLabel = payloadString(payload, "systemRoleLabel");
    const QString copyMessageTitle = payloadString(payload, "copyMessageTitle");
    const QString editMessageTitle = payloadString(payload, "editMessageTitle");
    const QString unselectMessageTitle = payloadString(payload, "unselectMessageTitle");
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
    sidebarLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft);

    QWidget *sidebarTitleBlock = new QWidget();
    QVBoxLayout *sidebarTitleLayout = new QVBoxLayout(sidebarTitleBlock);
    sidebarTitleLayout->setContentsMargins(0, 0, 0, 0);
    sidebarTitleLayout->setSpacing(styleInt(style, "sidebarTitleSpacing"));
    sidebarTitleLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    sidebarTitleLayout->addWidget(label(
        payloadString(payload, "sidebarTitle"),
        QStringLiteral("appTitle")
    ));
    sidebarTitleLayout->addWidget(label(
        payloadString(payload, "sidebarSubtitle"),
        QStringLiteral("caption")
    ));
    sidebarLayout->addWidget(sidebarTitleBlock);

    QPushButton *newConversationButton = new QPushButton();
    newConversationButton->setObjectName(QStringLiteral("primaryButton"));
    addIconTextButtonContent(
        newConversationButton,
        newConversationButtonIcon(icons),
        newConversationButtonTitle,
        QStringLiteral("primaryButtonIcon"),
        QStringLiteral("primaryButtonText"),
        "primaryButtonIconSpacing",
        "primaryButtonVerticalPadding",
        "primaryButtonHorizontalPadding",
        style
    );
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
    const QString noModelsTitle = payloadString(payload, "noModelsTitle");
    QComboBox *modelPicker = new QComboBox();
    QLabel *noModelsNotice = label(
        noModelsTitle,
        QStringLiteral("warningText")
    );
    noModelsNotice->setAccessibleName(noModelsTitle);
    noModelsNotice->setAccessibleDescription(noModelsTitle);
    noModelsNotice->setToolTip(noModelsTitle);
    noModelsNotice->setStatusTip(noModelsTitle);
    auto updateModelPickerAccessibility = [&]() {
        const QString selectedModelText = modelPicker->currentText().trimmed();
        const QString modelValue = selectedModelText.isEmpty() ? modelLabel : selectedModelText;
        modelPicker->setAccessibleName(modelLabel);
        modelPicker->setAccessibleDescription(modelValue);
        modelPicker->setToolTip(modelValue);
        modelPicker->setStatusTip(modelValue);
    };
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
        updateModelPickerAccessibility();
    };
    populateModelPicker(models, payloadString(payload, "selectedModel"));
    addSidebarField(
        sidebarLayout,
        modelLabel,
        modelPicker,
        style
    );
    updateModelPickerAccessibility();
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
    const QString initialStatus = payloadString(payload, "status");
    QLabel *statusText = label(initialStatus, QStringLiteral("statusText"));
    const int statusTextWidth = styleInt(style, "statusTextWidth");
    statusText->setFixedWidth(statusTextWidth);
    auto updateStatusAccessibility = [&](const QString &status) {
        statusDot->setAccessibleName(status);
        statusDot->setAccessibleDescription(status);
        statusDot->setToolTip(status);
        statusDot->setStatusTip(status);
        statusText->setAccessibleName(status);
        statusText->setAccessibleDescription(status);
        statusText->setToolTip(status);
        statusText->setStatusTip(status);
    };
    updateStatusAccessibility(initialStatus);
    auto setStatusText = [&](const QString &status) {
        statusText->setText(status);
        updateStatusAccessibility(status);
    };
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
    const QString deleteChatTitle = payloadString(payload, "deleteChatTitle");
    QPushButton *deleteButton = new QPushButton();
    deleteButton->setObjectName(QStringLiteral("secondaryButton"));
    addIconTextButtonContent(
        deleteButton,
        deleteChatButtonIcon(icons),
        deleteChatTitle,
        QStringLiteral("deleteButtonIcon"),
        QStringLiteral("deleteButtonText"),
        "actionButtonIconSpacing",
        "secondaryButtonVerticalPadding",
        "secondaryButtonHorizontalPadding",
        style
    );
    const QString clearAllTitle = payloadString(payload, "clearAllTitle");
    QPushButton *clearAllButton = new QPushButton();
    clearAllButton->setObjectName(QStringLiteral("secondaryButton"));
    addIconTextButtonContent(
        clearAllButton,
        clearAllButtonIcon(icons),
        clearAllTitle,
        QStringLiteral("clearAllButtonIcon"),
        QStringLiteral("clearAllButtonText"),
        "actionButtonIconSpacing",
        "secondaryButtonVerticalPadding",
        "secondaryButtonHorizontalPadding",
        style
    );
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
    auto configureUtilityButton = [&](QPushButton *button, const QString &title, const char *iconKey) {
        button->setObjectName(QStringLiteral("secondaryButton"));
        addIconTextButtonContent(
            button,
            utilityButtonIcon(icons, iconKey),
            title,
            QStringLiteral("utilityButtonIcon"),
            QStringLiteral("utilityButtonText"),
            "actionButtonIconSpacing",
            "secondaryButtonVerticalPadding",
            "secondaryButtonHorizontalPadding",
            style
        );
    };
    QPushButton *completionsButton = new QPushButton();
    configureUtilityButton(completionsButton, payloadString(payload, "completionsTitle"), "completions");
    QPushButton *shortcutsButton = new QPushButton();
    configureUtilityButton(shortcutsButton, payloadString(payload, "shortcutsTitle"), "shortcuts");
    QPushButton *settingsButton = new QPushButton();
    configureUtilityButton(settingsButton, payloadString(payload, "settingsTitle"), "settings");
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
    titleLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
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
        modelStatusText(payloadString(payload, "selectedModel"), chooseLocalModelStatus, usingModelStatusPrefix, usingModelStatusSeparator),
        QStringLiteral("caption")
    );
    const int headerTitleWidth = styleInt(style, "headerTitleWidth");
    currentTitle->setFixedWidth(headerTitleWidth);
    modelStatus->setFixedWidth(headerTitleWidth);
    auto updateHeaderTitleAccessibility = [&](const QString &title) {
        currentTitle->setAccessibleName(title);
        currentTitle->setAccessibleDescription(title);
        currentTitle->setToolTip(title);
        currentTitle->setStatusTip(title);
    };
    auto updateModelStatusAccessibility = [&](const QString &status) {
        modelStatus->setAccessibleName(status);
        modelStatus->setAccessibleDescription(status);
        modelStatus->setToolTip(status);
        modelStatus->setStatusTip(status);
    };
    updateHeaderTitleAccessibility(currentTitle->text());
    updateModelStatusAccessibility(modelStatus->text());
    titleLayout->addWidget(currentTitle);
    titleLayout->addWidget(modelStatus);
    headerLayout->addLayout(titleLayout, 1);
    const QString refreshModelsTitle = payloadString(payload, "refreshModelsTitle");
    QPushButton *refreshButton = new QPushButton();
    refreshButton->setObjectName(QStringLiteral("secondaryButton"));
    addIconTextButtonContent(
        refreshButton,
        refreshModelsButtonIcon(icons),
        refreshModelsTitle,
        QStringLiteral("refreshButtonIcon"),
        QStringLiteral("refreshButtonText"),
        "actionButtonIconSpacing",
        "secondaryButtonVerticalPadding",
        "secondaryButtonHorizontalPadding",
        style
    );
    refreshButton->setAccessibleName(refreshModelsTitle);
    refreshButton->setAccessibleDescription(refreshModelsTitle);
    refreshButton->setToolTip(refreshModelsTitle);
    refreshButton->setStatusTip(refreshModelsTitle);
    refreshButton->setEnabled(!isLoading);
    headerLayout->addWidget(refreshButton, 0, Qt::AlignVCenter);
    chatLayout->addWidget(header);

    QScrollArea *scrollArea = new QScrollArea();
    scrollArea->setWidgetResizable(true);
    QWidget *transcript = new QWidget();
    QVBoxLayout *messageLayout = new QVBoxLayout(transcript);
    const int contentPadding = styleInt(style, "contentPadding");
    messageLayout->setContentsMargins(contentPadding, contentPadding, contentPadding, contentPadding);
    const int messageSpacing = styleInt(style, "messageSpacing");
    messageLayout->setSpacing(messageSpacing);
    messageLayout->setAlignment(Qt::AlignTop);
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
    composerBandLayout->addWidget(composerContent, 0, Qt::AlignHCenter);
    composerBandLayout->addStretch(1);

    const int attachmentInputSpacing = styleInt(style, "attachmentInputSpacing");
    const QString dropTargetTitle = payloadString(payload, "dropTargetTitle");
    AttachmentDropFrame *dropTarget = new AttachmentDropFrame();
    dropTarget->setAccessibleName(dropTargetTitle);
    dropTarget->setAccessibleDescription(dropTargetTitle);
    dropTarget->setToolTip(dropTargetTitle);
    dropTarget->setStatusTip(dropTargetTitle);
    QVBoxLayout *dropTargetLayout = new QVBoxLayout(dropTarget);
    dropTargetLayout->setContentsMargins(0, 0, 0, 0);
    dropTargetLayout->setSpacing(attachmentInputSpacing);

    QFrame *dropHint = QuillQtWidgets::frame(QStringLiteral("dropTargetHint"));
    dropHint->setAccessibleName(dropTargetTitle);
    dropHint->setAccessibleDescription(dropTargetTitle);
    dropHint->setToolTip(dropTargetTitle);
    dropHint->setStatusTip(dropTargetTitle);
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
        dropTargetTitle,
        QStringLiteral("dropTargetLabel")
    );
    dropHintLayout->addWidget(dropTargetIconLabel, 0, Qt::AlignVCenter);
    dropHintLayout->addWidget(dropTargetLabel, 0, Qt::AlignVCenter);
    dropHintLayout->addStretch(1);
    dropHint->setVisible(false);
    dropTarget->setDropHint(dropHint);
    dropTargetLayout->addWidget(dropHint);

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
    dropTargetLayout->addWidget(attachmentTray);

    QWidget *attachmentInputRow = new QWidget();
    QHBoxLayout *dropLayout = new QHBoxLayout(attachmentInputRow);
    dropLayout->setContentsMargins(0, 0, 0, 0);
    dropLayout->setSpacing(attachmentInputSpacing);
    QLineEdit *attachmentPath = new QLineEdit();
    const QString attachmentPlaceholder = payloadString(payload, "attachmentPlaceholder");
    attachmentPath->setPlaceholderText(attachmentPlaceholder);
    attachmentPath->setAccessibleName(attachmentPlaceholder);
    attachmentPath->setAccessibleDescription(attachmentPlaceholder);
    attachmentPath->setToolTip(attachmentPlaceholder);
    attachmentPath->setStatusTip(attachmentPlaceholder);
    attachmentPath->setAcceptDrops(false);
    const QString attachTitle = payloadString(payload, "attachTitle");
    QPushButton *unavailableModelButton = new QPushButton();
    unavailableModelButton->setObjectName(QStringLiteral("secondaryButton"));
    unavailableModelButton->setIcon(unavailableModelButtonIcon(icons));
    applyButtonIconSize(unavailableModelButton, style);
    unavailableModelButton->setToolTip(chooseLocalModelStatus);
    unavailableModelButton->setAccessibleName(modelLabel);
    unavailableModelButton->setAccessibleDescription(chooseLocalModelStatus);
    unavailableModelButton->setStatusTip(chooseLocalModelStatus);
    unavailableModelButton->setEnabled(false);
    QPushButton *attachButton = new QPushButton();
    attachButton->setObjectName(QStringLiteral("secondaryButton"));
    addIconTextButtonContent(
        attachButton,
        attachButtonIcon(icons),
        attachTitle,
        QStringLiteral("attachButtonIcon"),
        QStringLiteral("attachButtonText"),
        "actionButtonIconSpacing",
        "secondaryButtonVerticalPadding",
        "secondaryButtonHorizontalPadding",
        style
    );
    attachButton->setAccessibleName(attachTitle);
    attachButton->setAccessibleDescription(attachTitle);
    attachButton->setToolTip(attachTitle);
    attachButton->setStatusTip(attachTitle);
    const QString clearAttachmentsTitle = payloadString(payload, "clearAttachmentsTitle");
    QPushButton *clearAttachmentsButton = new QPushButton(clearAttachmentsTitle);
    clearAttachmentsButton->setObjectName(QStringLiteral("secondaryButton"));
    clearAttachmentsButton->setAccessibleName(clearAttachmentsTitle);
    clearAttachmentsButton->setAccessibleDescription(clearAttachmentsTitle);
    clearAttachmentsButton->setToolTip(clearAttachmentsTitle);
    clearAttachmentsButton->setStatusTip(clearAttachmentsTitle);
    dropLayout->addWidget(attachmentPath, 1, Qt::AlignVCenter);
    dropLayout->addWidget(unavailableModelButton, 0, Qt::AlignVCenter);
    dropLayout->addWidget(attachButton, 0, Qt::AlignVCenter);
    dropLayout->addWidget(clearAttachmentsButton, 0, Qt::AlignVCenter);
    dropTargetLayout->addWidget(attachmentInputRow);
    composerLayout->addWidget(dropTarget);

    QHBoxLayout *promptRow = new QHBoxLayout();
    promptRow->setContentsMargins(0, 0, 0, 0);
    promptRow->setSpacing(styleInt(style, "promptRowSpacing"));
    QPlainTextEdit *promptEditor = new QPlainTextEdit();
    const QString composerPlaceholder = payloadString(payload, "composerPlaceholder");
    promptEditor->setPlaceholderText(composerPlaceholder);
    promptEditor->setAccessibleName(composerPlaceholder);
    promptEditor->setAccessibleDescription(composerPlaceholder);
    promptEditor->setToolTip(composerPlaceholder);
    promptEditor->setStatusTip(composerPlaceholder);
    promptEditor->setMinimumHeight(styleInt(style, "composerMinHeight"));
    promptEditor->setMaximumHeight(styleInt(style, "composerMaxHeight"));
    const QString sendTitle = payloadString(payload, "sendTitle");
    const QString stopTitle = payloadString(payload, "stopTitle");
    const QString stoppingStatus = payloadString(payload, "stoppingStatus");
    const QString attachmentsClearedStatus = payloadString(payload, "attachmentsClearedStatus");
    const QString attachmentRemovedEmptyStatus = payloadString(payload, "attachmentRemovedEmptyStatus");
    QPushButton *sendButton = new QPushButton();
    sendButton->setObjectName(QStringLiteral("sendButton"));
    addIconTextButtonContent(
        sendButton,
        sendButtonIcon(icons, isLoading),
        isLoading ? stopTitle : sendTitle,
        QStringLiteral("sendButtonIcon"),
        QStringLiteral("sendButtonText"),
        "actionButtonIconSpacing",
        "primaryButtonVerticalPadding",
        "primaryButtonHorizontalPadding",
        style
    );
    updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle, style);
    sendButton->setMinimumWidth(styleInt(style, "composerSendButtonMinWidth"));
    promptRow->addWidget(promptEditor, 1, Qt::AlignBottom);
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
    std::function<bool(const QString &, const QString &, const QString &, const QString &, const QStringList &)> requestHistoryAction;
    QString editingMessageID;
    std::function<void()> rerenderCurrentMessages;
    auto clearEditingMessage = [&]() {
        if (editingMessageID.isEmpty()) {
            return;
        }

        editingMessageID.clear();
        if (rerenderCurrentMessages) {
            rerenderCurrentMessages();
        }
    };
    const MessageEditAction editMessage = [&](const QString &messageID, const QString &message) {
        editingMessageID = messageID;
        promptEditor->setPlainText(message);
        promptEditor->setFocus(Qt::OtherFocusReason);
        if (rerenderCurrentMessages) {
            rerenderCurrentMessages();
        }
    };
    auto renderLocalUserMessage = [&](const QString &rawText) {
        const QString text = rawText.trimmed();
        if (text.isEmpty()) {
            return;
        }

        QJsonObject message;
        message.insert(QStringLiteral("id"), QStringLiteral("local-user-message"));
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
            icons,
            userRoleLabel,
            assistantRoleLabel,
            systemRoleLabel,
            copyMessageTitle,
            editMessageTitle,
            unselectMessageTitle,
            editingMessageID,
            editMessage,
            clearEditingMessage
        );
        promptEditor->clear();
        scrollTranscriptToBottom();
    };
    auto appendUserMessage = [&](const QString &rawText) {
        const QString text = rawText.trimmed();
        if (text.isEmpty()) {
            return;
        }

        const QString trimmingMessageID = editingMessageID;
        clearEditingMessage();
        if (requestHistoryAction
            && requestHistoryAction(
                QStringLiteral("sendMessage"),
                currentConversationID(conversationList, selectedConversationID),
                text,
                trimmingMessageID,
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

        const QString trimmingMessageID = editingMessageID;
        clearEditingMessage();
        if (requestHistoryAction
            && requestHistoryAction(
                QStringLiteral("sendMessage"),
                currentConversationID(conversationList, selectedConversationID),
                rawPrompt,
                trimmingMessageID,
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
        const bool imageAttachmentsAvailable = selectedModelSupportsImages(modelPicker, payload);
        attachmentInputRow->setVisible(imageAttachmentsAvailable);
        attachmentPath->setVisible(imageAttachmentsAvailable);
        unavailableModelButton->setVisible(false);
        attachButton->setVisible(imageAttachmentsAvailable);
        clearAttachmentsButton->setVisible(imageAttachmentsAvailable);
        dropTarget->setAcceptDrops(imageAttachmentsAvailable);
        if (!imageAttachmentsAvailable) {
            dropTarget->resetDragState();
        }
        dropTarget->setVisible(imageAttachmentsAvailable || hasPendingAttachments);
        if (!imageAttachmentsAvailable && dropHint != nullptr) {
            dropHint->setVisible(false);
        }
        attachButton->setEnabled(imageAttachmentsAvailable && hasAttachmentPathInput);
        clearAttachmentsButton->setEnabled(imageAttachmentsAvailable && (hasAttachmentPathInput || hasPendingAttachments));
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
            attachmentTextLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft);
            const QString attachmentNameText = attachmentDisplayName(path);
            const QString displaySize = attachmentDisplaySize(path);
            const QString attachmentSummary = accessibilitySummary(attachmentNameText, displaySize);
            attachmentChip->setAccessibleName(attachmentNameText);
            attachmentChip->setAccessibleDescription(attachmentSummary);
            attachmentChip->setToolTip(attachmentSummary);
            attachmentChip->setStatusTip(attachmentSummary);

            QLabel *attachmentName = label(attachmentNameText, QStringLiteral("attachmentName"));
            attachmentName->setWordWrap(false);
            attachmentTextLayout->addWidget(attachmentName);

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
            removeAttachmentButton->setAccessibleDescription(removeAttachmentTooltip);
            removeAttachmentButton->setStatusTip(removeAttachmentTooltip);
            removeAttachmentButton->setFixedWidth(styleInt(style, "attachmentRemoveButtonWidth"));
            QObject::connect(removeAttachmentButton, &QPushButton::clicked, [&, path]() {
                pendingAttachmentPaths.removeAll(path);
                setStatusText(
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
                setStatusText(validation.lastError);
            }
            return false;
        }

        renderAttachmentTray();
        setStatusText(attachmentReadyStatus(
            pendingAttachmentPaths.count(),
            imageReadyStatusSingular,
            imageReadyStatusPluralUnit
        ));
        return true;
    };
    dropTarget->setSupportedAttachmentExtensions(attachmentPolicy.supportedExtensions);
    dropTarget->setDropHandler([&](const QStringList &paths) {
        if (!selectedModelSupportsImages(modelPicker, payload)) {
            return;
        }

        addPendingAttachmentPaths(paths);
    });
    auto clearAttachmentState = [&](const QString &nextStatus) {
        attachmentPath->clear();
        pendingAttachmentPaths.clear();
        clearLayout(attachmentChipListLayout);
        attachmentTray->setVisible(false);
        if (!nextStatus.isEmpty()) {
            setStatusText(nextStatus);
        }
        updateComposerControlState();
    };
    auto triggerSendOrStop = [&]() {
        if (isLoading) {
            setStatusText(stoppingStatus);
            return;
        }

        appendComposerMessage(promptEditor->toPlainText());
        clearAttachmentState(QString());
    };
    auto attachPendingPath = [&]() {
        if (!selectedModelSupportsImages(modelPicker, payload)) {
            return;
        }

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
            icons,
            emptyStateTitle,
            emptyStateSubtitle,
            appendUserMessage,
            payloadString(payload, "status"),
            isLoading,
            userRoleLabel,
            assistantRoleLabel,
            systemRoleLabel,
            copyMessageTitle,
            editMessageTitle,
            unselectMessageTitle,
            editingMessageID,
            editMessage,
            clearEditingMessage
        );
        showingPromptCards = messages.isEmpty();
        scrollTranscriptToBottom();
    };
    rerenderCurrentMessages = [&]() {
        const QString selectedID = currentConversationID(conversationList, selectedConversationID);
        renderMessageSet(selectedConversationMessages(
            conversations,
            selectedID,
            fallbackMessages
        ));
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
        const QString updatedCurrentTitle = selectedConversationTitle(
            conversations,
            selectedID,
            newConversationTitle
        );
        currentTitle->setText(updatedCurrentTitle);
        updateHeaderTitleAccessibility(updatedCurrentTitle);
        setStatusText(payloadString(payload, "status"));
        refreshButton->setEnabled(!isLoading);
        updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle, style);
        refreshStyle(sendButton);
        updateComposerControlState();
        const QString updatedModelStatus = modelStatusText(
            modelPicker->currentText().trimmed().isEmpty()
                ? payloadString(payload, "selectedModel")
                : modelPicker->currentText(),
            chooseLocalModelStatus,
            usingModelStatusPrefix,
            usingModelStatusSeparator
        );
        modelStatus->setText(updatedModelStatus);
        updateModelStatusAccessibility(updatedModelStatus);
        renderMessageSet(selectedConversationMessages(
            conversations,
            selectedID,
            fallbackMessages
        ));
        updateConversationActionState();
    };
    requestHistoryAction = [&](const QString &actionName, const QString &conversationID, const QString &messageText, const QString &trimmingMessageID, const QStringList &attachmentPaths) -> bool {
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
        const QString trimmedTrimmingMessageID = trimmingMessageID.trimmed();
        if (!trimmedTrimmingMessageID.isEmpty()) {
            action.insert(QStringLiteral("trimmingMessageID"), trimmedTrimmingMessageID);
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
        setStatusText(status);
    };

    QObject::connect(newConversationButton, &QPushButton::clicked, [&]() {
        if (requestHistoryAction(QStringLiteral("newConversation"), QString(), QString(), QString(), QStringList())) {
            return;
        }

        conversationList->clearSelection();
        conversationList->setCurrentRow(-1);
        updateConversationSelectionStyles(conversationList);
        currentTitle->setText(newConversationTitle);
        updateHeaderTitleAccessibility(newConversationTitle);
        editingMessageID.clear();
        renderMessageSet(QJsonArray());
        updateConversationActionState();
    });
    QObject::connect(deleteButton, &QPushButton::clicked, [&]() {
        const int deletedRow = conversationList->currentRow();
        if (deletedRow < 0) {
            return;
        }

        const QString deletedConversationID = currentConversationID(conversationList, selectedConversationID);
        if (requestHistoryAction(QStringLiteral("deleteConversation"), deletedConversationID, QString(), QString(), QStringList())) {
            return;
        }

        removeConversationRow(conversationList, deletedRow);
        if (conversationList->count() > 0) {
            const int nextRow = deletedRow >= conversationList->count() ? conversationList->count() - 1 : deletedRow;
            conversationList->setCurrentRow(nextRow);
        } else {
            conversationList->setCurrentRow(-1);
            currentTitle->setText(newConversationTitle);
            updateHeaderTitleAccessibility(newConversationTitle);
            editingMessageID.clear();
            renderMessageSet(QJsonArray());
        }
        updateConversationSelectionStyles(conversationList);
        updateConversationActionState();
    });
    QObject::connect(clearAllButton, &QPushButton::clicked, [&]() {
        if (requestHistoryAction(QStringLiteral("deleteAllConversations"), QString(), QString(), QString(), QStringList())) {
            return;
        }

        conversationList->clear();
        conversationList->setCurrentRow(-1);
        updateConversationSelectionStyles(conversationList);
        currentTitle->setText(newConversationTitle);
        updateHeaderTitleAccessibility(newConversationTitle);
        editingMessageID.clear();
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
        const QString updatedCurrentTitle = selectedConversationTitle(
            conversations,
            selectedID,
            newConversationTitle
        );
        currentTitle->setText(updatedCurrentTitle);
        updateHeaderTitleAccessibility(updatedCurrentTitle);
        editingMessageID.clear();
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
            QString(),
            QStringList()
        );
    });
    QObject::connect(refreshButton, &QPushButton::clicked, [&]() {
        requestHistoryAction(
            QStringLiteral("refreshModels"),
            currentConversationID(conversationList, selectedConversationID),
            QString(),
            QString(),
            QStringList()
        );
    });
    QObject::connect(modelPicker, &QComboBox::currentTextChanged, [&](const QString &model) {
        updateModelPickerAccessibility();
        const QString updatedModelStatus = modelStatusText(model, chooseLocalModelStatus, usingModelStatusPrefix, usingModelStatusSeparator);
        modelStatus->setText(updatedModelStatus);
        updateModelStatusAccessibility(updatedModelStatus);
        if (!selectedModelSupportsImages(modelPicker, payload)) {
            clearAttachmentState(QString());
        } else {
            updateComposerControlState();
        }
        requestHistoryAction(
            QStringLiteral("selectModel"),
            currentConversationID(conversationList, selectedConversationID),
            QString(),
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
