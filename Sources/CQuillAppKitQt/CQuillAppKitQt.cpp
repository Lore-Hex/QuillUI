// CQuillAppKitQt.cpp — Qt6-Widgets implementation of the imperative C ABI in
// CQuillAppKitQt.h. Backs the AppKit shadow's NSApplication/NSWindow on Qt.
#include "CQuillAppKitQt.h"

#include <QApplication>
#include <QWidget>
#include <QString>

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

} // extern "C"
