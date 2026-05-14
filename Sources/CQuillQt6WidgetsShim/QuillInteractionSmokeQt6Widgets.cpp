#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QDialog>
#include <QFrame>
#include <QLabel>
#include <QLineEdit>
#include <QObject>
#include <QPushButton>
#include <QRect>
#include <QString>
#include <QWidget>

namespace {

void applyInteractionSmokeStyle(QApplication &app) {
    app.setStyleSheet(QStringLiteral(
        "QWidget#interactionSmokeWindow { background: #ffffff; color: #111827; font-size: 13px; }"
        "QFrame#interactionSmokeHeader { background: #ffffff; border-bottom: 1px solid #d8d8dd; }"
        "QWidget#interactionSmokeContent { background: #f7f7f8; }"
        "QLabel#interactionSmokeTitle { font-size: 24px; font-weight: 650; background: transparent; }"
        "QLabel#interactionSmokeWindowTitle { font-size: 18px; font-weight: 650; background: transparent; }"
        "QLabel#interactionSmokeText { color: #4b5563; background: transparent; }"
        "QPushButton { background: #ffffff; border: 1px solid #cfd3dc; border-radius: 6px; padding: 6px 10px; }"
        "QPushButton:pressed { background: #e7e9ef; }"
        "QPushButton#interactionSmokeActiveButton { background: #111827; border-color: #111827; color: #ffffff; }"
        "QFrame#interactionSmokePanel, QFrame#interactionSmokeBanner, QFrame#interactionSheetHeader {"
        " background: #111827; border-radius: 6px; }"
        "QLabel#interactionSmokePanelTitle, QLabel#interactionSheetTitle {"
        " background: transparent; color: #ffffff; font-size: 18px; font-weight: 650; }"
        "QLabel#interactionSmokePanelText, QLabel#interactionSheetText {"
        " background: transparent; color: #d1d5db; }"
        "QLineEdit { background: #ffffff; border: 1px solid #cfd3dc; border-radius: 6px; padding: 7px 9px; }"
        "QDialog#interactionSheet { background: #ffffff; color: #111827; font-size: 13px; }"
    ));
}

void showInteractionSmokeSheet(QWidget *parent, const QString &title) {
    QDialog *dialog = new QDialog(parent);
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setObjectName(QStringLiteral("interactionSheet"));
    dialog->setWindowTitle(title);
    dialog->resize(900, 700);

    QFrame *header = QuillQtWidgets::positionedFrame(
        dialog,
        QStringLiteral("interactionSheetHeader"),
        QRect(20, 55, 400, 70)
    );
    QuillQtWidgets::positionedLabel(
        header,
        title,
        QStringLiteral("interactionSheetTitle"),
        QRect(16, 10, 360, 24)
    );
    QuillQtWidgets::positionedLabel(
        header,
        QStringLiteral("Native Qt opened this dialog from the backend interaction fixture."),
        QStringLiteral("interactionSheetText"),
        QRect(16, 36, 360, 22)
    );

    QuillQtWidgets::positionedLabel(
        dialog,
        QStringLiteral("This sheet is intentionally native Qt so xdotool and the screenshot verifier can exercise a real child window."),
        QStringLiteral("interactionSmokeText"),
        QRect(20, 148, 560, 48)
    );

    dialog->show();
    dialog->raise();
    dialog->activateWindow();
}

} // namespace

int quill_qt_run_interaction_smoke(int argc, char **argv) {
    QApplication app(argc, argv);
    applyInteractionSmokeStyle(app);

    QWidget window;
    window.setObjectName(QStringLiteral("interactionSmokeWindow"));
    window.setWindowTitle(QStringLiteral("Quill Backend Interaction"));
    window.resize(640, 760);

    QFrame *header = QuillQtWidgets::positionedFrame(
        &window,
        QStringLiteral("interactionSmokeHeader"),
        QRect(0, 0, 640, 73)
    );
    QuillQtWidgets::positionedLabel(
        header,
        QStringLiteral("Quill Backend Interaction"),
        QStringLiteral("interactionSmokeWindowTitle"),
        QRect(32, 20, 350, 28)
    );

    QPushButton *panelButton = QuillQtWidgets::positionedButton(
        header,
        QStringLiteral("Open Panel"),
        QRect(508, 18, 100, 36)
    );

    QWidget *content = new QWidget(&window);
    content->setObjectName(QStringLiteral("interactionSmokeContent"));
    content->setGeometry(0, 73, 640, 687);
    QuillQtWidgets::positionedLabel(
        content,
        QStringLiteral("Native backend click target"),
        QStringLiteral("interactionSmokeTitle"),
        QRect(32, 30, 430, 36)
    );
    QuillQtWidgets::positionedLabel(
        content,
        QStringLiteral("This fixture keeps the Qt backend's click, text, banner, sidebar, and sheet checks on the same surface as GTK."),
        QStringLiteral("interactionSmokeText"),
        QRect(32, 70, 520, 42)
    );

    QLineEdit *textField = new QLineEdit(content);
    textField->setPlaceholderText(QStringLiteral("Type here"));
    textField->setGeometry(32, 126, 320, 38);
    QLabel *typedLabel = QuillQtWidgets::positionedLabel(
        content,
        QStringLiteral("No typed text yet"),
        QStringLiteral("interactionSmokeText"),
        QRect(32, 170, 360, 26)
    );
    QObject::connect(textField, &QLineEdit::textChanged, typedLabel, [typedLabel](const QString &text) {
        typedLabel->setText(text.isEmpty() ? QStringLiteral("No typed text yet") : QStringLiteral("Typed: %1").arg(text));
    });

    QFrame *panel = QuillQtWidgets::positionedFrame(
        content,
        QStringLiteral("interactionSmokePanel"),
        QRect(32, 72, 398, 165)
    );
    panel->hide();
    QuillQtWidgets::positionedLabel(
        panel,
        QStringLiteral("Interaction Open"),
        QStringLiteral("interactionSmokePanelTitle"),
        QRect(18, 18, 320, 26)
    );
    QuillQtWidgets::positionedLabel(
        panel,
        QStringLiteral("QuillUI rendered this panel after a native backend button click."),
        QStringLiteral("interactionSmokePanelText"),
        QRect(18, 54, 340, 48)
    );
    QObject::connect(panelButton, &QPushButton::clicked, panel, [panel, panelButton]() {
        const bool shouldOpen = !panel->isVisible();
        panel->setVisible(shouldOpen);
        panelButton->setText(shouldOpen ? QStringLiteral("Hide Panel") : QStringLiteral("Open Panel"));
    });

    QPushButton *sidebarButton = QuillQtWidgets::positionedButton(
        content,
        QStringLiteral("Sidebar Closed"),
        QRect(56, 185, 180, 46)
    );
    QObject::connect(sidebarButton, &QPushButton::clicked, sidebarButton, [sidebarButton]() {
        sidebarButton->setObjectName(QStringLiteral("interactionSmokeActiveButton"));
        sidebarButton->setText(QStringLiteral("Sidebar Open"));
        QuillQtWidgets::repolish(sidebarButton);
    });

    QFrame *banner = QuillQtWidgets::positionedFrame(
        content,
        QStringLiteral("interactionSmokeBanner"),
        QRect(60, 255, 190, 62)
    );
    banner->hide();
    QuillQtWidgets::positionedLabel(
        banner,
        QStringLiteral("Banner Open"),
        QStringLiteral("interactionSmokePanelTitle"),
        QRect(14, 17, 156, 26)
    );
    QPushButton *bannerButton = QuillQtWidgets::positionedButton(
        content,
        QStringLiteral("Open Banner"),
        QRect(410, 277, 150, 44)
    );
    QObject::connect(bannerButton, &QPushButton::clicked, banner, [banner]() {
        banner->show();
    });

    QPushButton *nestedSheetButton = QuillQtWidgets::positionedButton(
        content,
        QStringLiteral("Open Nested Sheet"),
        QRect(56, 360, 190, 48)
    );
    QObject::connect(nestedSheetButton, &QPushButton::clicked, &window, [&window]() {
        showInteractionSmokeSheet(&window, QStringLiteral("Nested Sheet Open"));
    });

    QPushButton *sidebarSheetButton = QuillQtWidgets::positionedButton(
        content,
        QStringLiteral("Open Sidebar Sheet"),
        QRect(90, 410, 190, 48)
    );
    QObject::connect(sidebarSheetButton, &QPushButton::clicked, &window, [&window]() {
        showInteractionSmokeSheet(&window, QStringLiteral("Sidebar Sheet Open"));
    });

    QPushButton *bannerSheetButton = QuillQtWidgets::positionedButton(
        content,
        QStringLiteral("Open Banner Sheet"),
        QRect(410, 493, 170, 48)
    );
    QObject::connect(bannerSheetButton, &QPushButton::clicked, &window, [&window]() {
        showInteractionSmokeSheet(&window, QStringLiteral("Banner Sheet Open"));
    });

    window.show();
    return app.exec();
}
