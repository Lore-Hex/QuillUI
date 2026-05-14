#pragma once

#include <QFrame>
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
