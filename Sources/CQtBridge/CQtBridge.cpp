// CQtBridge.cpp — Qt6 Widgets implementation of the generic-backend C ABI.
//
// Mirrors the existing per-app shims under CQuillQt6WidgetsShim: public Qt C++
// types stay behind this C ABI so the BackendQt Swift target never imports Qt
// headers. Compiled with the Qt6Widgets include/cxx flags from Package.swift.

#include "CQtBridge.h"

#include <QApplication>
#include <QAbstractItemView>
#include <QAbstractScrollArea>
#include <QFont>
#include <QFontDatabase>
#include <QFrame>
#include <QLabel>
#include <QList>
#include <QListView>
#include <QListWidget>
#include <QListWidgetItem>
#include <QObject>
#include <QPixmap>
#include <QPushButton>
#include <QRect>
#include <QSize>
#include <QString>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <algorithm>
#include <cstdio>

namespace {

inline QWidget *asWidget(QuillQtWidgetHandle handle) {
    return reinterpret_cast<QWidget *>(handle);
}

inline QString utf8(const char *value) {
    return value == nullptr ? QString() : QString::fromUtf8(value);
}

QSize resolvedWidgetSize(QWidget *target) {
    if (target == nullptr) {
        return QSize(0, 0);
    }

    // setFixedSize() sets minimum == maximum on that axis. A widget we have
    // NOT explicitly sized keeps Qt's default minimum (0) and maximum
    // (QWIDGETSIZE_MAX), which never coincide — so equality on an axis means
    // WE fixed it (a container / frame / zero-size placeholder) and the value
    // is authoritative. An unfixed axis falls back to the intrinsic sizeHint().
    const QSize minSize = target->minimumSize();
    const QSize maxSize = target->maximumSize();
    const QSize hint = target->sizeHint();
    const bool fixedWidth = minSize.width() == maxSize.width();
    const bool fixedHeight = minSize.height() == maxSize.height();
    QSize resolved(
        fixedWidth ? minSize.width() : hint.width(),
        fixedHeight ? minSize.height() : hint.height()
    );

    // Clamp invalid sizeHints (QSize(-1, -1) for a bare QWidget) to 0 so the
    // shared layout engine never sees a negative dimension.
    if (resolved.width() < 0) {
        resolved.setWidth(0);
    }
    if (resolved.height() < 0) {
        resolved.setHeight(0);
    }
    return resolved;
}

// Stderr breadcrumb for the generic-backend smoke. The runtime crash this fix
// addresses (a dangling QApplication argc reference) produced a bare
// "*** Signal 11 ***" with no Swift backtrace under Xvfb, so each application
// lifecycle step now logs to stderr and flushes immediately. If a regression
// reappears, the CI app-log (/tmp/quillui-qt-generic-smoke-app.log) pinpoints
// the exact bridge call that ran last before the crash.
inline void bridgeTrace(const char *message) {
    std::fprintf(stderr, "[cqtbridge] %s\n", message);
    std::fflush(stderr);
}

bool materialSymbolsFontRegistered = false;

} // namespace

// --- Application lifecycle -------------------------------------------------

QuillQtAppHandle quill_qt_bridge_application_create(int argc, char **argv) {
    bridgeTrace("application_create: enter");

    // CRASH FIX (Signal 11 at startup): QApplication's constructor is
    // `QApplication(int &argc, char **argv)` — it stores a POINTER to the int
    // it is handed and keeps reading through it for the entire lifetime of the
    // application (argument parsing, QCoreApplication::arguments(), session
    // restore, etc.). The previous code passed the *by-value* `argc` parameter,
    // which lives only until this function returns. Because this generic backend
    // splits application_create from application_exec across SEPARATE call
    // frames (unlike the per-app shims, which build AND exec the QApplication in
    // one `..._run_app_json` frame so their local `argc` outlives exec()), that
    // parameter was destroyed the moment we returned the handle to Swift, and
    // the later `application_exec` ran QApplication::exec() on top of a dangling
    // `int&` — a use-after-scope segfault before the first widget rendered.
    //
    // Fix: copy argc/argv into process-lifetime storage and hand QApplication a
    // stable `int&`. The storage is function-local `static`, so it outlives
    // every subsequent bridge call (create is invoked exactly once — the app is
    // a singleton). Qt may also mutate argc/argv in place (it strips recognized
    // Qt arguments), which the mutable static supports. `argv` from Swift's
    // CommandLine.unsafeArgv already has process lifetime; we stash the pointer
    // too so argc and argv come from the same long-lived place. The QApplication
    // itself is intentionally leaked for the process lifetime (singleton, torn
    // down at exit), matching the per-app shims.
    static int stableArgc = argc;
    static char **stableArgv = argv;
    stableArgc = argc;
    stableArgv = argv;

    QApplication *app = new QApplication(stableArgc, stableArgv);
    bridgeTrace("application_create: QApplication constructed");
    return reinterpret_cast<QuillQtAppHandle>(app);
}

void quill_qt_bridge_application_set_stylesheet(
    QuillQtAppHandle app,
    const char *qss
) {
    if (app == nullptr) {
        return;
    }
    reinterpret_cast<QApplication *>(app)->setStyleSheet(utf8(qss));
}

int quill_qt_bridge_application_exec(QuillQtAppHandle app) {
    if (app == nullptr) {
        bridgeTrace("application_exec: null app handle");
        return 1;
    }
    bridgeTrace("application_exec: entering event loop");
    const int status = reinterpret_cast<QApplication *>(app)->exec();
    bridgeTrace("application_exec: event loop returned");
    return status;
}

// --- Window ----------------------------------------------------------------

QuillQtWidgetHandle quill_qt_bridge_window_create(const char *title) {
    bridgeTrace("window_create: enter (first top-level QWidget)");
    QWidget *window = new QWidget();
    window->setWindowTitle(utf8(title));
    return reinterpret_cast<QuillQtWidgetHandle>(window);
}

void quill_qt_bridge_window_resize(
    QuillQtWidgetHandle window,
    int width,
    int height
) {
    if (QWidget *widget = asWidget(window)) {
        widget->resize(width, height);
    }
}

void quill_qt_bridge_window_set_minimum_size(
    QuillQtWidgetHandle window,
    int width,
    int height
) {
    if (QWidget *widget = asWidget(window)) {
        widget->setMinimumSize(QSize(width, height));
    }
}

void quill_qt_bridge_window_set_content(
    QuillQtWidgetHandle window,
    QuillQtWidgetHandle content
) {
    QWidget *windowWidget = asWidget(window);
    QWidget *contentWidget = asWidget(content);
    if (windowWidget == nullptr || contentWidget == nullptr) {
        return;
    }
    contentWidget->setParent(windowWidget);
    // Fill the current client area. The shared layout engine sizes the
    // content's own children; here we just dock the root content to the
    // window bounds so it is visible at launch and on the first frame.
    contentWidget->setGeometry(windowWidget->rect());
    contentWidget->show();
}

// --- Generic container (absolute placement) --------------------------------

QuillQtWidgetHandle quill_qt_bridge_container_create(void) {
    QWidget *container = new QWidget();
    return reinterpret_cast<QuillQtWidgetHandle>(container);
}

void quill_qt_bridge_widget_add_child(
    QuillQtWidgetHandle parent,
    QuillQtWidgetHandle child
) {
    QWidget *parentWidget = asWidget(parent);
    QWidget *childWidget = asWidget(child);
    if (parentWidget == nullptr || childWidget == nullptr) {
        return;
    }
    childWidget->setParent(parentWidget);
    childWidget->show();
}

void quill_qt_bridge_widget_delete_children(QuillQtWidgetHandle parent) {
    QWidget *parentWidget = asWidget(parent);
    if (parentWidget == nullptr) {
        return;
    }
    // Copy the list first: deleteLater() does not mutate children() until the
    // event loop runs, but reparenting/finding by direct iteration is safest
    // over a snapshot. findChildren with Qt::FindDirectChildrenOnly returns
    // only immediate children, matching GTK's first-child/next-sibling walk.
    const QList<QWidget *> directChildren =
        parentWidget->findChildren<QWidget *>(QString(), Qt::FindDirectChildrenOnly);
    for (QWidget *child : directChildren) {
        child->hide();
        child->setParent(nullptr);
        child->deleteLater();
    }
}

void quill_qt_bridge_widget_set_geometry(
    QuillQtWidgetHandle widget,
    int x,
    int y,
    int width,
    int height
) {
    if (QWidget *target = asWidget(widget)) {
        target->setGeometry(QRect(x, y, width, height));
    }
}

void quill_qt_bridge_widget_set_fixed_size(
    QuillQtWidgetHandle widget,
    int width,
    int height
) {
    if (QWidget *target = asWidget(widget)) {
        target->setFixedSize(QSize(width, height));
    }
}

// --- Leaf widgets ----------------------------------------------------------

QuillQtWidgetHandle quill_qt_bridge_label_create(const char *text) {
    QLabel *label = new QLabel(utf8(text));
    // SwiftUI Text reports its intrinsic single-line size to the layout
    // engine; leave word-wrap off so sizeHint() is the natural text size.
    label->setWordWrap(false);
    return reinterpret_cast<QuillQtWidgetHandle>(label);
}

void quill_qt_bridge_material_symbols_register_font(const char *font_path) {
    if (materialSymbolsFontRegistered) {
        return;
    }

    const QString path = utf8(font_path);
    if (path.isEmpty()) {
        return;
    }

    const int fontId = QFontDatabase::addApplicationFont(path);
    if (fontId < 0) {
        std::fprintf(
            stderr,
            "[cqtbridge] failed to register Material Symbols font at %s\n",
            path.toUtf8().constData()
        );
        std::fflush(stderr);
        return;
    }

    materialSymbolsFontRegistered = true;
}

QuillQtWidgetHandle quill_qt_bridge_material_symbol_label_create(
    const char *glyph,
    const char *font_family,
    int point_size
) {
    QLabel *label = new QLabel(utf8(glyph));
    QFont font(utf8(font_family));
    font.setPointSize(point_size);
    font.setWeight(QFont::Normal);
    label->setFont(font);
    label->setAlignment(Qt::AlignCenter);
    label->setWordWrap(false);
    label->setFixedSize(QSize(point_size, point_size));
    return reinterpret_cast<QuillQtWidgetHandle>(label);
}

QuillQtWidgetHandle quill_qt_bridge_image_create_from_file(
    const char *path,
    int resizable
) {
    QLabel *label = new QLabel();
    label->setAlignment(Qt::AlignCenter);
    label->setPixmap(QPixmap(utf8(path)));
    label->setScaledContents(resizable != 0);
    label->setWordWrap(false);
    return reinterpret_cast<QuillQtWidgetHandle>(label);
}

QuillQtWidgetHandle quill_qt_bridge_button_create(
    const char *title,
    quill_qt_bridge_click_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QPushButton *button = new QPushButton(utf8(title));

    if (callback != nullptr) {
        QObject::connect(button, &QPushButton::clicked, button, [callback, user_data]() {
            callback(user_data);
        });
    }

    // Release the Swift-owned user_data box when the button is destroyed,
    // mirroring g_signal_connect_data's GClosureNotify. This keeps the box
    // alive exactly as long as the signal connection can fire.
    if (destroy != nullptr) {
        QObject::connect(button, &QObject::destroyed, button, [destroy, user_data]() {
            destroy(user_data);
        });
    }

    return reinterpret_cast<QuillQtWidgetHandle>(button);
}

QuillQtWidgetHandle quill_qt_bridge_list_widget_create(void) {
    QListWidget *list = new QListWidget();
    list->setSelectionMode(QAbstractItemView::NoSelection);
    list->setFrameShape(QFrame::NoFrame);
    list->setUniformItemSizes(false);
    list->setSpacing(0);
    list->setResizeMode(QListView::Adjust);
    list->setSizeAdjustPolicy(QAbstractScrollArea::AdjustToContents);
    list->setHorizontalScrollMode(QAbstractItemView::ScrollPerPixel);
    list->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    list->setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    list->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    list->setStyleSheet(
        "QListWidget {"
        " background: #ffffff;"
        " border: 1px solid rgba(17, 24, 39, 35);"
        " border-radius: 10px;"
        " padding: 0px;"
        "}"
        "QListWidget::item { border: none; }"
        "QListWidget::item:selected { background: transparent; color: #111827; }"
    );
    return reinterpret_cast<QuillQtWidgetHandle>(list);
}

void quill_qt_bridge_list_widget_add_row_widget(
    QuillQtWidgetHandle list,
    QuillQtWidgetHandle child
) {
    QListWidget *listWidget = qobject_cast<QListWidget *>(asWidget(list));
    QWidget *childWidget = asWidget(child);
    if (listWidget == nullptr || childWidget == nullptr) {
        return;
    }

    QWidget *row = new QWidget();
    row->setObjectName(QStringLiteral("quill-qt-list-row"));
    row->setAttribute(Qt::WA_StyledBackground, true);
    row->setStyleSheet(
        "QWidget#quill-qt-list-row {"
        " background: transparent;"
        " border-bottom: 1px solid rgba(17, 24, 39, 45);"
        "}"
    );

    QVBoxLayout *layout = new QVBoxLayout(row);
    layout->setContentsMargins(16, 8, 16, 8);
    layout->setSpacing(0);
    layout->addWidget(childWidget);

    const QSize childSize = resolvedWidgetSize(childWidget);
    const QSize rowSize(
        std::max(1, childSize.width() + 32),
        std::max(1, childSize.height() + 16)
    );
    row->setMinimumSize(rowSize);

    QListWidgetItem *item = new QListWidgetItem();
    item->setFlags(item->flags() & ~Qt::ItemIsSelectable);
    item->setSizeHint(rowSize);
    listWidget->addItem(item);
    listWidget->setItemWidget(item, row);
    row->show();
}

// --- Styling ---------------------------------------------------------------

void quill_qt_bridge_widget_set_object_name(
    QuillQtWidgetHandle widget,
    const char *name
) {
    if (QWidget *target = asWidget(widget)) {
        target->setObjectName(utf8(name));
    }
}

void quill_qt_bridge_widget_set_stylesheet(
    QuillQtWidgetHandle widget,
    const char *qss
) {
    if (QWidget *target = asWidget(widget)) {
        // A bare QWidget does not honor a `background-color` QSS rule unless it
        // paints a styled background. QLabel/QPushButton already do; force it
        // here so Color fills (plain QWidget + background-color) actually paint.
        target->setAttribute(Qt::WA_StyledBackground, true);
        target->setStyleSheet(utf8(qss));
    }
}

void quill_qt_bridge_widget_show(QuillQtWidgetHandle widget) {
    if (QWidget *target = asWidget(widget)) {
        bridgeTrace("widget_show: showing widget");
        target->show();
        bridgeTrace("widget_show: shown");
    }
}

void quill_qt_bridge_widget_set_visible(QuillQtWidgetHandle widget, int visible) {
    if (QWidget *target = asWidget(widget)) {
        target->setVisible(visible != 0);
    }
}

// --- Measurement -----------------------------------------------------------

void quill_qt_bridge_widget_size_hint(
    QuillQtWidgetHandle widget,
    int *out_width,
    int *out_height
) {
    QWidget *target = asWidget(widget);
    const QSize hint = target != nullptr ? target->sizeHint() : QSize(0, 0);
    if (out_width != nullptr) {
        *out_width = hint.width();
    }
    if (out_height != nullptr) {
        *out_height = hint.height();
    }
}

void quill_qt_bridge_widget_resolved_size(
    QuillQtWidgetHandle widget,
    int *out_width,
    int *out_height
) {
    const QSize resolved = resolvedWidgetSize(asWidget(widget));
    if (out_width != nullptr) {
        *out_width = resolved.width();
    }
    if (out_height != nullptr) {
        *out_height = resolved.height();
    }
}

// --- Reactive rebuild scheduling -------------------------------------------

void quill_qt_bridge_post_idle(
    quill_qt_bridge_idle_callback callback,
    void *user_data
) {
    if (callback == nullptr) {
        return;
    }
    // Post to the main loop; runs once on the next turn. Mirrors g_idle_add.
    QTimer::singleShot(0, [callback, user_data]() {
        callback(user_data);
    });
}
