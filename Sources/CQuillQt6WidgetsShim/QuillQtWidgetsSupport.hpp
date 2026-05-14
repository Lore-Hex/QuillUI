#pragma once

#include <QFrame>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QPushButton>
#include <QRect>
#include <QString>
#include <QStyle>
#include <QWidget>

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
