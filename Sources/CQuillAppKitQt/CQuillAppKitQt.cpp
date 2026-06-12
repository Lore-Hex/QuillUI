// CQuillAppKitQt.cpp — Qt6-Widgets implementation of the imperative C ABI in
// CQuillAppKitQt.h. Backs the AppKit shadow's NSApplication/NSWindow on Qt.
#include "CQuillAppKitQt.h"

#include <QApplication>
#include <QByteArray>
#include <QImage>
#include <QPaintEvent>
#include <QPainter>
#include <QWidget>
#include <QString>
#include <QRect>
#include <QPushButton>
#include <QLabel>
#include <QPixmap>
#include <QFont>
#include <QSizePolicy>

#include <cairo.h>
#include <cstring>
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

class QuillAppKitQtDrawingWidget final : public QWidget {
public:
    QuillAppKitQtDrawingWidget(
        quill_appkit_qt_draw_callback draw,
        void *userData,
        quill_appkit_qt_destroy_callback destroy
    )
        : draw_(draw), userData_(userData), destroy_(destroy)
    {
        setAttribute(Qt::WA_OpaquePaintEvent, false);
        setAttribute(Qt::WA_NoSystemBackground, true);
        setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    }

    ~QuillAppKitQtDrawingWidget() override {
        if (destroy_ != nullptr && userData_ != nullptr) {
            destroy_(userData_);
        }
    }

protected:
    void paintEvent(QPaintEvent *) override {
        if (draw_ == nullptr || width() <= 0 || height() <= 0) {
            return;
        }

        const int surfaceWidth = width();
        const int surfaceHeight = height();
        const int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, surfaceWidth);
        if (stride <= 0) {
            return;
        }

        QByteArray pixels;
        pixels.resize(stride * surfaceHeight);
        std::memset(pixels.data(), 0, static_cast<size_t>(pixels.size()));

        cairo_surface_t *surface = cairo_image_surface_create_for_data(
            reinterpret_cast<unsigned char *>(pixels.data()),
            CAIRO_FORMAT_ARGB32,
            surfaceWidth,
            surfaceHeight,
            stride
        );
        if (surface == nullptr || cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
            if (surface != nullptr) {
                cairo_surface_destroy(surface);
            }
            return;
        }

        cairo_t *cr = cairo_create(surface);
        if (cr != nullptr && cairo_status(cr) == CAIRO_STATUS_SUCCESS) {
            draw_(static_cast<void *>(cr), surfaceWidth, surfaceHeight, userData_);
            cairo_destroy(cr);
        } else if (cr != nullptr) {
            cairo_destroy(cr);
        }
        cairo_surface_flush(surface);
        cairo_surface_destroy(surface);

        QImage image(
            reinterpret_cast<const uchar *>(pixels.constData()),
            surfaceWidth,
            surfaceHeight,
            stride,
            QImage::Format_ARGB32_Premultiplied
        );
        QPainter painter(this);
        painter.drawImage(0, 0, image);
    }

private:
    quill_appkit_qt_draw_callback draw_ = nullptr;
    void *userData_ = nullptr;
    quill_appkit_qt_destroy_callback destroy_ = nullptr;
};
} // namespace

extern "C" {

int quill_appkit_qt_app_init(void) {
    if (QApplication::instance() == nullptr) {
        g_app = new QApplication(g_argc, g_argv);
        // Give the whole AppKit-on-Qt process a macOS-class system font so
        // recompiled AppKit UI renders in a clean sans face instead of Qt's
        // serif fallback. Inter is the repo's declared SF substitute and matches
        // PaintTypography's MacFonts.controlLabel (SF Pro Text, 13pt, regular).
        // The SansSerif style hint guarantees a sans face even where Inter isn't
        // installed; the substitution chain maps the macOS family names that
        // unmodified source asks for (e.g. NSFont.systemFont) onto what's present.
        QFont systemFont("Inter");
        systemFont.setPointSize(13);
        systemFont.setStyleHint(QFont::SansSerif);
        QApplication::setFont(systemFont);
        QFont::insertSubstitutions("SF Pro Text", {"Inter", "Helvetica Neue", "Nimbus Sans", "DejaVu Sans"});
        QFont::insertSubstitutions("SF Pro", {"Inter", "Helvetica Neue", "Nimbus Sans", "DejaVu Sans"});
        QFont::insertSubstitutions(".AppleSystemUIFont", {"Inter", "Helvetica Neue", "Nimbus Sans", "DejaVu Sans"});

        // macOS-like control painting via a Qt stylesheet (an approximation — the
        // QuillPaint Mac* painters give true pixel parity in a later rung). macOS
        // push buttons: a rounded white bezel with a subtle top-down gradient and
        // a hairline border; label text in the macOS near-black (#1D1D1F). Scoped
        // to this AppKit-bridge QApplication, so it never touches the generic-Qt
        // app products (which use their own Qt runtime/process).
        g_app->setStyleSheet(R"QSS(
QPushButton {
    background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #FFFFFF, stop:1 #F4F4F6);
    border: 1px solid #C3C3C8;
    border-radius: 6px;
    padding: 3px 12px;
    color: #1D1D1F;
}
QPushButton:hover { background-color: #FAFAFB; }
QPushButton:pressed { background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #E6E6EB, stop:1 #DCDCE2); }
QPushButton:disabled { color: #AEAEB2; border-color: #DBDBE0; }
QLabel { color: #1D1D1F; }
)QSS");
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

int quill_appkit_qt_window_grab_png(void *window, const char *path) {
    if (window == nullptr || path == nullptr) {
        return 0;
    }
    QWidget *w = asWidget(window);
    // Ensure the widget tree is sized + polished so children paint when grabbed
    // (grab() works offscreen without show()). ensurePolished triggers style
    // resolution; grab() then renders the widget and all descendants.
    w->ensurePolished();
    QPixmap pixmap = w->grab();
    return pixmap.save(QString::fromUtf8(path), "PNG") ? 1 : 0;
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

void *quill_appkit_qt_drawing_view_new(
    quill_appkit_qt_draw_callback draw,
    void *user_data,
    quill_appkit_qt_destroy_callback destroy
) {
    if (QApplication::instance() == nullptr) {
        return nullptr;
    }
    return static_cast<void *>(new QuillAppKitQtDrawingWidget(draw, user_data, destroy));
}

void quill_appkit_qt_view_add_subview(void *parent, void *child) {
    if (!parent || !child) {
        return;
    }
    QWidget *childWidget = asWidget(child);
    childWidget->setParent(asWidget(parent));
    childWidget->show();
}

void quill_appkit_qt_view_update(void *view) {
    if (view) {
        asWidget(view)->update();
    }
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
