// CQuillAppKitQt.cpp — Qt6-Widgets implementation of the imperative C ABI in
// CQuillAppKitQt.h. Backs the AppKit shadow's NSApplication/NSWindow on Qt.
#include "CQuillAppKitQt.h"

#include <QApplication>
#include <QBrush>
#include <QColor>
#include <QImage>
#include <QLabel>
#include <QFont>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QPointF>
#include <QPixmap>
#include <QPushButton>
#include <QRect>
#include <QString>
#include <QVariant>
#include <QVector>
#include <QWidget>

#include <algorithm>
#include <cmath>
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

constexpr const char *kQuillExternalMountProperty = "quillRepresentableRetained";
constexpr double kPi = 3.14159265358979323846;

struct QuillQtPaintState {
    QColor fill = QColor::fromRgbF(0, 0, 0, 1);
    QColor stroke = QColor::fromRgbF(0, 0, 0, 1);
    qreal alpha = 1.0;
    qreal lineWidth = 1.0;
    Qt::PenCapStyle lineCap = Qt::FlatCap;
    Qt::PenJoinStyle lineJoin = Qt::MiterJoin;
};

class QuillQtPaintContext final {
public:
    explicit QuillQtPaintContext(QPainter *painter)
        : painter(painter)
    {
        painter->setRenderHint(QPainter::Antialiasing, true);
    }

    QPainter *painter = nullptr;
    QPainterPath path;
    QuillQtPaintState state;
    QVector<QuillQtPaintState> stateStack;

    QColor colorWithAlpha(QColor color) const {
        color.setAlphaF(std::clamp(color.alphaF() * state.alpha, 0.0, 1.0));
        return color;
    }

    QPen pen() const {
        QPen pen(colorWithAlpha(state.stroke));
        pen.setWidthF(state.lineWidth);
        pen.setCapStyle(state.lineCap);
        pen.setJoinStyle(state.lineJoin);
        return pen;
    }

    QBrush brush() const {
        return QBrush(colorWithAlpha(state.fill));
    }
};

inline QuillQtPaintContext *asPaintContext(void *handle) {
    return static_cast<QuillQtPaintContext *>(handle);
}

inline QColor normalizedColor(double r, double g, double b, double a) {
    return QColor::fromRgbF(
        std::clamp(r, 0.0, 1.0),
        std::clamp(g, 0.0, 1.0),
        std::clamp(b, 0.0, 1.0),
        std::clamp(a, 0.0, 1.0)
    );
}

inline QRectF rect(double x, double y, double width, double height) {
    return QRectF(x, y, width, height);
}

class QuillCustomDrawWidget final : public QWidget {
public:
    QuillCustomDrawWidget(
        quill_appkit_qt_draw_callback draw,
        void *userData,
        quill_appkit_qt_destroy_callback destroy
    )
        : draw_(draw), userData_(userData), destroy_(destroy)
    {
        setAttribute(Qt::WA_OpaquePaintEvent, false);
        setAutoFillBackground(false);
        setMinimumSize(1, 1);
        setProperty(kQuillExternalMountProperty, true);
    }

    ~QuillCustomDrawWidget() override {
        if (destroy_ != nullptr) {
            destroy_(userData_);
        }
    }

    QSize sizeHint() const override {
        return QSize(1, 1);
    }

protected:
    void paintEvent(QPaintEvent *event) override {
        Q_UNUSED(event);
        if (draw_ == nullptr) {
            return;
        }
        QPainter painter(this);
        QuillQtPaintContext context(&painter);
        draw_(static_cast<void *>(&context), width(), height(), userData_);
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

void *quill_appkit_qt_custom_draw_view_new(
    quill_appkit_qt_draw_callback draw,
    void *user_data,
    quill_appkit_qt_destroy_callback destroy
) {
    if (QApplication::instance() == nullptr) {
        return nullptr;
    }
    return static_cast<void *>(new QuillCustomDrawWidget(draw, user_data, destroy));
}

void quill_appkit_qt_widget_detach_from_parent(void *widget) {
    if (!widget) {
        return;
    }
    QWidget *target = asWidget(widget);
    target->hide();
    target->setParent(nullptr);
}

void quill_appkit_qt_widget_update(void *widget) {
    if (widget) {
        asWidget(widget)->update();
    }
}

void quill_appkit_qt_widget_delete(void *widget) {
    if (!widget) {
        return;
    }
    QWidget *target = asWidget(widget);
    target->hide();
    target->setParent(nullptr);
    target->deleteLater();
}

void quill_appkit_qt_widget_mark_external_mount(void *widget, int retained) {
    if (widget) {
        asWidget(widget)->setProperty(kQuillExternalMountProperty, retained != 0);
    }
}

void quill_appkit_qt_paint_save(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->save();
        context->stateStack.append(context->state);
    }
}

void quill_appkit_qt_paint_restore(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->restore();
        if (!context->stateStack.isEmpty()) {
            context->state = context->stateStack.takeLast();
        }
    }
}

void quill_appkit_qt_paint_translate(void *paint_context, double x, double y) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->translate(x, y);
    }
}

void quill_appkit_qt_paint_scale(void *paint_context, double x, double y) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->scale(x, y);
    }
}

void quill_appkit_qt_paint_rotate(void *paint_context, double radians) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->rotate(radians * 180.0 / kPi);
    }
}

void quill_appkit_qt_paint_set_fill_color(void *paint_context, double r, double g, double b, double a) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->state.fill = normalizedColor(r, g, b, a);
    }
}

void quill_appkit_qt_paint_set_stroke_color(void *paint_context, double r, double g, double b, double a) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->state.stroke = normalizedColor(r, g, b, a);
    }
}

void quill_appkit_qt_paint_set_line_width(void *paint_context, double width) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->state.lineWidth = std::max(0.0, width);
    }
}

void quill_appkit_qt_paint_set_line_cap(void *paint_context, int cap) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        switch (cap) {
        case 1:
            context->state.lineCap = Qt::RoundCap;
            break;
        case 2:
            context->state.lineCap = Qt::SquareCap;
            break;
        default:
            context->state.lineCap = Qt::FlatCap;
            break;
        }
    }
}

void quill_appkit_qt_paint_set_line_join(void *paint_context, int join) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        switch (join) {
        case 1:
            context->state.lineJoin = Qt::RoundJoin;
            break;
        case 2:
            context->state.lineJoin = Qt::BevelJoin;
            break;
        default:
            context->state.lineJoin = Qt::MiterJoin;
            break;
        }
    }
}

void quill_appkit_qt_paint_set_alpha(void *paint_context, double alpha) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->state.alpha = std::clamp(alpha, 0.0, 1.0);
    }
}

void quill_appkit_qt_paint_fill_rect(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->fillRect(rect(x, y, width, height), context->brush());
    }
}

void quill_appkit_qt_paint_stroke_rect(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setPen(context->pen());
        context->painter->setBrush(Qt::NoBrush);
        context->painter->drawRect(rect(x, y, width, height));
    }
}

void quill_appkit_qt_paint_fill_ellipse(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setPen(Qt::NoPen);
        context->painter->setBrush(context->brush());
        context->painter->drawEllipse(rect(x, y, width, height));
    }
}

void quill_appkit_qt_paint_stroke_ellipse(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setPen(context->pen());
        context->painter->setBrush(Qt::NoBrush);
        context->painter->drawEllipse(rect(x, y, width, height));
    }
}

void quill_appkit_qt_paint_clear_rect(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->save();
        context->painter->setCompositionMode(QPainter::CompositionMode_Clear);
        context->painter->fillRect(rect(x, y, width, height), Qt::transparent);
        context->painter->restore();
    }
}

void quill_appkit_qt_paint_stroke_line_segments(void *paint_context, const double *xy_pairs, int point_count) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        if (xy_pairs == nullptr || point_count < 2) {
            return;
        }
        context->painter->setPen(context->pen());
        context->painter->setBrush(Qt::NoBrush);
        for (int i = 0; i + 1 < point_count; i += 2) {
            const double x1 = xy_pairs[i * 2];
            const double y1 = xy_pairs[i * 2 + 1];
            const double x2 = xy_pairs[(i + 1) * 2];
            const double y2 = xy_pairs[(i + 1) * 2 + 1];
            context->painter->drawLine(QPointF(x1, y1), QPointF(x2, y2));
        }
    }
}

void quill_appkit_qt_paint_begin_path(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->path = QPainterPath();
    }
}

void quill_appkit_qt_paint_close_path(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->path.closeSubpath();
    }
}

void quill_appkit_qt_paint_move_to(void *paint_context, double x, double y) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->path.moveTo(x, y);
    }
}

void quill_appkit_qt_paint_add_line_to(void *paint_context, double x, double y) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->path.lineTo(x, y);
    }
}

void quill_appkit_qt_paint_add_rect(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->path.addRect(rect(x, y, width, height));
    }
}

void quill_appkit_qt_paint_add_ellipse(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->path.addEllipse(rect(x, y, width, height));
    }
}

void quill_appkit_qt_paint_add_arc(
    void *paint_context,
    double center_x,
    double center_y,
    double radius,
    double start_angle,
    double end_angle,
    int clockwise
) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        const QRectF bounds(center_x - radius, center_y - radius, radius * 2.0, radius * 2.0);
        const double startDegrees = -start_angle * 180.0 / kPi;
        double spanDegrees = -(end_angle - start_angle) * 180.0 / kPi;
        if (clockwise != 0 && spanDegrees > 0) {
            spanDegrees -= 360.0;
        } else if (clockwise == 0 && spanDegrees < 0) {
            spanDegrees += 360.0;
        }
        context->path.arcTo(bounds, startDegrees, spanDegrees);
    }
}

void quill_appkit_qt_paint_fill_path(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setPen(Qt::NoPen);
        context->painter->setBrush(context->brush());
        context->painter->drawPath(context->path);
        context->path = QPainterPath();
    }
}

void quill_appkit_qt_paint_stroke_path(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setPen(context->pen());
        context->painter->setBrush(Qt::NoBrush);
        context->painter->drawPath(context->path);
        context->path = QPainterPath();
    }
}

void quill_appkit_qt_paint_clip(void *paint_context) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setClipPath(context->path, Qt::IntersectClip);
        context->path = QPainterPath();
    }
}

void quill_appkit_qt_paint_clip_rect(void *paint_context, double x, double y, double width, double height) {
    if (QuillQtPaintContext *context = asPaintContext(paint_context)) {
        context->painter->setClipRect(rect(x, y, width, height), Qt::IntersectClip);
    }
}

void quill_appkit_qt_paint_draw_bgra_image(
    void *paint_context,
    const unsigned char *pixels,
    int width,
    int height,
    int stride,
    double x,
    double y,
    double target_width,
    double target_height,
    int nearest
) {
    QuillQtPaintContext *context = asPaintContext(paint_context);
    if (context == nullptr || pixels == nullptr || width <= 0 || height <= 0 || stride <= 0) {
        return;
    }

    QImage image(pixels, width, height, stride, QImage::Format_ARGB32_Premultiplied);
    context->painter->save();
    context->painter->setRenderHint(QPainter::SmoothPixmapTransform, nearest == 0);
    context->painter->drawImage(rect(x, y, target_width, target_height), image);
    context->painter->restore();
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
