// CQuillAppKitQt.cpp — Qt6-Widgets implementation of the imperative C ABI in
// CQuillAppKitQt.h. Backs the AppKit shadow's NSApplication/NSWindow on Qt.
#include "CQuillAppKitQt.h"

#include <QApplication>
#include <QWidget>
#include <QString>
#include <QRect>
#include <QPushButton>
#include <QLabel>

#include <string>

namespace {
// CRASH FIX (mirrors CQtBridge.cpp): QApplication's constructor is
// `QApplication(int &argc, char **argv)` — it stores a POINTER to argc, so
// argc/argv must outlive the QApplication. Static storage guarantees that.
int g_argc = 1;
char g_arg0[] = "quillappkit";
char *g_argv[] = {g_arg0, nullptr};
QApplication *g_app = nullptr;

inline QWidget *asWidget(void *handle) { return static_cast<QWidget *>(handle); }
} // namespace

extern "C" {

int quill_appkit_qt_app_init(void) {
    if (QApplication::instance() == nullptr) {
        g_app = new QApplication(g_argc, g_argv);
    }
    return QApplication::instance() != nullptr ? 1 : 0;
}

void quill_appkit_qt_app_run(void) {
    if (QApplication::instance() != nullptr) {
        QApplication::instance()->exec();
    }
}

void *quill_appkit_qt_window_new(void) {
    if (QApplication::instance() == nullptr) {
        return nullptr;
    }
    return static_cast<void *>(new QWidget());
}

void quill_appkit_qt_window_set_title(void *window, const char *utf8) {
    if (window && utf8) {
        asWidget(window)->setWindowTitle(QString::fromUtf8(utf8));
    }
}

void quill_appkit_qt_window_set_size(void *window, int width, int height) {
    if (window && width > 0 && height > 0) {
        asWidget(window)->resize(width, height);
    }
}

void quill_appkit_qt_window_present(void *window) {
    if (window) {
        asWidget(window)->show();
    }
}

void quill_appkit_qt_window_close(void *window) {
    if (window) {
        asWidget(window)->close();
    }
}

const char *quill_appkit_qt_window_title(void *window) {
    static thread_local std::string buffer;
    if (!window) {
        buffer.clear();
        return buffer.c_str();
    }
    buffer = asWidget(window)->windowTitle().toUtf8().constData();
    return buffer.c_str();
}

void quill_appkit_qt_window_size(void *window, int *width, int *height) {
    if (!window) {
        return;
    }
    QWidget *widget = asWidget(window);
    if (width) {
        *width = widget->width();
    }
    if (height) {
        *height = widget->height();
    }
}

// --- NSView ---

void *quill_appkit_qt_view_new(void) {
    if (QApplication::instance() == nullptr) {
        return nullptr;
    }
    return static_cast<void *>(new QWidget());
}

void quill_appkit_qt_view_add_subview(void *parent, void *child) {
    if (!parent || !child) {
        return;
    }
    QWidget *childWidget = asWidget(child);
    childWidget->setParent(asWidget(parent));
    childWidget->show();
}

int quill_appkit_qt_view_child_count(void *view) {
    if (!view) {
        return 0;
    }
    return asWidget(view)
        ->findChildren<QWidget *>(QString(), Qt::FindDirectChildrenOnly)
        .size();
}

void quill_appkit_qt_view_set_geometry(void *view, int x, int y, int width, int height) {
    if (view) {
        asWidget(view)->setGeometry(x, y, width, height);
    }
}

void quill_appkit_qt_view_geometry(void *view, int *x, int *y, int *width, int *height) {
    if (!view) {
        return;
    }
    QRect g = asWidget(view)->geometry();
    if (x) *x = g.x();
    if (y) *y = g.y();
    if (width) *width = g.width();
    if (height) *height = g.height();
}

void quill_appkit_qt_window_set_content_view(void *window, void *view) {
    if (!window || !view) {
        return;
    }
    QWidget *content = asWidget(view);
    content->setParent(asWidget(window));
    content->show();
}

// --- NSControl family ---
// QPushButton / QLabel derive QWidget; the void* round-trips as a QWidget* for
// the hierarchy/geometry calls above (single inheritance ⇒ same address).

void *quill_appkit_qt_button_new(const char *title) {
    if (QApplication::instance() == nullptr) {
        return nullptr;
    }
    return static_cast<void *>(new QPushButton(title ? QString::fromUtf8(title) : QString()));
}

void quill_appkit_qt_button_set_title(void *button, const char *title) {
    if (button && title) {
        static_cast<QPushButton *>(button)->setText(QString::fromUtf8(title));
    }
}

const char *quill_appkit_qt_button_title(void *button) {
    static thread_local std::string buffer;
    if (!button) {
        buffer.clear();
        return buffer.c_str();
    }
    buffer = static_cast<QPushButton *>(button)->text().toUtf8().constData();
    return buffer.c_str();
}

void *quill_appkit_qt_label_new(const char *text) {
    if (QApplication::instance() == nullptr) {
        return nullptr;
    }
    return static_cast<void *>(new QLabel(text ? QString::fromUtf8(text) : QString()));
}

void quill_appkit_qt_label_set_text(void *label, const char *text) {
    if (label && text) {
        static_cast<QLabel *>(label)->setText(QString::fromUtf8(text));
    }
}

const char *quill_appkit_qt_label_text(void *label) {
    static thread_local std::string buffer;
    if (!label) {
        buffer.clear();
        return buffer.c_str();
    }
    buffer = static_cast<QLabel *>(label)->text().toUtf8().constData();
    return buffer.c_str();
}

} // extern "C"
