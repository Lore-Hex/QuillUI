#include "CQuillQt6WidgetsShim.h"

#include <QApplication>
#include <QDialog>
#include <QFrame>
#include <QLabel>
#include <QLineEdit>
#include <QObject>
#include <QPushButton>
#include <QString>
#include <QStyle>
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

QPushButton *interactionSmokeButton(QWidget *parent, const QString &title, int x, int y, int width, int height) {
    QPushButton *button = new QPushButton(title, parent);
    button->setGeometry(x, y, width, height);
    return button;
}

QLabel *interactionSmokeLabel(
    QWidget *parent,
    const QString &text,
    const QString &objectName,
    int x,
    int y,
    int width,
    int height
) {
    QLabel *view = new QLabel(text, parent);
    view->setObjectName(objectName);
    view->setWordWrap(true);
    view->setGeometry(x, y, width, height);
    return view;
}

void showInteractionSmokeSheet(QWidget *parent, const QString &title) {
    QDialog *dialog = new QDialog(parent);
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setObjectName(QStringLiteral("interactionSheet"));
    dialog->setWindowTitle(title);
    dialog->resize(900, 700);

    QFrame *header = new QFrame(dialog);
    header->setObjectName(QStringLiteral("interactionSheetHeader"));
    header->setGeometry(20, 55, 400, 70);
    interactionSmokeLabel(
        header,
        title,
        QStringLiteral("interactionSheetTitle"),
        16,
        10,
        360,
        24
    );
    interactionSmokeLabel(
        header,
        QStringLiteral("Native Qt opened this dialog from the backend interaction fixture."),
        QStringLiteral("interactionSheetText"),
        16,
        36,
        360,
        22
    );

    interactionSmokeLabel(
        dialog,
        QStringLiteral("This sheet is intentionally native Qt so xdotool and the screenshot verifier can exercise a real child window."),
        QStringLiteral("interactionSmokeText"),
        20,
        148,
        560,
        48
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

    QFrame *header = new QFrame(&window);
    header->setObjectName(QStringLiteral("interactionSmokeHeader"));
    header->setGeometry(0, 0, 640, 73);
    interactionSmokeLabel(
        header,
        QStringLiteral("Quill Backend Interaction"),
        QStringLiteral("interactionSmokeWindowTitle"),
        32,
        20,
        350,
        28
    );

    QPushButton *panelButton = interactionSmokeButton(
        header,
        QStringLiteral("Open Panel"),
        508,
        18,
        100,
        36
    );

    QWidget *content = new QWidget(&window);
    content->setObjectName(QStringLiteral("interactionSmokeContent"));
    content->setGeometry(0, 73, 640, 687);
    interactionSmokeLabel(
        content,
        QStringLiteral("Native backend click target"),
        QStringLiteral("interactionSmokeTitle"),
        32,
        30,
        430,
        36
    );
    interactionSmokeLabel(
        content,
        QStringLiteral("This fixture keeps the Qt backend's click, text, banner, sidebar, and sheet checks on the same surface as GTK."),
        QStringLiteral("interactionSmokeText"),
        32,
        70,
        520,
        42
    );

    QLineEdit *textField = new QLineEdit(content);
    textField->setPlaceholderText(QStringLiteral("Type here"));
    textField->setGeometry(32, 126, 320, 38);
    QLabel *typedLabel = interactionSmokeLabel(
        content,
        QStringLiteral("No typed text yet"),
        QStringLiteral("interactionSmokeText"),
        32,
        170,
        360,
        26
    );
    QObject::connect(textField, &QLineEdit::textChanged, typedLabel, [typedLabel](const QString &text) {
        typedLabel->setText(text.isEmpty() ? QStringLiteral("No typed text yet") : QStringLiteral("Typed: %1").arg(text));
    });

    QFrame *panel = new QFrame(content);
    panel->setObjectName(QStringLiteral("interactionSmokePanel"));
    panel->setGeometry(32, 72, 398, 165);
    panel->hide();
    interactionSmokeLabel(
        panel,
        QStringLiteral("Interaction Open"),
        QStringLiteral("interactionSmokePanelTitle"),
        18,
        18,
        320,
        26
    );
    interactionSmokeLabel(
        panel,
        QStringLiteral("QuillUI rendered this panel after a native backend button click."),
        QStringLiteral("interactionSmokePanelText"),
        18,
        54,
        340,
        48
    );
    QObject::connect(panelButton, &QPushButton::clicked, panel, [panel, panelButton]() {
        const bool shouldOpen = !panel->isVisible();
        panel->setVisible(shouldOpen);
        panelButton->setText(shouldOpen ? QStringLiteral("Hide Panel") : QStringLiteral("Open Panel"));
    });

    QPushButton *sidebarButton = interactionSmokeButton(
        content,
        QStringLiteral("Sidebar Closed"),
        56,
        185,
        180,
        46
    );
    QObject::connect(sidebarButton, &QPushButton::clicked, sidebarButton, [sidebarButton]() {
        sidebarButton->setObjectName(QStringLiteral("interactionSmokeActiveButton"));
        sidebarButton->setText(QStringLiteral("Sidebar Open"));
        sidebarButton->style()->unpolish(sidebarButton);
        sidebarButton->style()->polish(sidebarButton);
    });

    QFrame *banner = new QFrame(content);
    banner->setObjectName(QStringLiteral("interactionSmokeBanner"));
    banner->setGeometry(60, 255, 190, 62);
    banner->hide();
    interactionSmokeLabel(
        banner,
        QStringLiteral("Banner Open"),
        QStringLiteral("interactionSmokePanelTitle"),
        14,
        17,
        156,
        26
    );
    QPushButton *bannerButton = interactionSmokeButton(
        content,
        QStringLiteral("Open Banner"),
        410,
        277,
        150,
        44
    );
    QObject::connect(bannerButton, &QPushButton::clicked, banner, [banner]() {
        banner->show();
    });

    QPushButton *nestedSheetButton = interactionSmokeButton(
        content,
        QStringLiteral("Open Nested Sheet"),
        56,
        360,
        190,
        48
    );
    QObject::connect(nestedSheetButton, &QPushButton::clicked, &window, [&window]() {
        showInteractionSmokeSheet(&window, QStringLiteral("Nested Sheet Open"));
    });

    QPushButton *sidebarSheetButton = interactionSmokeButton(
        content,
        QStringLiteral("Open Sidebar Sheet"),
        90,
        410,
        190,
        48
    );
    QObject::connect(sidebarSheetButton, &QPushButton::clicked, &window, [&window]() {
        showInteractionSmokeSheet(&window, QStringLiteral("Sidebar Sheet Open"));
    });

    QPushButton *bannerSheetButton = interactionSmokeButton(
        content,
        QStringLiteral("Open Banner Sheet"),
        410,
        493,
        170,
        48
    );
    QObject::connect(bannerSheetButton, &QPushButton::clicked, &window, [&window]() {
        showInteractionSmokeSheet(&window, QStringLiteral("Banner Sheet Open"));
    });

    window.show();
    return app.exec();
}
