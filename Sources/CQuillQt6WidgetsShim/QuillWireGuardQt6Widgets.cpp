#include "CQuillQt6WidgetsShim.h"

#include <QApplication>
#include <QByteArray>
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
#include <QListWidget>
#include <QListWidgetItem>
#include <QObject>
#include <QPlainTextEdit>
#include <QScrollArea>
#include <QSize>
#include <QSplitter>
#include <QString>
#include <QVBoxLayout>
#include <QWidget>

#include <algorithm>

namespace {

QString stringValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toString();
}

int intValue(const QJsonObject &object, const char *key, int fallback) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    return value.isDouble() ? value.toInt(fallback) : fallback;
}

QSize resolvedDefaultWindowSize(const QJsonObject &payload) {
    const int minimumWidth = intValue(payload, "minimumWidth", 900);
    const int minimumHeight = intValue(payload, "minimumHeight", 600);

    return QSize(
        std::max(intValue(payload, "defaultWidth", minimumWidth), minimumWidth),
        std::max(intValue(payload, "defaultHeight", minimumHeight), minimumHeight)
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
    bool monospaced = false
) {
    QLabel *titleLabel = label(title, QStringLiteral("detailKey"));
    QLabel *valueLabel = label(value.isEmpty() ? QStringLiteral("None") : value);
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

void addInterfaceSection(QVBoxLayout *detailLayout, const QJsonObject &tunnel) {
    const QJsonObject interfaceObject = objectValue(tunnel, "interface");
    QGroupBox *section = sectionBox(QStringLiteral("Interface"));
    QFormLayout *form = new QFormLayout(section);
    form->setLabelAlignment(Qt::AlignLeft);
    addDetailRow(form, QStringLiteral("Public key"), stringValue(interfaceObject, "publicKey"), true);
    addDetailRow(form, QStringLiteral("Addresses"), stringValue(interfaceObject, "addressesText"));
    addDetailRow(form, QStringLiteral("DNS"), stringValue(interfaceObject, "dnsServersText"));

    const QString listenPort = stringValue(interfaceObject, "listenPortText");
    if (!listenPort.isEmpty()) {
        addDetailRow(form, QStringLiteral("Listen port"), listenPort);
    }

    detailLayout->addWidget(section);
}

void addPeerSection(QVBoxLayout *detailLayout, const QJsonObject &peer) {
    QGroupBox *section = sectionBox(stringValue(peer, "name"));
    QFormLayout *form = new QFormLayout(section);
    form->setLabelAlignment(Qt::AlignLeft);
    addDetailRow(form, QStringLiteral("Public key"), stringValue(peer, "publicKey"), true);
    addDetailRow(form, QStringLiteral("Allowed IPs"), stringValue(peer, "allowedIPsText"));

    const QString endpoint = stringValue(peer, "endpointText");
    if (!endpoint.isEmpty()) {
        addDetailRow(form, QStringLiteral("Endpoint"), endpoint);
    }

    const QString keepAlive = stringValue(peer, "keepAliveText");
    if (!keepAlive.isEmpty()) {
        addDetailRow(form, QStringLiteral("Keepalive"), keepAlive);
    }

    detailLayout->addWidget(section);
}

void addExportSection(QVBoxLayout *detailLayout, const QJsonObject &tunnel) {
    QGroupBox *section = sectionBox(QStringLiteral("Export"));
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

void renderDetail(QVBoxLayout *detailLayout, const QJsonArray &tunnels, int row) {
    clearLayout(detailLayout);

    if (row < 0 || row >= tunnels.size()) {
        detailLayout->addStretch();
        detailLayout->addWidget(label(QStringLiteral("Select a tunnel to edit and export its configuration.")));
        detailLayout->addStretch();
        return;
    }

    const QJsonObject tunnel = tunnels.at(row).toObject();

    QHBoxLayout *heading = new QHBoxLayout();
    QLabel *name = label(stringValue(tunnel, "name"), QStringLiteral("detailTitle"));
    QLabel *status = label(stringValue(tunnel, "statusText"), QStringLiteral("detailStatus"));
    heading->addWidget(name, 1);
    heading->addWidget(status, 0, Qt::AlignRight);
    detailLayout->addLayout(heading);

    addInterfaceSection(detailLayout, tunnel);

    const QJsonArray peers = arrayValue(tunnel, "peers");
    for (const QJsonValue &value : peers) {
        addPeerSection(detailLayout, value.toObject());
    }

    addExportSection(detailLayout, tunnel);
    detailLayout->addStretch();
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
        "QLabel#detailTitle { font-size: 22px; font-weight: 600; }"
        "QGroupBox#detailSection { border: 0; background: #f4f4f5; margin-top: 18px; padding: 12px; font-weight: 700; color: #6e6e73; }"
        "QGroupBox#detailSection::title { subcontrol-origin: margin; left: 10px; padding: 0 3px; }"
        "QPlainTextEdit { background: #ffffff; border: 1px solid #d8d8dd; border-radius: 4px; }"
    ));
}

} // namespace

int quill_wireguard_qt_run_wireguard_json(
    int argc,
    char **argv,
    const char *payload_json
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
    const QJsonArray tunnels = arrayValue(payload, "tunnels");
    const QString selectedTunnelID = stringValue(payload, "selectedTunnelID");

    QWidget window;
    window.setWindowTitle(stringValue(payload, "title"));
    const QSize defaultWindowSize = resolvedDefaultWindowSize(payload);
    window.setMinimumSize(defaultWindowSize);
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
    sidebarHeader->addWidget(label(QStringLiteral("Tunnels"), QStringLiteral("sidebarTitle")));
    sidebarHeader->addStretch();
    sidebarHeader->addWidget(label(QString::number(tunnels.size()), QStringLiteral("sidebarCount")));
    sidebarLayout->addLayout(sidebarHeader);

    QListWidget *list = new QListWidget();
    for (const QJsonValue &value : tunnels) {
        const QJsonObject tunnel = value.toObject();
        QListWidgetItem *item = new QListWidgetItem();
        item->setSizeHint(QSize(240, 64));
        list->addItem(item);
        list->setItemWidget(item, tunnelRowWidget(tunnel));
    }
    sidebarLayout->addWidget(list, 1);

    sidebarLayout->addWidget(label(QStringLiteral("Backend"), QStringLiteral("backendTitle")));
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
        renderDetail(detailLayout, tunnels, row);
    });

    const int initialRow = selectedRow(tunnels, selectedTunnelID);
    if (initialRow >= 0) {
        list->setCurrentRow(initialRow);
    } else {
        renderDetail(detailLayout, tunnels, initialRow);
    }

    window.show();
    return app.exec();
}
