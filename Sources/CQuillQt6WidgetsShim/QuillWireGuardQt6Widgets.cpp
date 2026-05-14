#include "CQuillQt6WidgetsShim.h"
#include "QuillQtWidgetsSupport.hpp"

#include <QApplication>
#include <QByteArray>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFile>
#include <QFileDialog>
#include <QFormLayout>
#include <QFont>
#include <QFrame>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLayout>
#include <QLayoutItem>
#include <QKeySequence>
#include <QLineEdit>
#include <QListWidget>
#include <QListWidgetItem>
#include <QObject>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QShortcut>
#include <QSize>
#include <QSplitter>
#include <QString>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

#include <algorithm>
#include <cstdio>

namespace {

using QuillQtWidgets::label;

QString stringValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toString();
}

QString stringValue(const QJsonObject &object, const char *key, const QString &fallback) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    return value.isString() ? value.toString() : fallback;
}

QString presentationValue(const QJsonObject &presentation, const char *key, const char *fallback) {
    return stringValue(presentation, key, QString::fromUtf8(fallback));
}

QString styleValue(const QJsonObject &style, const char *key, const char *fallback) {
    return stringValue(style, key, QString::fromUtf8(fallback));
}

int intValue(const QJsonObject &object, const char *key, int fallback) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    return value.isDouble() ? value.toInt(fallback) : fallback;
}

QFont monospacedFont(const QJsonObject &style) {
    QFont font(QStringLiteral("monospace"));
    font.setStyleHint(QFont::Monospace);
    font.setPointSize(intValue(style, "monospacedFontSize", 11));
    return font;
}

QPlainTextEdit *configurationTextEditor(
    const QJsonObject &style,
    const QString &text = QString(),
    bool readOnly = false
) {
    QPlainTextEdit *editor = new QPlainTextEdit(text);
    editor->setFont(monospacedFont(style));
    editor->setMinimumHeight(intValue(style, "importEditorHeight", 180));
    editor->setReadOnly(readOnly);
    return editor;
}

QSize resolvedMinimumWindowSize(const QJsonObject &payload) {
    return QSize(
        intValue(payload, "minimumWidth", 900),
        intValue(payload, "minimumHeight", 600)
    );
}

QSize resolvedDefaultWindowSize(const QJsonObject &payload, const QSize &minimumSize) {
    return QSize(
        std::max(intValue(payload, "defaultWidth", minimumSize.width()), minimumSize.width()),
        std::max(intValue(payload, "defaultHeight", minimumSize.height()), minimumSize.height())
    );
}

QJsonObject objectValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toObject();
}

QJsonArray arrayValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toArray();
}

void clearLayout(QLayout *layout) {
    while (QLayoutItem *item = layout->takeAt(0)) {
        if (QLayout *childLayout = item->layout()) {
            clearLayout(childLayout);
        }
        if (QWidget *widget = item->widget()) {
            delete widget;
        }
        delete item;
    }
}

void addDetailRow(
    QFormLayout *layout,
    const QString &title,
    const QString &value,
    const QString &noneText,
    const QJsonObject &style,
    bool monospaced = false
) {
    QLabel *titleLabel = label(title, QStringLiteral("detailKey"));
    QLabel *valueLabel = label(value.isEmpty() ? noneText : value);
    titleLabel->setFixedWidth(intValue(style, "detailKeyWidth", 92));
    if (monospaced) {
        valueLabel->setFont(monospacedFont(style));
    }
    layout->addRow(titleLabel, valueLabel);
}

QGroupBox *sectionBox(const QString &title) {
    QGroupBox *box = new QGroupBox(title.toUpper());
    box->setObjectName(QStringLiteral("detailSection"));
    return box;
}

QWidget *tunnelRowWidget(const QJsonObject &tunnel, const QJsonObject &style) {
    QWidget *row = new QWidget();
    row->setObjectName(QStringLiteral("tunnelRow"));

    QVBoxLayout *layout = new QVBoxLayout(row);
    const int horizontalPadding = intValue(style, "tunnelRowHorizontalPadding", 8);
    const int verticalPadding = intValue(style, "tunnelRowVerticalPadding", 6);
    layout->setContentsMargins(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding);
    layout->setSpacing(intValue(style, "tunnelRowSpacing", 3));

    QHBoxLayout *header = new QHBoxLayout();
    header->setContentsMargins(0, 0, 0, 0);
    QLabel *name = label(stringValue(tunnel, "name"), QStringLiteral("tunnelName"));
    QLabel *status = label(stringValue(tunnel, "statusText"), QStringLiteral("tunnelStatus"));
    header->addWidget(name, 1);
    header->addWidget(status, 0, Qt::AlignRight);
    layout->addLayout(header);

    const QJsonObject interfaceObject = objectValue(tunnel, "interface");
    QLabel *summary = label(
        QStringLiteral("%1 - %2").arg(
            stringValue(interfaceObject, "addressesText"),
            stringValue(tunnel, "peerSummary")
        ),
        QStringLiteral("tunnelSummary")
    );
    layout->addWidget(summary);

    return row;
}

void addTunnelRow(QListWidget *list, const QJsonObject &tunnel, const QJsonObject &style) {
    QListWidgetItem *item = new QListWidgetItem();
    item->setSizeHint(QSize(240, intValue(style, "tunnelRowHeight", 64)));
    list->addItem(item);
    list->setItemWidget(item, tunnelRowWidget(tunnel, style));
}

void replaceTunnelName(QJsonArray *tunnels, int row, const QString &name) {
    if (tunnels == nullptr || row < 0 || row >= tunnels->size()) {
        return;
    }

    QJsonObject tunnel = tunnels->at(row).toObject();
    tunnel.insert(QStringLiteral("name"), name);
    tunnels->replace(row, QJsonValue(tunnel));
}

void updateTunnelRowName(QListWidget *list, int row, const QString &name) {
    if (list == nullptr || row < 0 || row >= list->count()) {
        return;
    }

    QWidget *rowWidget = list->itemWidget(list->item(row));
    if (rowWidget == nullptr) {
        return;
    }

    QLabel *nameLabel = rowWidget->findChild<QLabel *>(QStringLiteral("tunnelName"));
    if (nameLabel != nullptr) {
        nameLabel->setText(name);
    }
}

void addInterfaceSection(
    QVBoxLayout *detailLayout,
    const QJsonObject &tunnel,
    const QJsonObject &presentation,
    const QJsonObject &style
) {
    const QString noneText = presentationValue(presentation, "noneText", "None");
    const QJsonObject interfaceObject = objectValue(tunnel, "interface");
    QGroupBox *section = sectionBox(presentationValue(presentation, "interfaceSectionTitle", "Interface"));
    QFormLayout *form = new QFormLayout(section);
    form->setLabelAlignment(Qt::AlignLeft);
    addDetailRow(
        form,
        presentationValue(presentation, "publicKeyLabel", "Public key"),
        stringValue(interfaceObject, "publicKey"),
        noneText,
        style,
        true
    );
    addDetailRow(
        form,
        presentationValue(presentation, "addressesLabel", "Addresses"),
        stringValue(interfaceObject, "addressesText"),
        noneText,
        style
    );
    addDetailRow(
        form,
        presentationValue(presentation, "dnsLabel", "DNS"),
        stringValue(interfaceObject, "dnsServersText"),
        noneText,
        style
    );

    const QString listenPort = stringValue(interfaceObject, "listenPortText");
    if (!listenPort.isEmpty()) {
        addDetailRow(
            form,
            presentationValue(presentation, "listenPortLabel", "Listen port"),
            listenPort,
            noneText,
            style
        );
    }

    detailLayout->addWidget(section);
}

void addPeerSection(
    QVBoxLayout *detailLayout,
    const QJsonObject &peer,
    const QJsonObject &presentation,
    const QJsonObject &style
) {
    const QString noneText = presentationValue(presentation, "noneText", "None");
    QGroupBox *section = sectionBox(stringValue(peer, "name"));
    QFormLayout *form = new QFormLayout(section);
    form->setLabelAlignment(Qt::AlignLeft);
    addDetailRow(
        form,
        presentationValue(presentation, "publicKeyLabel", "Public key"),
        stringValue(peer, "publicKey"),
        noneText,
        style,
        true
    );
    addDetailRow(
        form,
        presentationValue(presentation, "allowedIPsLabel", "Allowed IPs"),
        stringValue(peer, "allowedIPsText"),
        noneText,
        style
    );

    const QString endpoint = stringValue(peer, "endpointText");
    if (!endpoint.isEmpty()) {
        addDetailRow(
            form,
            presentationValue(presentation, "endpointLabel", "Endpoint"),
            endpoint,
            noneText,
            style
        );
    }

    const QString keepAlive = stringValue(peer, "keepAliveText");
    if (!keepAlive.isEmpty()) {
        addDetailRow(
            form,
            presentationValue(presentation, "keepAliveLabel", "Keepalive"),
            keepAlive,
            noneText,
            style
        );
    }

    detailLayout->addWidget(section);
}

void addExportSection(
    QVBoxLayout *detailLayout,
    const QJsonObject &tunnel,
    const QJsonObject &presentation,
    const QJsonObject &style
) {
    QGroupBox *section = sectionBox(presentationValue(presentation, "exportSectionTitle", "Export"));
    QVBoxLayout *layout = new QVBoxLayout(section);
    QPlainTextEdit *config = configurationTextEditor(style, stringValue(tunnel, "wgQuickConfig"), true);
    layout->addWidget(config);
    detailLayout->addWidget(section);
}

void renderDetail(
    QVBoxLayout *detailLayout,
    QJsonArray *tunnels,
    QListWidget *list,
    const QJsonObject &presentation,
    const QJsonObject &style,
    int row
) {
    clearLayout(detailLayout);

    if (tunnels == nullptr || row < 0 || row >= tunnels->size()) {
        QLabel *title = label(
            presentationValue(presentation, "emptyStateTitle", "Quill WireGuard"),
            QStringLiteral("emptyStateTitle")
        );
        title->setAlignment(Qt::AlignCenter);
        QLabel *message = label(
            presentationValue(
                presentation,
                "emptyStateMessage",
                "Select a tunnel to edit and export its configuration."
            ),
            QStringLiteral("emptyStateMessage")
        );
        message->setAlignment(Qt::AlignCenter);
        detailLayout->addStretch();
        detailLayout->addWidget(title);
        detailLayout->addWidget(message);
        detailLayout->addStretch();
        return;
    }

    const QJsonObject tunnel = tunnels->at(row).toObject();

    QHBoxLayout *heading = new QHBoxLayout();
    QLineEdit *name = new QLineEdit(stringValue(tunnel, "name"));
    name->setObjectName(QStringLiteral("detailTitle"));
    name->setPlaceholderText(presentationValue(presentation, "tunnelNamePlaceholder", "Tunnel name"));
    QObject::connect(name, &QLineEdit::textChanged, [tunnels, list, row](const QString &updatedName) {
        replaceTunnelName(tunnels, row, updatedName);
        updateTunnelRowName(list, row, updatedName);
    });
    QLabel *status = label(stringValue(tunnel, "statusText"), QStringLiteral("detailStatus"));
    heading->addWidget(name, 1);
    heading->addWidget(status, 0, Qt::AlignRight);
    detailLayout->addLayout(heading);

    addInterfaceSection(detailLayout, tunnel, presentation, style);

    const QJsonArray peers = arrayValue(tunnel, "peers");
    for (const QJsonValue &value : peers) {
        addPeerSection(detailLayout, value.toObject(), presentation, style);
    }

    addExportSection(detailLayout, tunnel, presentation, style);
    detailLayout->addStretch();
}

void appendImportedTunnel(
    QJsonArray *tunnels,
    QListWidget *list,
    QLabel *countLabel,
    const QJsonObject &tunnel,
    const QJsonObject &style
) {
    if (tunnels == nullptr || list == nullptr) {
        return;
    }

    tunnels->append(tunnel);
    addTunnelRow(list, tunnel, style);
    if (countLabel != nullptr) {
        countLabel->setText(QString::number(tunnels->size()));
    }
    list->setCurrentRow(tunnels->size() - 1);
}

QJsonObject importResponseObject(
    const QString &configuration,
    QJsonArray *tunnels,
    const QJsonObject &presentation,
    quill_wireguard_qt_import_config_callback importConfig,
    quill_wireguard_qt_free_string_callback freeString,
    QString *errorText
) {
    if (importConfig == nullptr || tunnels == nullptr) {
        if (errorText != nullptr) {
            *errorText = presentationValue(
                presentation,
                "importUnavailableError",
                "WireGuard import is unavailable in this build."
            );
        }
        return QJsonObject();
    }

    const QByteArray configurationBytes = configuration.toUtf8();

    char *responsePointer = importConfig(
        configurationBytes.constData(),
        static_cast<int>(tunnels->size()),
        nullptr
    );
    if (responsePointer == nullptr) {
        if (errorText != nullptr) {
            *errorText = presentationValue(
                presentation,
                "importNoResponseError",
                "WireGuard import did not return a response."
            );
        }
        return QJsonObject();
    }

    QJsonParseError parseError;
    const QJsonDocument responseDocument = QJsonDocument::fromJson(
        QByteArray(responsePointer),
        &parseError
    );
    if (freeString != nullptr) {
        freeString(responsePointer);
    }

    if (parseError.error != QJsonParseError::NoError || !responseDocument.isObject()) {
        if (errorText != nullptr) {
            *errorText = presentationValue(
                presentation,
                "importInvalidResponseError",
                "WireGuard import returned invalid JSON."
            );
        }
        return QJsonObject();
    }

    const QJsonObject response = responseDocument.object();
    const QString responseError = stringValue(response, "errorText");
    if (!responseError.isEmpty()) {
        if (errorText != nullptr) {
            *errorText = responseError;
        }
        return QJsonObject();
    }

    const QJsonValue tunnelValue = response.value(QStringLiteral("tunnel"));
    if (!tunnelValue.isObject()) {
        if (errorText != nullptr) {
            *errorText = presentationValue(
                presentation,
                "importMissingTunnelError",
                "WireGuard import response did not include a tunnel."
            );
        }
        return QJsonObject();
    }

    if (errorText != nullptr) {
        errorText->clear();
    }
    return tunnelValue.toObject();
}

void setImportError(QLabel *error, const QString &message) {
    if (error != nullptr) {
        error->setText(message);
    }
}

void clearImportError(QLabel *error) {
    if (error != nullptr) {
        error->clear();
    }
}

void reportStartupImportError(const QString &message) {
    if (message.isEmpty()) {
        return;
    }

    const QByteArray bytes = message.toUtf8();
    std::fprintf(stderr, "quill-wireguard-qt: startup import failed: %s\n", bytes.constData());
}

bool readImportConfigurationFile(
    const QString &fileName,
    QString *configuration,
    QString *errorMessage
) {
    QFile file(fileName);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (errorMessage != nullptr) {
            *errorMessage = QStringLiteral("%1: %2").arg(fileName, file.errorString());
        }
        return false;
    }

    if (configuration != nullptr) {
        *configuration = QString::fromUtf8(file.readAll());
    }
    if (errorMessage != nullptr) {
        errorMessage->clear();
    }
    return true;
}

bool importConfigurationIntoList(
    const QString &configuration,
    QJsonArray *tunnels,
    QListWidget *list,
    QLabel *countLabel,
    const QJsonObject &presentation,
    const QJsonObject &style,
    quill_wireguard_qt_import_config_callback importConfig,
    quill_wireguard_qt_free_string_callback freeString,
    QLabel *error,
    QString *errorText = nullptr
) {
    auto fail = [&](const QString &message) {
        setImportError(error, message);
        if (errorText != nullptr) {
            *errorText = message;
        }
        return false;
    };

    const QString trimmedConfiguration = configuration.trimmed();
    if (trimmedConfiguration.isEmpty()) {
        return fail(presentationValue(
            presentation,
            "importEmptyConfigurationError",
            "Paste a WireGuard configuration before importing."
        ));
    }

    QString importError;
    const QJsonObject tunnel = importResponseObject(
        trimmedConfiguration,
        tunnels,
        presentation,
        importConfig,
        freeString,
        &importError
    );
    if (!importError.isEmpty()) {
        return fail(importError);
    }

    appendImportedTunnel(tunnels, list, countLabel, tunnel, style);
    clearImportError(error);
    if (errorText != nullptr) {
        errorText->clear();
    }
    return true;
}

QString startupImportConfigurationFile() {
    return QuillQtWidgets::environmentValue("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START");
}

bool startupImportShouldOpenDialog() {
    return QuillQtWidgets::environmentFlag("QUILLUI_WIREGUARD_QT_IMPORT_DIALOG_ON_START");
}

void showImportDialog(
    QWidget *parent,
    QJsonArray *tunnels,
    QListWidget *list,
    QLabel *countLabel,
    const QJsonObject &presentation,
    const QJsonObject &style,
    quill_wireguard_qt_import_config_callback importConfig,
    quill_wireguard_qt_free_string_callback freeString,
    const QString &initialConfiguration = QString(),
    bool submitInitialConfiguration = false
) {
    QDialog dialog(parent);
    dialog.setWindowTitle(presentationValue(
        presentation,
        "importDialogTitle",
        "Import WireGuard Configuration"
    ));
    dialog.setMinimumSize(
        intValue(style, "importDialogWidth", 560),
        intValue(style, "importDialogHeight", 420)
    );

    QVBoxLayout *layout = new QVBoxLayout(&dialog);
    layout->setSpacing(intValue(style, "importDialogSpacing", 10));

    QPlainTextEdit *editor = configurationTextEditor(style);
    editor->setObjectName(QStringLiteral("importConfigText"));
    editor->setPlaceholderText(presentationValue(
        presentation,
        "importPlaceholder",
        "[Interface]\nPrivateKey = ...\n\n[Peer]\nPublicKey = ..."
    ));
    if (!initialConfiguration.isEmpty()) {
        editor->setPlainText(initialConfiguration);
    }
    layout->addWidget(editor, 1);

    QLabel *error = label(QString(), QStringLiteral("importError"));
    error->setMinimumHeight(intValue(style, "importErrorMinHeight", 20));
    layout->addWidget(error);

    QDialogButtonBox *buttons = new QDialogButtonBox(QDialogButtonBox::Cancel);
    if (QPushButton *cancel = buttons->button(QDialogButtonBox::Cancel)) {
        cancel->setObjectName(QStringLiteral("importCancelButton"));
        cancel->setText(presentationValue(presentation, "importCancelActionLabel", "Cancel"));
    }
    QPushButton *confirm = buttons->addButton(
        presentationValue(presentation, "importActionLabel", "Import"),
        QDialogButtonBox::AcceptRole
    );
    confirm->setObjectName(QStringLiteral("importConfirmButton"));
    confirm->setDefault(true);
    confirm->setAutoDefault(true);
    QPushButton *chooseFile = buttons->addButton(
        presentationValue(presentation, "importFileActionLabel", "Choose File"),
        QDialogButtonBox::ActionRole
    );
    chooseFile->setObjectName(QStringLiteral("importChooseFileButton"));
    layout->addWidget(buttons);

    QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    auto attemptImport = [&](const QString &configuration) {
        if (importConfigurationIntoList(
            configuration,
            tunnels,
            list,
            countLabel,
            presentation,
            style,
            importConfig,
            freeString,
            error
        )) {
            dialog.accept();
            return true;
        }
        return false;
    };
    QObject::connect(confirm, &QPushButton::clicked, [&]() {
        attemptImport(editor->toPlainText());
    });

    QShortcut *importShortcut = new QShortcut(QKeySequence(QStringLiteral("Ctrl+Return")), &dialog);
    importShortcut->setContext(Qt::WindowShortcut);
    QObject::connect(importShortcut, &QShortcut::activated, [&]() {
        attemptImport(editor->toPlainText());
    });

    QObject::connect(chooseFile, &QPushButton::clicked, [&]() {
        const QString fileName = QFileDialog::getOpenFileName(
            &dialog,
            presentationValue(presentation, "importDialogTitle", "Import WireGuard Configuration"),
            QString(),
            presentationValue(
                presentation,
                "importFileFilter",
                "WireGuard configurations (*.conf *.txt);;All files (*)"
            )
        );
        if (fileName.isEmpty()) {
            return;
        }

        QString configuration;
        QString fileError;
        if (!readImportConfigurationFile(fileName, &configuration, &fileError)) {
            setImportError(error, fileError);
            return;
        }

        editor->setPlainText(configuration);
        attemptImport(configuration);
    });

    QTimer::singleShot(0, editor, [editor]() {
        editor->setFocus(Qt::OtherFocusReason);
    });
    if (submitInitialConfiguration) {
        QTimer::singleShot(0, &dialog, [&]() {
            attemptImport(editor->toPlainText());
        });
    }
    dialog.exec();
}

int selectedRow(const QJsonArray &tunnels, const QString &selectedTunnelID) {
    for (int index = 0; index < tunnels.size(); ++index) {
        if (stringValue(tunnels.at(index).toObject(), "id") == selectedTunnelID) {
            return index;
        }
    }
    return tunnels.isEmpty() ? -1 : 0;
}

void applyStyle(QApplication &app, const QJsonObject &style) {
    QString styleSheet = QStringLiteral(
        "QWidget { background: %1; color: %2; font-size: %3px; }"
        "QSplitter::handle { background: %4; width: 1px; }"
        "QListWidget { background: %5; border: 0; padding: %25px; }"
        "QListWidget::item { padding: 0; margin: %26px 0; border-radius: %6px; }"
        "QListWidget::item:selected { background: %7; color: %8; }"
        "QWidget#tunnelRow { background: transparent; }"
        "QWidget#tunnelRow QLabel { background: transparent; }"
        "QLabel#tunnelName { font-weight: 500; }"
        "QLabel#tunnelStatus, QLabel#tunnelSummary { color: %9; font-size: %10px; }"
        "QLabel#sidebarTitle { font-weight: 700; font-size: %11px; }"
        "QLabel#sidebarCount, QLabel#backendText, QLabel#detailStatus, QLabel#detailKey { color: %9; }"
        "QLabel#backendTitle { color: %9; font-weight: 700; font-size: %12px; }"
        "QLabel#emptyStateTitle { font-size: %13px; font-weight: 600; }"
        "QLabel#emptyStateMessage { color: %9; }"
        "QLabel#importError { color: %14; }"
        "QPushButton#importButton { background: %1; border: 1px solid %4; border-radius: %15px; padding: %16px %17px; }"
        "QPushButton#importButton:pressed { background: %18; }"
        "QLineEdit#detailTitle { background: transparent; border: 1px solid transparent; border-radius: %19px; padding: %27px; font-size: %20px; font-weight: 600; }"
        "QLineEdit#detailTitle:focus { background: %1; border-color: %21; }"
        "QGroupBox#detailSection { border: 0; background: %22; margin-top: %23px; padding: %24px; font-weight: 700; color: %9; }"
        "QGroupBox#detailSection::title { subcontrol-origin: margin; left: %28px; padding: 0 %29px; }"
        "QPlainTextEdit { background: %1; border: 1px solid %4; border-radius: %15px; }"
    );

    styleSheet = styleSheet
        .arg(styleValue(style, "windowBackgroundColor", "#ffffff"))
        .arg(styleValue(style, "primaryTextColor", "#1d1d1f"))
        .arg(intValue(style, "rootFontSize", 13))
        .arg(styleValue(style, "dividerColor", "#d8d8dd"))
        .arg(styleValue(style, "sidebarBackgroundColor", "#f7f7f8"))
        .arg(intValue(style, "listItemCornerRadius", 4))
        .arg(styleValue(style, "selectedRowBackgroundColor", "#e8eefc"))
        .arg(styleValue(style, "selectedRowTextColor", "#111111"))
        .arg(styleValue(style, "secondaryTextColor", "#6e6e73"))
        .arg(intValue(style, "captionFontSize", 11))
        .arg(intValue(style, "sidebarTitleFontSize", 16))
        .arg(intValue(style, "backendTitleFontSize", 11))
        .arg(intValue(style, "emptyStateTitleFontSize", 22))
        .arg(styleValue(style, "errorTextColor", "#a92222"))
        .arg(intValue(style, "importButtonCornerRadius", 4))
        .arg(intValue(style, "importButtonVerticalPadding", 4))
        .arg(intValue(style, "importButtonHorizontalPadding", 8))
        .arg(styleValue(style, "pressedButtonBackgroundColor", "#ececf0"))
        .arg(intValue(style, "detailTitleCornerRadius", 3))
        .arg(intValue(style, "detailTitleFontSize", 22))
        .arg(styleValue(style, "focusBorderColor", "#93a4c7"))
        .arg(styleValue(style, "detailSectionBackgroundColor", "#f4f4f5"))
        .arg(intValue(style, "detailSectionTopMargin", 18))
        .arg(intValue(style, "detailSectionPadding", 12))
        .arg(intValue(style, "listPadding", 6))
        .arg(intValue(style, "listItemVerticalMargin", 2))
        .arg(intValue(style, "detailTitlePadding", 2))
        .arg(intValue(style, "detailSectionTitleLeftPadding", 10))
        .arg(intValue(style, "detailSectionTitleHorizontalPadding", 3));

    app.setStyleSheet(styleSheet);
}

} // namespace

int quill_wireguard_qt_run_wireguard_json(
    int argc,
    char **argv,
    const char *payload_json,
    quill_wireguard_qt_import_config_callback import_config,
    quill_wireguard_qt_free_string_callback free_string
) {
    if (payload_json == nullptr) {
        return 64;
    }

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(QByteArray(payload_json), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return 65;
    }

    const QJsonObject payload = document.object();
    const QJsonObject presentation = objectValue(payload, "presentation");
    const QJsonObject style = objectValue(payload, "style");
    QJsonArray tunnels = arrayValue(payload, "tunnels");
    const QString selectedTunnelID = stringValue(payload, "selectedTunnelID");

    QApplication app(argc, argv);
    applyStyle(app, style);

    QWidget window;
    window.setWindowTitle(stringValue(payload, "title"));
    const QSize minimumWindowSize = resolvedMinimumWindowSize(payload);
    const QSize defaultWindowSize = resolvedDefaultWindowSize(payload, minimumWindowSize);
    window.setMinimumSize(minimumWindowSize);
    window.resize(defaultWindowSize);

    QHBoxLayout *rootLayout = new QHBoxLayout(&window);
    rootLayout->setContentsMargins(0, 0, 0, 0);

    QSplitter *splitter = new QSplitter(Qt::Horizontal);
    rootLayout->addWidget(splitter);

    QWidget *sidebar = new QWidget();
    sidebar->setMinimumWidth(intValue(style, "sidebarWidth", 280));
    sidebar->setMaximumWidth(intValue(style, "sidebarMaximumWidth", 320));
    QVBoxLayout *sidebarLayout = new QVBoxLayout(sidebar);
    const int sidebarPadding = intValue(style, "sidebarPadding", 14);
    sidebarLayout->setContentsMargins(
        sidebarPadding,
        sidebarPadding,
        sidebarPadding,
        intValue(style, "sidebarBottomPadding", 12)
    );

    QHBoxLayout *sidebarHeader = new QHBoxLayout();
    sidebarHeader->addWidget(label(
        presentationValue(presentation, "sidebarTitle", "Tunnels"),
        QStringLiteral("sidebarTitle")
    ));
    sidebarHeader->addStretch();
    QLabel *sidebarCount = label(QString::number(tunnels.size()), QStringLiteral("sidebarCount"));
    sidebarHeader->addWidget(sidebarCount);
    QPushButton *headerImportButton = new QPushButton(presentationValue(presentation, "importButtonLabel", "+"));
    headerImportButton->setObjectName(QStringLiteral("importButton"));
    headerImportButton->setToolTip(presentationValue(
        presentation,
        "importButtonTooltip",
        "Import WireGuard configuration"
    ));
    sidebarHeader->addWidget(headerImportButton);
    sidebarLayout->addLayout(sidebarHeader);

    QListWidget *list = new QListWidget();
    for (const QJsonValue &value : tunnels) {
        addTunnelRow(list, value.toObject(), style);
    }
    sidebarLayout->addWidget(list, 1);

    sidebarLayout->addWidget(label(
        presentationValue(presentation, "backendTitle", "Backend"),
        QStringLiteral("backendTitle")
    ));
    sidebarLayout->addWidget(label(stringValue(payload, "backendStatusText"), QStringLiteral("backendText")));

    QScrollArea *scrollArea = new QScrollArea();
    scrollArea->setWidgetResizable(true);
    QWidget *detail = new QWidget();
    QVBoxLayout *detailLayout = new QVBoxLayout(detail);
    const int detailPadding = intValue(style, "detailPadding", 22);
    detailLayout->setContentsMargins(detailPadding, detailPadding, detailPadding, detailPadding);
    detailLayout->setSpacing(intValue(style, "detailSpacing", 16));
    scrollArea->setWidget(detail);

    splitter->addWidget(sidebar);
    splitter->addWidget(scrollArea);
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);

    QObject::connect(list, &QListWidget::currentRowChanged, [&](int row) {
        renderDetail(detailLayout, &tunnels, list, presentation, style, row);
    });
    QObject::connect(headerImportButton, &QPushButton::clicked, [&]() {
        showImportDialog(
            &window,
            &tunnels,
            list,
            sidebarCount,
            presentation,
            style,
            import_config,
            free_string
        );
    });

    const int initialRow = selectedRow(tunnels, selectedTunnelID);
    if (initialRow >= 0) {
        list->setCurrentRow(initialRow);
    } else {
        renderDetail(detailLayout, &tunnels, list, presentation, style, initialRow);
    }

    window.show();
    const QString startupImportFile = startupImportConfigurationFile();
    if (!startupImportFile.isEmpty()) {
        const bool openStartupImportDialog = startupImportShouldOpenDialog();
        QTimer::singleShot(0, &window, [&, startupImportFile, openStartupImportDialog]() {
            QString configuration;
            QString fileError;
            if (!readImportConfigurationFile(startupImportFile, &configuration, &fileError)) {
                reportStartupImportError(fileError);
                return;
            }
            if (openStartupImportDialog) {
                showImportDialog(
                    &window,
                    &tunnels,
                    list,
                    sidebarCount,
                    presentation,
                    style,
                    import_config,
                    free_string,
                    configuration,
                    true
                );
                return;
            }
            QString importError;
            if (!importConfigurationIntoList(
                configuration,
                &tunnels,
                list,
                sidebarCount,
                presentation,
                style,
                import_config,
                free_string,
                nullptr,
                &importError
            )) {
                reportStartupImportError(importError);
            }
        });
    }
    return app.exec();
}
