#include "CQuillQt6WidgetsShim.h"

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
#include <cstdlib>

namespace {

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

int intValue(const QJsonObject &object, const char *key, int fallback) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    return value.isDouble() ? value.toInt(fallback) : fallback;
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
        if (QWidget *widget = item->widget()) {
            delete widget;
        }
        if (QLayout *childLayout = item->layout()) {
            clearLayout(childLayout);
            delete childLayout;
        }
        delete item;
    }
}

QLabel *label(const QString &text, const QString &objectName = QString()) {
    QLabel *view = new QLabel(text);
    view->setWordWrap(true);
    if (!objectName.isEmpty()) {
        view->setObjectName(objectName);
    }
    return view;
}

void addDetailRow(
    QFormLayout *layout,
    const QString &title,
    const QString &value,
    const QString &noneText,
    bool monospaced = false
) {
    QLabel *titleLabel = label(title, QStringLiteral("detailKey"));
    QLabel *valueLabel = label(value.isEmpty() ? noneText : value);
    if (monospaced) {
        QFont font(QStringLiteral("monospace"));
        font.setStyleHint(QFont::Monospace);
        font.setPointSize(10);
        valueLabel->setFont(font);
    }
    layout->addRow(titleLabel, valueLabel);
}

QGroupBox *sectionBox(const QString &title) {
    QGroupBox *box = new QGroupBox(title.toUpper());
    box->setObjectName(QStringLiteral("detailSection"));
    return box;
}

QWidget *tunnelRowWidget(const QJsonObject &tunnel) {
    QWidget *row = new QWidget();
    row->setObjectName(QStringLiteral("tunnelRow"));

    QVBoxLayout *layout = new QVBoxLayout(row);
    layout->setContentsMargins(8, 6, 8, 6);
    layout->setSpacing(3);

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

void addTunnelRow(QListWidget *list, const QJsonObject &tunnel) {
    QListWidgetItem *item = new QListWidgetItem();
    item->setSizeHint(QSize(240, 64));
    list->addItem(item);
    list->setItemWidget(item, tunnelRowWidget(tunnel));
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
    const QJsonObject &presentation
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
        true
    );
    addDetailRow(
        form,
        presentationValue(presentation, "addressesLabel", "Addresses"),
        stringValue(interfaceObject, "addressesText"),
        noneText
    );
    addDetailRow(
        form,
        presentationValue(presentation, "dnsLabel", "DNS"),
        stringValue(interfaceObject, "dnsServersText"),
        noneText
    );

    const QString listenPort = stringValue(interfaceObject, "listenPortText");
    if (!listenPort.isEmpty()) {
        addDetailRow(
            form,
            presentationValue(presentation, "listenPortLabel", "Listen port"),
            listenPort,
            noneText
        );
    }

    detailLayout->addWidget(section);
}

void addPeerSection(
    QVBoxLayout *detailLayout,
    const QJsonObject &peer,
    const QJsonObject &presentation
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
        true
    );
    addDetailRow(
        form,
        presentationValue(presentation, "allowedIPsLabel", "Allowed IPs"),
        stringValue(peer, "allowedIPsText"),
        noneText
    );

    const QString endpoint = stringValue(peer, "endpointText");
    if (!endpoint.isEmpty()) {
        addDetailRow(
            form,
            presentationValue(presentation, "endpointLabel", "Endpoint"),
            endpoint,
            noneText
        );
    }

    const QString keepAlive = stringValue(peer, "keepAliveText");
    if (!keepAlive.isEmpty()) {
        addDetailRow(
            form,
            presentationValue(presentation, "keepAliveLabel", "Keepalive"),
            keepAlive,
            noneText
        );
    }

    detailLayout->addWidget(section);
}

void addExportSection(
    QVBoxLayout *detailLayout,
    const QJsonObject &tunnel,
    const QJsonObject &presentation
) {
    QGroupBox *section = sectionBox(presentationValue(presentation, "exportSectionTitle", "Export"));
    QVBoxLayout *layout = new QVBoxLayout(section);
    QPlainTextEdit *config = new QPlainTextEdit(stringValue(tunnel, "wgQuickConfig"));
    config->setReadOnly(true);
    config->setMinimumHeight(180);
    QFont font(QStringLiteral("monospace"));
    font.setStyleHint(QFont::Monospace);
    font.setPointSize(10);
    config->setFont(font);
    layout->addWidget(config);
    detailLayout->addWidget(section);
}

void renderDetail(
    QVBoxLayout *detailLayout,
    QJsonArray *tunnels,
    QListWidget *list,
    const QJsonObject &presentation,
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

    addInterfaceSection(detailLayout, tunnel, presentation);

    const QJsonArray peers = arrayValue(tunnel, "peers");
    for (const QJsonValue &value : peers) {
        addPeerSection(detailLayout, value.toObject(), presentation);
    }

    addExportSection(detailLayout, tunnel, presentation);
    detailLayout->addStretch();
}

void appendImportedTunnel(
    QJsonArray *tunnels,
    QListWidget *list,
    QLabel *countLabel,
    const QJsonObject &tunnel
) {
    if (tunnels == nullptr || list == nullptr) {
        return;
    }

    tunnels->append(tunnel);
    addTunnelRow(list, tunnel);
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

bool readImportConfigurationFile(
    const QString &fileName,
    QString *configuration,
    QString *errorMessage
) {
    QFile file(fileName);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (errorMessage != nullptr) {
            *errorMessage = file.errorString();
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
    quill_wireguard_qt_import_config_callback importConfig,
    quill_wireguard_qt_free_string_callback freeString,
    QLabel *error
) {
    const QString trimmedConfiguration = configuration.trimmed();
    if (trimmedConfiguration.isEmpty()) {
        setImportError(error, presentationValue(
            presentation,
            "importEmptyConfigurationError",
            "Paste a WireGuard configuration before importing."
        ));
        return false;
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
        setImportError(error, importError);
        return false;
    }

    appendImportedTunnel(tunnels, list, countLabel, tunnel);
    clearImportError(error);
    return true;
}

QString startupImportConfigurationFile() {
    const char *fileName = std::getenv("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START");
    if (fileName == nullptr || fileName[0] == '\0') {
        return QString();
    }
    return QString::fromUtf8(fileName);
}

void showImportDialog(
    QWidget *parent,
    QJsonArray *tunnels,
    QListWidget *list,
    QLabel *countLabel,
    const QJsonObject &presentation,
    quill_wireguard_qt_import_config_callback importConfig,
    quill_wireguard_qt_free_string_callback freeString
) {
    QDialog dialog(parent);
    dialog.setWindowTitle(presentationValue(
        presentation,
        "importDialogTitle",
        "Import WireGuard Configuration"
    ));
    dialog.setMinimumSize(560, 420);

    QVBoxLayout *layout = new QVBoxLayout(&dialog);
    layout->setSpacing(10);

    QPlainTextEdit *editor = new QPlainTextEdit();
    editor->setObjectName(QStringLiteral("importConfigText"));
    editor->setPlaceholderText(presentationValue(
        presentation,
        "importPlaceholder",
        "[Interface]\nPrivateKey = ...\n\n[Peer]\nPublicKey = ..."
    ));
    QFont font(QStringLiteral("monospace"));
    font.setStyleHint(QFont::Monospace);
    font.setPointSize(10);
    editor->setFont(font);
    layout->addWidget(editor, 1);

    QLabel *error = label(QString(), QStringLiteral("importError"));
    error->setMinimumHeight(20);
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
            QStringLiteral("WireGuard configurations (*.conf *.txt);;All files (*)")
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

void applyStyle(QApplication &app) {
    app.setStyleSheet(QStringLiteral(
        "QWidget { background: #ffffff; color: #1d1d1f; font-size: 13px; }"
        "QSplitter::handle { background: #d8d8dd; width: 1px; }"
        "QListWidget { background: #f7f7f8; border: 0; padding: 6px; }"
        "QListWidget::item { padding: 0; margin: 2px 0; border-radius: 4px; }"
        "QListWidget::item:selected { background: #e8eefc; color: #111111; }"
        "QWidget#tunnelRow { background: transparent; }"
        "QWidget#tunnelRow QLabel { background: transparent; }"
        "QLabel#tunnelName { font-weight: 500; }"
        "QLabel#tunnelStatus, QLabel#tunnelSummary { color: #6e6e73; font-size: 11px; }"
        "QLabel#sidebarTitle { font-weight: 700; font-size: 16px; }"
        "QLabel#sidebarCount, QLabel#backendText, QLabel#detailStatus, QLabel#detailKey { color: #6e6e73; }"
        "QLabel#backendTitle { color: #6e6e73; font-weight: 700; font-size: 11px; }"
        "QLabel#emptyStateTitle { font-size: 22px; font-weight: 600; }"
        "QLabel#emptyStateMessage { color: #6e6e73; }"
        "QLabel#importError { color: #a92222; }"
        "QPushButton#importButton { background: #ffffff; border: 1px solid #d8d8dd; border-radius: 4px; padding: 4px 8px; }"
        "QPushButton#importButton:pressed { background: #ececf0; }"
        "QLineEdit#detailTitle { background: transparent; border: 1px solid transparent; border-radius: 3px; padding: 2px; font-size: 22px; font-weight: 600; }"
        "QLineEdit#detailTitle:focus { background: #ffffff; border-color: #93a4c7; }"
        "QGroupBox#detailSection { border: 0; background: #f4f4f5; margin-top: 18px; padding: 12px; font-weight: 700; color: #6e6e73; }"
        "QGroupBox#detailSection::title { subcontrol-origin: margin; left: 10px; padding: 0 3px; }"
        "QPlainTextEdit { background: #ffffff; border: 1px solid #d8d8dd; border-radius: 4px; }"
    ));
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

    QApplication app(argc, argv);
    applyStyle(app);

    const QJsonObject payload = document.object();
    const QJsonObject presentation = objectValue(payload, "presentation");
    QJsonArray tunnels = arrayValue(payload, "tunnels");
    const QString selectedTunnelID = stringValue(payload, "selectedTunnelID");

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
    sidebar->setMinimumWidth(280);
    sidebar->setMaximumWidth(320);
    QVBoxLayout *sidebarLayout = new QVBoxLayout(sidebar);
    sidebarLayout->setContentsMargins(14, 14, 14, 12);

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
        addTunnelRow(list, value.toObject());
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
    detailLayout->setContentsMargins(22, 22, 22, 22);
    detailLayout->setSpacing(16);
    scrollArea->setWidget(detail);

    splitter->addWidget(sidebar);
    splitter->addWidget(scrollArea);
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);

    QObject::connect(list, &QListWidget::currentRowChanged, [&](int row) {
        renderDetail(detailLayout, &tunnels, list, presentation, row);
    });
    QObject::connect(headerImportButton, &QPushButton::clicked, [&]() {
        showImportDialog(
            &window,
            &tunnels,
            list,
            sidebarCount,
            presentation,
            import_config,
            free_string
        );
    });

    const int initialRow = selectedRow(tunnels, selectedTunnelID);
    if (initialRow >= 0) {
        list->setCurrentRow(initialRow);
    } else {
        renderDetail(detailLayout, &tunnels, list, presentation, initialRow);
    }

    window.show();
    const QString startupImportFile = startupImportConfigurationFile();
    if (!startupImportFile.isEmpty()) {
        QTimer::singleShot(0, &window, [&, startupImportFile]() {
            QString configuration;
            QString fileError;
            if (!readImportConfigurationFile(startupImportFile, &configuration, &fileError)) {
                return;
            }
            importConfigurationIntoList(
                configuration,
                &tunnels,
                list,
                sidebarCount,
                presentation,
                import_config,
                free_string,
                nullptr
            );
        });
    }
    return app.exec();
}
