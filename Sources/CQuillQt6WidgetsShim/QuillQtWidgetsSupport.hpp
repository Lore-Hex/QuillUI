#pragma once

#include <QByteArray>
#include <QFrame>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QLabel>
#include <QLayout>
#include <QLayoutItem>
#include <QPushButton>
#include <QRect>
#include <QString>
#include <QStyle>
#include <QWidget>

#include <cstdio>
#include <cstdlib>

namespace QuillQtWidgets {

inline QString environmentValue(const char *name) {
    const char *value = std::getenv(name);
    if (value == nullptr || value[0] == '\0') {
        return QString();
    }
    return QString::fromUtf8(value);
}

inline bool environmentFlag(const char *name) {
    const QString value = environmentValue(name).trimmed().toLower();
    return value == QStringLiteral("1")
        || value == QStringLiteral("true")
        || value == QStringLiteral("yes")
        || value == QStringLiteral("on");
}

inline QString jsonStringValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toString();
}

inline QString jsonStringValue(
    const QJsonObject &object,
    const char *key,
    const QString &fallback
) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    return value.isString() ? value.toString() : fallback;
}

inline QString jsonPresentationValue(
    const QJsonObject &presentation,
    const char *key,
    const char *fallback
) {
    return jsonStringValue(presentation, key, QString::fromUtf8(fallback));
}

inline QString jsonStyleValue(
    const QJsonObject &style,
    const char *key,
    const char *fallback
) {
    return jsonStringValue(style, key, QString::fromUtf8(fallback));
}

inline int jsonIntValue(const QJsonObject &object, const char *key, int fallback) {
    const QJsonValue value = object.value(QString::fromUtf8(key));
    return value.isDouble() ? value.toInt(fallback) : fallback;
}

inline QJsonObject jsonObjectValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toObject();
}

inline QJsonArray jsonArrayValue(const QJsonObject &object, const char *key) {
    return object.value(QString::fromUtf8(key)).toArray();
}

inline bool parseJsonObjectPayload(
    const char *payloadJson,
    const char *executableName,
    int missingPayloadExitCode,
    int invalidPayloadExitCode,
    QJsonObject *payload,
    int *exitCode
) {
    const char *name = executableName == nullptr ? "quill-qt" : executableName;
    if (payloadJson == nullptr) {
        std::fprintf(stderr, "%s: missing payload JSON\n", name);
        if (exitCode != nullptr) {
            *exitCode = missingPayloadExitCode;
        }
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(QByteArray(payloadJson), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        QByteArray reason = parseError.errorString().toUtf8();
        if (parseError.error == QJsonParseError::NoError && !document.isObject()) {
            reason = QByteArray("expected object payload");
        }
        std::fprintf(
            stderr,
            "%s: invalid payload JSON at offset %lld: %s\n",
            name,
            static_cast<long long>(parseError.offset),
            reason.constData()
        );
        if (exitCode != nullptr) {
            *exitCode = invalidPayloadExitCode;
        }
        return false;
    }

    if (payload != nullptr) {
        *payload = document.object();
    }
    if (exitCode != nullptr) {
        *exitCode = 0;
    }
    return true;
}

inline void clearLayout(QLayout *layout) {
    if (layout == nullptr) {
        return;
    }

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

inline QLabel *label(
    const QString &text,
    const QString &objectName = QString(),
    QWidget *parent = nullptr
) {
    QLabel *view = new QLabel(text, parent);
    view->setWordWrap(true);
    if (!objectName.isEmpty()) {
        view->setObjectName(objectName);
    }
    return view;
}

inline QLabel *positionedLabel(
    QWidget *parent,
    const QString &text,
    const QString &objectName,
    const QRect &geometry
) {
    QLabel *view = label(text, objectName, parent);
    view->setGeometry(geometry);
    return view;
}

inline QFrame *frame(
    const QString &objectName = QString(),
    QWidget *parent = nullptr
) {
    QFrame *view = new QFrame(parent);
    if (!objectName.isEmpty()) {
        view->setObjectName(objectName);
    }
    return view;
}

inline QFrame *positionedFrame(
    QWidget *parent,
    const QString &objectName,
    const QRect &geometry
) {
    QFrame *view = frame(objectName, parent);
    view->setGeometry(geometry);
    return view;
}

inline QPushButton *positionedButton(
    QWidget *parent,
    const QString &title,
    const QRect &geometry,
    const QString &objectName = QString()
) {
    QPushButton *button = new QPushButton(title, parent);
    if (!objectName.isEmpty()) {
        button->setObjectName(objectName);
    }
    button->setGeometry(geometry);
    return button;
}

inline void repolish(QWidget *widget) {
    if (widget == nullptr || widget->style() == nullptr) {
        return;
    }

    widget->style()->unpolish(widget);
    widget->style()->polish(widget);
}

} // namespace QuillQtWidgets
