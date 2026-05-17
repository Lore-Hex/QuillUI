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

QIcon attachmentChipIcon() {
    return themedActionIcon(QStringLiteral("folder-symbolic"), QStyle::SP_DirIcon);
}

QIcon promptButtonIcon() {
    return themedActionIcon(QStringLiteral("starred-symbolic"), QStyle::SP_DialogYesButton);
}

QIcon completionsButtonIcon() {
    return themedActionIcon(QStringLiteral("accessories-text-editor-symbolic"), QStyle::SP_FileDialogDetailedView);
}

QIcon shortcutsButtonIcon() {
    return themedActionIcon(QStringLiteral("input-keyboard-symbolic"), QStyle::SP_ComputerIcon);
}

QIcon settingsButtonIcon() {
    return themedActionIcon(QStringLiteral("preferences-system-symbolic"), QStyle::SP_MessageBoxInformation);
}

QIcon sendButtonIcon(bool isLoading) {
    return isLoading
        ? themedActionIcon(QStringLiteral("process-stop-symbolic"), QStyle::SP_MediaStop)
        : themedActionIcon(QStringLiteral("go-next-symbolic"), QStyle::SP_MediaPlay);
}

QIcon removeAttachmentButtonIcon() {
    return themedActionIcon(QStringLiteral("window-close-symbolic"), QStyle::SP_DialogCloseButton);
}

int buttonIconSize(const QJsonObject &style) {
    return intValue(style, "actionButtonIconSize", 16);
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
          color(styleValue(style, "primaryColor", "#4285F4")) {
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

QJsonObject objectValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonObjectValue(object, key);
}

QJsonArray arrayValue(const QJsonObject &object, const char *key) {
    return QuillQtWidgets::jsonArrayValue(object, key);
}

QString appStyleSheet(const QJsonObject &style) {
    const QString canvas = styleValue(style, "canvasColor", "#FBFBFD");
    const QString ink = styleValue(style, "inkColor", "#1D1D1F");
    const QString sidebar = styleValue(style, "sidebarColor", "#F5F5F7");
    const QString header = styleValue(style, "headerColor", "#FBFBFD");
    const QString card = styleValue(style, "cardColor", "#FFFFFF");
    const QString primary = styleValue(style, "primaryColor", "#4285F4");
    const QString system = styleValue(style, "systemColor", "#E8E8ED");
    const QString muted = styleValue(style, "mutedColor", "#6E6E73");
    const QString selected = styleValue(style, "selectedMutedColor", "#FFFFFF");
    const QString warning = styleValue(style, "warningColor", "#FF9F0A");
    const QString success = styleValue(style, "successColor", "#34C759");
    const QString dropTarget = styleValue(style, "dropTargetColor", "#EAF2FF");
    const QString quoteRule = styleValue(style, "quoteRuleColor", "#D8D8DE");
    const QString codeBlock = styleValue(style, "codeBlockColor", "#F4F4F6");
    const QString divider = styleValue(style, "dividerColor", "#D8D8DE");
    const QString cardBorder = styleValue(style, "cardBorderColor", "#D8D8DE");
    const QString messageBorder = styleValue(style, "messageBorderColor", "#D8D8DE");
    const QString controlBorder = styleValue(style, "controlBorderColor", "#D8D8DE");
    const QString dropTargetBorder = styleValue(style, "dropTargetBorderColor", "#4285F4");
    const QString disabledButtonBackground = styleValue(style, "disabledButtonBackgroundColor", "#D8D8DE");
    const QString disabledButtonForeground = styleValue(style, "disabledButtonForegroundColor", "#6E6E73");
    const QString disabledText = styleValue(style, "disabledTextColor", "#6E6E73");
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
    const QString composerEditorRadius = cssPixels(style, "composerEditorRadius", 8);

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

QFrame *conversationRowWidget(
    const QJsonObject &conversation,
    const QJsonObject &style,
    const QString &newConversationTitle,
    const QString &noMessagesYet
) {
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
        stringValue(conversation, "title", newConversationTitle),
        QStringLiteral("conversationTitle")
    );
    title->setWordWrap(false);
    title->setProperty("active", false);

    QLabel *preview = label(
        stringValue(conversation, "lastMessage", noMessagesYet),
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
    const QJsonObject &style,
    const QString &newConversationTitle,
    const QString &noMessagesYet
) {
    list->clear();
    list->setSpacing(intValue(style, "conversationListSpacing", 8));
    int selectedRow = -1;

    for (const QJsonValue &value : conversations) {
        const QJsonObject conversation = value.toObject();
        QListWidgetItem *item = new QListWidgetItem();
        item->setData(Qt::UserRole, stringValue(conversation, "id"));
        item->setSizeHint(QSize(260, 88));
        list->addItem(item);
        list->setItemWidget(item, conversationRowWidget(
            conversation,
            style,
            newConversationTitle,
            noMessagesYet
        ));
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

QFrame *messageBubble(
    const QJsonObject &message,
    const QJsonObject &style,
    const QString &userRoleLabel,
    const QString &assistantRoleLabel,
    const QString &systemRoleLabel
) {
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
        messageRoleTitle(role, userRoleLabel, assistantRoleLabel, systemRoleLabel),
        role == QStringLiteral("user") ? QStringLiteral("messageUserRole") : QStringLiteral("messageRole")
    ));
    if (role == QStringLiteral("user")) {
        layout->addWidget(label(stringValue(message, "content"), QStringLiteral("messageUserText")));
    } else {
        layout->addWidget(markdownMessageWidget(stringValue(message, "content"), style));
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
    const bool isUser = stringValue(message, "role") == QStringLiteral("user");
    QHBoxLayout *row = new QHBoxLayout();
    row->setContentsMargins(0, 0, 0, 0);
    row->setSpacing(intValue(style, "messageBubbleRowSpacing", 10));
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
    const int emptyStatePadding = intValue(style, "emptyStatePadding", 26);
    layout->setContentsMargins(
        emptyStatePadding,
        emptyStatePadding,
        emptyStatePadding,
        emptyStatePadding
    );
    layout->setSpacing(intValue(style, "emptyStateSpacing", 18));
    QVBoxLayout *headerLayout = new QVBoxLayout();
    headerLayout->setContentsMargins(0, 0, 0, 0);
    headerLayout->setSpacing(intValue(style, "emptyStateHeaderSpacing", 8));
    headerLayout->addWidget(label(title, QStringLiteral("currentTitle")));
    headerLayout->addWidget(label(
        subtitle,
        QStringLiteral("caption")
    ));
    layout->addLayout(headerLayout);

    QVBoxLayout *promptList = new QVBoxLayout();
    promptList->setSpacing(intValue(style, "promptListSpacing", 10));
    for (const QJsonValue &value : prompts) {
        const QString prompt = value.toString();
        const int promptButtonWidth = intValue(style, "promptButtonWidth", 620);
        const int promptButtonIconSpacing = intValue(style, "promptButtonIconSpacing", 10);
        const int promptButtonTextWidth = promptButtonWidth - intValue(style, "promptButtonTextWidthInset", 80);
        QPushButton *button = new QPushButton();
        button->setObjectName(QStringLiteral("promptButton"));
        button->setAccessibleName(prompt);
        button->setMinimumHeight(intValue(style, "promptButtonMinHeight", 48));
        button->setFixedWidth(promptButtonWidth);
        QHBoxLayout *buttonLayout = new QHBoxLayout(button);
        buttonLayout->setContentsMargins(0, 0, 0, 0);
        buttonLayout->setSpacing(promptButtonIconSpacing);
        QLabel *promptIcon = iconLabel(promptButtonIcon(), QStringLiteral("promptButtonIcon"), style);
        promptIcon->setAttribute(Qt::WA_TransparentForMouseEvents);
        QLabel *promptText = label(prompt, QStringLiteral("promptButtonText"));
        promptText->setWordWrap(true);
        promptText->setFixedWidth(promptButtonTextWidth > 0 ? promptButtonTextWidth : 0);
        promptText->setAttribute(Qt::WA_TransparentForMouseEvents);
        buttonLayout->addWidget(promptIcon, 0, Qt::AlignTop);
        buttonLayout->addWidget(promptText, 0, Qt::AlignVCenter);
        buttonLayout->addStretch(1);
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

const qint64 attachmentMaxByteCount = 20 * 1024 * 1024;

struct AttachmentPathValidation {
    QStringList acceptedPaths;
    QString lastError;
};

QString formattedAttachmentByteCount(qint64 byteCount);
QString attachmentDisplaySize(const QString &rawPath);

QStringList supportedAttachmentExtensions() {
    return {
        QStringLiteral("gif"),
        QStringLiteral("heic"),
        QStringLiteral("jpeg"),
        QStringLiteral("jpg"),
        QStringLiteral("png"),
        QStringLiteral("tif"),
        QStringLiteral("tiff"),
        QStringLiteral("webp")
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

QString unsupportedAttachmentMessage(const QString &name) {
    return QStringLiteral("%1 is not a supported image attachment.").arg(name);
}

QString unreadableAttachmentMessage(const QString &path) {
    return QStringLiteral("Could not read image attachment at %1.").arg(path);
}

QString oversizedAttachmentMessage(const QString &name, qint64 byteCount) {
    return QStringLiteral("%1 is too large to attach (%2).").arg(name, formattedAttachmentByteCount(byteCount));
}

AttachmentPathValidation validatedAttachmentPaths(const QStringList &rawPaths) {
    AttachmentPathValidation validation;
    const QStringList supportedExtensions = supportedAttachmentExtensions();

    for (const QString &rawPath : rawPaths) {
        const QString path = normalizedAttachmentPath(rawPath);
        if (path.isEmpty()) {
            continue;
        }

        const QFileInfo fileInfo(path);
        const QString displayName = fileInfo.fileName().isEmpty() ? path : fileInfo.fileName();
        if (!supportedExtensions.contains(fileInfo.suffix().toLower())) {
            validation.lastError = unsupportedAttachmentMessage(displayName);
            continue;
        }

        if (!fileInfo.exists() || !fileInfo.isFile() || !fileInfo.isReadable()) {
            validation.lastError = unreadableAttachmentMessage(path);
            continue;
        }

        const qint64 byteCount = fileInfo.size();
        if (byteCount > attachmentMaxByteCount) {
            validation.lastError = oversizedAttachmentMessage(displayName, byteCount);
            continue;
        }

        if (!validation.acceptedPaths.contains(path)) {
            validation.acceptedPaths.append(path);
        }
    }

    return validation;
}

QStringList attachmentCandidatePathsFromMimeData(const QMimeData *mimeData) {
    QStringList paths;
    if (mimeData == nullptr || !mimeData->hasUrls()) {
        return paths;
    }

    const QStringList supportedExtensions = supportedAttachmentExtensions();
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
        const QStringList paths = attachmentCandidatePathsFromMimeData(event->mimeData());
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

        const bool acceptsDrop = !attachmentCandidatePathsFromMimeData(event->mimeData()).isEmpty();
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
    groupLayout->setSpacing(intValue(style, "sidebarControlGroupSpacing", 7));
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
    const QJsonObject style = objectValue(payload, "style");
    bool isLoading = boolValue(payload, "isLoading", false);
    const QString chooseLocalModelStatus = stringValue(
        payload,
        "chooseLocalModelStatus",
        QStringLiteral("Choose a local model to begin")
    );
    const QString usingModelStatusPrefix = stringValue(payload, "usingModelStatusPrefix", QStringLiteral("Using"));
    const QString newConversationTitle = stringValue(payload, "newConversationTitle", QStringLiteral("New conversation"));
    const QString noMessagesYet = stringValue(payload, "noMessagesYet", QStringLiteral("No messages yet"));
    const QString userRoleLabel = stringValue(payload, "userRoleLabel", QStringLiteral("You"));
    const QString assistantRoleLabel = stringValue(payload, "assistantRoleLabel", QStringLiteral("Enchanted"));
    const QString systemRoleLabel = stringValue(payload, "systemRoleLabel", QStringLiteral("System"));
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

    QWidget *sidebarTitleBlock = new QWidget();
    QVBoxLayout *sidebarTitleLayout = new QVBoxLayout(sidebarTitleBlock);
    sidebarTitleLayout->setContentsMargins(0, 0, 0, 0);
    sidebarTitleLayout->setSpacing(intValue(style, "sidebarTitleSpacing", 4));
    sidebarTitleLayout->addWidget(label(
        stringValue(payload, "sidebarTitle", QStringLiteral("Enchanted")),
        QStringLiteral("appTitle")
    ));
    sidebarTitleLayout->addWidget(label(
        stringValue(payload, "sidebarSubtitle", QStringLiteral("QuillUI Linux preview")),
        QStringLiteral("caption")
    ));
    sidebarLayout->addWidget(sidebarTitleBlock);

    QPushButton *newChatButton = new QPushButton(stringValue(payload, "newChatTitle", QStringLiteral("New chat")));
    newChatButton->setObjectName(QStringLiteral("primaryButton"));
    newChatButton->setIcon(newChatButtonIcon());
    applyButtonIconSize(newChatButton, style);
    sidebarLayout->addWidget(newChatButton);

    QLineEdit *endpointField = new QLineEdit(stringValue(payload, "endpoint"));
    addSidebarField(
        sidebarLayout,
        stringValue(payload, "endpointLabel", QStringLiteral("Ollama endpoint")),
        endpointField,
        style
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
        modelPicker,
        style
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
    statusText->setFixedWidth(intValue(style, "statusTextWidth", 240));
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
        style,
        newConversationTitle,
        noMessagesYet
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

    QFrame *sidebarUtilityPanel = QuillQtWidgets::frame(QStringLiteral("sidebarUtilityPanel"));
    QVBoxLayout *sidebarUtilityLayout = new QVBoxLayout(sidebarUtilityPanel);
    const int sidebarUtilityPadding = intValue(style, "emptyHistoryPadding", 12);
    sidebarUtilityLayout->setContentsMargins(
        sidebarUtilityPadding,
        sidebarUtilityPadding,
        sidebarUtilityPadding,
        sidebarUtilityPadding
    );
    sidebarUtilityLayout->setSpacing(intValue(style, "emptyHistorySpacing", 8));
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
    sidebarBottomNavigationLayout->setSpacing(intValue(style, "conversationActionsSpacing", 8));
    QPushButton *completionsButton = new QPushButton(stringValue(payload, "completionsTitle", QStringLiteral("Completions")));
    completionsButton->setObjectName(QStringLiteral("secondaryButton"));
    completionsButton->setIcon(completionsButtonIcon());
    applyButtonIconSize(completionsButton, style);
    QPushButton *shortcutsButton = new QPushButton(stringValue(payload, "shortcutsTitle", QStringLiteral("Shortcuts")));
    shortcutsButton->setObjectName(QStringLiteral("secondaryButton"));
    shortcutsButton->setIcon(shortcutsButtonIcon());
    applyButtonIconSize(shortcutsButton, style);
    QPushButton *settingsButton = new QPushButton(stringValue(payload, "settingsTitle", QStringLiteral("Settings")));
    settingsButton->setObjectName(QStringLiteral("secondaryButton"));
    settingsButton->setIcon(settingsButtonIcon());
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
            newConversationTitle
        ),
        QStringLiteral("currentTitle")
    );
    QLabel *modelStatus = label(
        modelStatusText(stringValue(payload, "selectedModel"), chooseLocalModelStatus, usingModelStatusPrefix),
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
    QHBoxLayout *composerBandLayout = new QHBoxLayout(composer);
    composerBandLayout->setContentsMargins(0, 0, 0, 0);
    composerBandLayout->setSpacing(0);
    QWidget *composerContent = new QWidget();
    composerContent->setMinimumWidth(intValue(style, "composerMinWidth", 620));
    composerContent->setMaximumWidth(intValue(style, "composerMaxWidth", 840));
    QVBoxLayout *composerLayout = new QVBoxLayout(composerContent);
    const int composerPadding = intValue(style, "composerPadding", 18);
    composerLayout->setContentsMargins(composerPadding, composerPadding, composerPadding, composerPadding);
    composerLayout->setSpacing(intValue(style, "composerSpacing", 10));
    composerBandLayout->addStretch(1);
    composerBandLayout->addWidget(composerContent);
    composerBandLayout->addStretch(1);

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
    const QString attachmentsClearedStatus = stringValue(payload, "attachmentsClearedStatus", QStringLiteral("Attachments cleared"));
    const QString attachmentRemovedEmptyStatus = stringValue(payload, "attachmentRemovedEmptyStatus", QStringLiteral("Ready"));
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
    const QString attachmentDefaultPromptPlural = stringValue(
        payload,
        "attachmentDefaultPromptPlural",
        QStringLiteral("Describe these images.")
    );
    const QString attachmentSummaryTitle = stringValue(
        payload,
        "attachmentSummaryTitle",
        QStringLiteral("[Attached images]")
    );
    const QString removeAttachmentTooltip = stringValue(
        payload,
        "removeAttachmentTooltip",
        QStringLiteral("Remove attachment")
    );
    const QString imageReadyStatusSingular = stringValue(
        payload,
        "imageReadyStatusSingular",
        QStringLiteral("1 image ready to send")
    );
    const QString imageReadyStatusPluralUnit = stringValue(
        payload,
        "imageReadyStatusPluralUnit",
        QStringLiteral("images ready to send")
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
            const int attachmentChipPadding = intValue(style, "attachmentChipPadding", 8);
            attachmentChipLayout->setContentsMargins(
                attachmentChipPadding,
                attachmentChipPadding,
                attachmentChipPadding,
                attachmentChipPadding
            );
            attachmentChipLayout->setSpacing(intValue(style, "attachmentChipSpacing", 8));

            QLabel *attachmentIcon = iconLabel(
                attachmentChipIcon(),
                QStringLiteral("attachmentChipIcon"),
                style
            );

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

            QPushButton *removeAttachmentButton = new QPushButton();
            removeAttachmentButton->setObjectName(QStringLiteral("chipRemoveButton"));
            removeAttachmentButton->setIcon(removeAttachmentButtonIcon());
            applyButtonIconSize(removeAttachmentButton, style);
            removeAttachmentButton->setToolTip(removeAttachmentTooltip);
            removeAttachmentButton->setAccessibleName(removeAttachmentTooltip);
            removeAttachmentButton->setFixedWidth(intValue(style, "attachmentRemoveButtonWidth", 28));
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
        const AttachmentPathValidation validation = validatedAttachmentPaths(rawPaths);
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
            stringValue(payload, "status"),
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
            style,
            newConversationTitle,
            noMessagesYet
        );
        const QString selectedID = currentConversationID(conversationList, selectedConversationID);
        currentTitle->setText(selectedConversationTitle(
            conversations,
            selectedID,
            newConversationTitle
        ));
        statusText->setText(stringValue(payload, "status"));
        refreshButton->setEnabled(!isLoading);
        updateSendButtonPresentation(sendButton, isLoading, sendTitle, stopTitle);
        refreshStyle(sendButton);
        updateComposerControlState();
        modelStatus->setText(modelStatusText(
            modelPicker->currentText().trimmed().isEmpty()
                ? stringValue(payload, "selectedModel")
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

    QObject::connect(newChatButton, &QPushButton::clicked, [&]() {
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
            stringValue(payload, "completionsTitle", QStringLiteral("Completions")),
            stringValue(
                payload,
                "completionsPanelSubtitle",
                QStringLiteral("Prompt completions use the shared Enchanted profile.")
            ),
            stringValue(payload, "completionsStatus", QStringLiteral("Completions"))
        );
    });
    QObject::connect(shortcutsButton, &QPushButton::clicked, [&]() {
        showSidebarUtilityPanel(
            stringValue(payload, "shortcutsTitle", QStringLiteral("Shortcuts")),
            stringValue(
                payload,
                "shortcutsPanelSubtitle",
                QStringLiteral("Keyboard shortcuts use the shared QuillKit shortcut surface.")
            ),
            stringValue(payload, "shortcutsStatus", QStringLiteral("Shortcuts"))
        );
    });
    QObject::connect(settingsButton, &QPushButton::clicked, [&]() {
        showSidebarUtilityPanel(
            stringValue(payload, "settingsTitle", QStringLiteral("Settings")),
            stringValue(
                payload,
                "settingsPanelSubtitle",
                QStringLiteral("Refresh models, choose a local model, or clear history from this sidebar.")
            ),
            stringValue(payload, "settingsStatus", QStringLiteral("Settings"))
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
