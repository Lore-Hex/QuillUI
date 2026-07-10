// CQtBridge.cpp — Qt6 Widgets implementation of the generic-backend C ABI.
//
// Mirrors the existing per-app shims under CQuillQt6WidgetsShim: public Qt C++
// types stay behind this C ABI so the BackendQt Swift target never imports Qt
// headers. Compiled with the Qt6Widgets include/cxx flags from Package.swift.

#include "CQtBridge.h"

#include <QApplication>
#include <QAbstractItemView>
#include <QAbstractScrollArea>
#include <QAbstractButton>
#include <QAction>
#include <QByteArray>
#include <QCheckBox>
#include <QClipboard>
#include <QComboBox>
#include <QEvent>
#include <QFont>
#include <QFontDatabase>
#include <QFrame>
#include <QGridLayout>
#include <QButtonGroup>
#include <QHBoxLayout>
#include <QLabel>
#include <QKeyEvent>
#include <QLineEdit>
#include <QList>
#include <QListView>
#include <QListWidget>
#include <QListWidgetItem>
#include <QMenu>
#include <QObject>
#include <QPixmap>
#include <QPointer>
#include <QPoint>
#include <QProgressBar>
#include <QPushButton>
#include <QRect>
#include <QScreen>
#include <QSize>
#include <QScrollArea>
#include <QString>
#include <QSizePolicy>
#include <QTimer>
#include <QToolButton>
#include <QVBoxLayout>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <utility>

namespace {

inline QWidget *asWidget(QuillQtWidgetHandle handle) {
    return reinterpret_cast<QWidget *>(handle);
}

inline QString utf8(const char *value) {
    return value == nullptr ? QString() : QString::fromUtf8(value);
}

bool widgetContains(QWidget *root, QWidget *candidate);

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

Qt::Alignment overlayAlignment(int horizontal, int vertical) {
    Qt::Alignment alignment = {};

    switch (horizontal) {
    case 0:
        alignment |= Qt::AlignLeft;
        break;
    case 2:
        alignment |= Qt::AlignRight;
        break;
    default:
        alignment |= Qt::AlignHCenter;
        break;
    }

    switch (vertical) {
    case 0:
        alignment |= Qt::AlignTop;
        break;
    case 2:
        alignment |= Qt::AlignBottom;
        break;
    default:
        alignment |= Qt::AlignVCenter;
        break;
    }

    return alignment;
}

class QuillQtDividerFrame final : public QFrame {
public:
    explicit QuillQtDividerFrame(QWidget *parent = nullptr)
        : QFrame(parent)
    {
        setObjectName(QStringLiteral("quill-qt-divider"));
        setOrientation(Qt::Horizontal);
    }

    QSize sizeHint() const override {
        return QSize(1, 1);
    }

    void setOrientation(Qt::Orientation orientation) {
        orientation_ = orientation;
        setFrameShape(orientation == Qt::Horizontal ? QFrame::HLine : QFrame::VLine);
        setFrameShadow(QFrame::Plain);
        setLineWidth(1);
        setMidLineWidth(0);

        if (orientation == Qt::Horizontal) {
            setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
            setMinimumWidth(1);
            setMaximumWidth(QWIDGETSIZE_MAX);
            setMinimumHeight(1);
            setMaximumHeight(1);
        } else {
            setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Expanding);
            setMinimumWidth(1);
            setMaximumWidth(1);
            setMinimumHeight(1);
            setMaximumHeight(QWIDGETSIZE_MAX);
        }
    }

private:
    Qt::Orientation orientation_ = Qt::Horizontal;
};

class QuillQtHoverState final {
public:
    QuillQtHoverState(
        quill_qt_bridge_hover_callback callback,
        void *userData,
        quill_qt_bridge_click_callback destroy
    )
        : callback_(callback),
          userData_(userData),
          destroy_(destroy)
    {
    }

    ~QuillQtHoverState() {
        if (destroy_ != nullptr && userData_ != nullptr) {
            destroy_(userData_);
        }
    }

    void update(bool hovered) {
        if (hovered_ == hovered) {
            return;
        }
        hovered_ = hovered;
        if (callback_ != nullptr) {
            callback_(hovered ? 1 : 0, userData_);
        }
    }

private:
    quill_qt_bridge_hover_callback callback_;
    void *userData_;
    quill_qt_bridge_click_callback destroy_;
    bool hovered_ = false;
};

class QuillQtHoverFilter final : public QObject {
public:
    QuillQtHoverFilter(
        std::shared_ptr<QuillQtHoverState> state,
        QObject *parent
    )
        : QObject(parent),
          state_(std::move(state))
    {
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        switch (event->type()) {
        case QEvent::Enter:
            state_->update(true);
            break;
        case QEvent::Leave:
            state_->update(false);
            break;
        default:
            break;
        }
        return QObject::eventFilter(watched, event);
    }

private:
    std::shared_ptr<QuillQtHoverState> state_;
};

class QuillQtFocusState final {
public:
    QuillQtFocusState(
        quill_qt_bridge_focus_callback callback,
        void *userData,
        quill_qt_bridge_click_callback destroy
    )
        : callback_(callback),
          userData_(userData),
          destroy_(destroy)
    {
    }

    ~QuillQtFocusState() {
        if (destroy_ != nullptr && userData_ != nullptr) {
            destroy_(userData_);
        }
    }

    void update(bool focused) {
        if (focused_ == focused) {
            return;
        }
        focused_ = focused;
        if (callback_ != nullptr) {
            callback_(focused ? 1 : 0, userData_);
        }
    }

private:
    quill_qt_bridge_focus_callback callback_;
    void *userData_;
    quill_qt_bridge_click_callback destroy_;
    bool focused_ = false;
};

class QuillQtFocusFilter final : public QObject {
public:
    QuillQtFocusFilter(
        std::shared_ptr<QuillQtFocusState> state,
        QObject *parent
    )
        : QObject(parent),
          state_(std::move(state))
    {
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        switch (event->type()) {
        case QEvent::FocusIn:
            state_->update(true);
            break;
        case QEvent::FocusOut:
            state_->update(false);
            break;
        default:
            break;
        }
        return QObject::eventFilter(watched, event);
    }

private:
    std::shared_ptr<QuillQtFocusState> state_;
};

class QuillQtPopoverState final {
public:
    QuillQtPopoverState(
        quill_qt_bridge_click_callback closed,
        void *userData,
        quill_qt_bridge_click_callback destroy
    )
        : closed_(closed),
          userData_(userData),
          destroy_(destroy)
    {
    }

    ~QuillQtPopoverState() {
        release();
    }

    void notifyClosed() {
        if (closed_ != nullptr && userData_ != nullptr) {
            closed_(userData_);
        }
        release();
    }

private:
    void release() {
        if (destroy_ != nullptr && userData_ != nullptr) {
            destroy_(userData_);
        }
        userData_ = nullptr;
        closed_ = nullptr;
        destroy_ = nullptr;
    }

    quill_qt_bridge_click_callback closed_;
    void *userData_;
    quill_qt_bridge_click_callback destroy_;
};

class QuillQtPopoverFilter final : public QObject {
public:
    QuillQtPopoverFilter(
        std::shared_ptr<QuillQtPopoverState> state,
        QObject *parent
    )
        : QObject(parent),
          state_(std::move(state))
    {
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        switch (event->type()) {
        case QEvent::Hide:
        case QEvent::Close:
        case QEvent::DeferredDelete:
        case QEvent::Destroy:
            state_->notifyClosed();
            break;
        default:
            break;
        }
        return QObject::eventFilter(watched, event);
    }

private:
    std::shared_ptr<QuillQtPopoverState> state_;
};

class QuillQtKeyPressState final {
public:
    QuillQtKeyPressState(
        quill_qt_bridge_key_callback callback,
        void *userData,
        quill_qt_bridge_click_callback destroy
    )
        : callback_(callback),
          userData_(userData),
          destroy_(destroy)
    {
    }

    ~QuillQtKeyPressState() {
        if (destroy_ != nullptr && userData_ != nullptr) {
            destroy_(userData_);
        }
    }

    bool handle(int key) {
        if (callback_ == nullptr || key == 0) {
            return false;
        }
        return callback_(key, userData_) != 0;
    }

private:
    quill_qt_bridge_key_callback callback_;
    void *userData_;
    quill_qt_bridge_click_callback destroy_;
};

class QuillQtShortcutState final {
public:
    QuillQtShortcutState(
        quill_qt_bridge_shortcut_callback callback,
        void *userData,
        quill_qt_bridge_click_callback destroy
    )
        : callback_(callback),
          userData_(userData),
          destroy_(destroy)
    {
    }

    ~QuillQtShortcutState() {
        if (destroy_ != nullptr && userData_ != nullptr) {
            destroy_(userData_);
        }
    }

    bool handle(int key, int modifiers) {
        if (callback_ == nullptr || key == 0) {
            return false;
        }
        return callback_(key, modifiers, userData_) != 0;
    }

private:
    quill_qt_bridge_shortcut_callback callback_;
    void *userData_;
    quill_qt_bridge_click_callback destroy_;
};

int quillQtKeyEquivalent(QKeyEvent *event) {
    if (event == nullptr) {
        return 0;
    }

    switch (event->key()) {
    case Qt::Key_Return:
    case Qt::Key_Enter:
        return '\r';
    case Qt::Key_Escape:
        return 0x1B;
    case Qt::Key_Backspace:
        return 0x7F;
    case Qt::Key_Delete:
        return 0xF728;
    case Qt::Key_Tab:
    case Qt::Key_Backtab:
        return '\t';
    case Qt::Key_Up:
        return 0xF700;
    case Qt::Key_Down:
        return 0xF701;
    case Qt::Key_Left:
        return 0xF702;
    case Qt::Key_Right:
        return 0xF703;
    case Qt::Key_Space:
        return ' ';
    default:
        break;
    }

    const QString text = event->text();
    if (text.isEmpty()) {
        return 0;
    }
    const uint scalar = text.at(0).unicode();
    return scalar == 0 ? 0 : static_cast<int>(scalar);
}

int quillQtEventModifiers(QKeyEvent *event) {
    if (event == nullptr) {
        return 0;
    }

    const Qt::KeyboardModifiers qtModifiers = event->modifiers();
    int modifiers = 0;
    // SwiftOpenUI EventModifiers raw bits.
    constexpr int shift = 1 << 1;
    constexpr int option = 1 << 3;
    constexpr int command = 1 << 4;
    constexpr int numericPad = 1 << 5;

    if (qtModifiers & Qt::ShiftModifier) {
        modifiers |= shift;
    }
    if (qtModifiers & Qt::AltModifier) {
        modifiers |= option;
    }
    // Match the GTK backend and desktop convention: app-authored command
    // shortcuts are activated by Control on Linux. Meta is accepted as command
    // too for keyboards/window managers that surface it separately.
    if ((qtModifiers & Qt::ControlModifier) || (qtModifiers & Qt::MetaModifier)) {
        modifiers |= command;
    }
    if (qtModifiers & Qt::KeypadModifier) {
        modifiers |= numericPad;
    }
    return modifiers;
}

class QuillQtKeyPressFilter final : public QObject {
public:
    QuillQtKeyPressFilter(
        std::shared_ptr<QuillQtKeyPressState> state,
        QObject *parent
    )
        : QObject(parent),
          state_(std::move(state))
    {
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (event->type() != QEvent::KeyPress) {
            return QObject::eventFilter(watched, event);
        }

        QKeyEvent *keyEvent = static_cast<QKeyEvent *>(event);
        if (state_->handle(quillQtKeyEquivalent(keyEvent))) {
            return true;
        }
        return QObject::eventFilter(watched, event);
    }

private:
    std::shared_ptr<QuillQtKeyPressState> state_;
};

class QuillQtShortcutFilter final : public QObject {
public:
    QuillQtShortcutFilter(
        QWidget *window,
        std::shared_ptr<QuillQtShortcutState> state,
        QObject *parent
    )
        : QObject(parent),
          window_(window),
          state_(std::move(state))
    {
    }

    ~QuillQtShortcutFilter() override {
        if (qApp != nullptr) {
            qApp->removeEventFilter(this);
        }
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (event->type() != QEvent::KeyPress) {
            return QObject::eventFilter(watched, event);
        }

        QWidget *target = qobject_cast<QWidget *>(watched);
        if (!widgetContains(window_, target)) {
            return QObject::eventFilter(watched, event);
        }

        QKeyEvent *keyEvent = static_cast<QKeyEvent *>(event);
        if (state_->handle(
                quillQtKeyEquivalent(keyEvent),
                quillQtEventModifiers(keyEvent)
            )) {
            return true;
        }
        return QObject::eventFilter(watched, event);
    }

private:
    QWidget *window_;
    std::shared_ptr<QuillQtShortcutState> state_;
};

void installHoverFilterRecursive(
    QWidget *target,
    const std::shared_ptr<QuillQtHoverState> &state
) {
    if (target == nullptr) {
        return;
    }

    target->setAttribute(Qt::WA_Hover, true);
    target->setMouseTracking(true);
    target->installEventFilter(new QuillQtHoverFilter(state, target));

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        installHoverFilterRecursive(child, state);
    }
}

void installFocusFilterRecursive(
    QWidget *target,
    const std::shared_ptr<QuillQtFocusState> &state
) {
    if (target == nullptr) {
        return;
    }

    target->installEventFilter(new QuillQtFocusFilter(state, target));

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        installFocusFilterRecursive(child, state);
    }
}

void installKeyPressFilterRecursive(
    QWidget *target,
    const std::shared_ptr<QuillQtKeyPressState> &state
) {
    if (target == nullptr) {
        return;
    }

    target->installEventFilter(new QuillQtKeyPressFilter(state, target));

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        installKeyPressFilterRecursive(child, state);
    }
}

bool widgetContains(QWidget *root, QWidget *candidate) {
    if (root == nullptr || candidate == nullptr) {
        return false;
    }
    for (QWidget *cursor = candidate; cursor != nullptr; cursor = cursor->parentWidget()) {
        if (cursor == root) {
            return true;
        }
    }
    return false;
}

QWidget *firstFocusableWidget(QWidget *target) {
    if (target == nullptr || !target->isEnabled()) {
        return nullptr;
    }
    if (target->focusPolicy() != Qt::NoFocus) {
        return target;
    }

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        if (QWidget *focusable = firstFocusableWidget(child)) {
            return focusable;
        }
    }
    return nullptr;
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

// --- Clipboard -------------------------------------------------------------

int quill_qt_bridge_clipboard_set_text(const char *text) {
    if (QClipboard *clipboard = QApplication::clipboard()) {
        clipboard->setText(utf8(text));
        return 1;
    }
    return 0;
}

const char *quill_qt_bridge_clipboard_text(void) {
    static QByteArray text;
    if (QClipboard *clipboard = QApplication::clipboard()) {
        text = clipboard->text().toUtf8();
        return text.constData();
    }
    return nullptr;
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

QuillQtWidgetHandle quill_qt_make_overlay_container(void) {
    QWidget *container = new QWidget();
    QGridLayout *layout = new QGridLayout();
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);
    container->setLayout(layout);
    return reinterpret_cast<QuillQtWidgetHandle>(container);
}

QuillQtWidgetHandle quill_qt_make_grid_container(int column_count) {
    QWidget *container = new QWidget();
    QGridLayout *layout = new QGridLayout();
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    const int columns = std::max(1, column_count);
    for (int column = 0; column < columns; ++column) {
        layout->setColumnStretch(column, 1);
    }

    container->setLayout(layout);
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

void quill_qt_overlay_container_add_child(
    QuillQtWidgetHandle container,
    QuillQtWidgetHandle child,
    int horizontal_alignment,
    int vertical_alignment
) {
    QWidget *containerWidget = qobject_cast<QWidget *>(asWidget(container));
    QWidget *childWidget = qobject_cast<QWidget *>(asWidget(child));
    if (containerWidget == nullptr || childWidget == nullptr) {
        return;
    }

    QGridLayout *layout = qobject_cast<QGridLayout *>(containerWidget->layout());
    if (layout == nullptr) {
        return;
    }

    layout->addWidget(
        childWidget,
        0,
        0,
        overlayAlignment(horizontal_alignment, vertical_alignment)
    );
    childWidget->show();
    childWidget->raise();
}

void quill_qt_grid_container_set_spacing(
    QuillQtWidgetHandle container,
    int horizontal_spacing,
    int vertical_spacing
) {
    QWidget *containerWidget = qobject_cast<QWidget *>(asWidget(container));
    if (containerWidget == nullptr) {
        return;
    }

    QGridLayout *layout = qobject_cast<QGridLayout *>(containerWidget->layout());
    if (layout == nullptr) {
        return;
    }

    layout->setHorizontalSpacing(std::max(0, horizontal_spacing));
    layout->setVerticalSpacing(std::max(0, vertical_spacing));
}

void quill_qt_grid_container_add_child(
    QuillQtWidgetHandle container,
    QuillQtWidgetHandle child,
    int row,
    int column
) {
    QWidget *containerWidget = qobject_cast<QWidget *>(asWidget(container));
    QWidget *childWidget = qobject_cast<QWidget *>(asWidget(child));
    if (containerWidget == nullptr || childWidget == nullptr) {
        return;
    }

    QGridLayout *layout = qobject_cast<QGridLayout *>(containerWidget->layout());
    if (layout == nullptr) {
        return;
    }

    layout->addWidget(childWidget, std::max(0, row), std::max(0, column));
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

void quill_qt_popover_show_for_anchor(
    QuillQtWidgetHandle anchor,
    QuillQtWidgetHandle popover,
    int vertical_gap,
    quill_qt_bridge_click_callback closed,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QPointer<QWidget> anchorWidget(asWidget(anchor));
    QPointer<QWidget> popoverWidget(asWidget(popover));
    const int gap = std::max(0, vertical_gap);
    auto state = std::make_shared<QuillQtPopoverState>(closed, user_data, destroy);

    if (anchorWidget.isNull() || popoverWidget.isNull()) {
        if (!popoverWidget.isNull()) {
            popoverWidget->deleteLater();
        }
        return;
    }

    popoverWidget->setParent(anchorWidget, Qt::Popup | Qt::FramelessWindowHint);
    popoverWidget->setAttribute(Qt::WA_DeleteOnClose, true);
    popoverWidget->installEventFilter(new QuillQtPopoverFilter(state, popoverWidget));

    QTimer::singleShot(0, [anchorWidget, popoverWidget, gap, state]() {
        (void)state;
        if (anchorWidget.isNull() || popoverWidget.isNull()) {
            if (!popoverWidget.isNull()) {
                popoverWidget->deleteLater();
            }
            return;
        }

        const QSize natural = resolvedWidgetSize(popoverWidget);
        popoverWidget->resize(natural);

        const QPoint anchorTopLeft = anchorWidget->mapToGlobal(QPoint(0, 0));
        QPoint origin = anchorWidget->mapToGlobal(QPoint(0, anchorWidget->height() + gap));
        QScreen *screen = anchorWidget->screen();
        if (screen == nullptr) {
            screen = QApplication::primaryScreen();
        }
        if (screen != nullptr) {
            const QRect available = screen->availableGeometry();
            if (origin.x() + natural.width() > available.right()) {
                origin.setX(std::max(available.left(), available.right() - natural.width()));
            }
            if (origin.y() + natural.height() > available.bottom()) {
                origin.setY(std::max(available.top(), anchorTopLeft.y() - natural.height() - gap));
            }
        }

        popoverWidget->move(origin);
        popoverWidget->show();
        popoverWidget->raise();
        popoverWidget->activateWindow();
    });
}

// --- Leaf widgets ----------------------------------------------------------

QuillQtWidgetHandle quill_qt_bridge_label_create(const char *text) {
    QLabel *label = new QLabel(utf8(text));
    // SwiftUI Text reports its intrinsic single-line size to the layout
    // engine; leave word-wrap off so sizeHint() is the natural text size.
    label->setWordWrap(false);
    return reinterpret_cast<QuillQtWidgetHandle>(label);
}

void quill_qt_widget_set_text_selectable_recursive(
    QuillQtWidgetHandle widget,
    int selectable
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        return;
    }

    if (QLabel *label = qobject_cast<QLabel *>(target)) {
        label->setTextInteractionFlags(
            selectable != 0
                ? (Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard)
                : Qt::NoTextInteraction
        );
    }

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        quill_qt_widget_set_text_selectable_recursive(
            reinterpret_cast<QuillQtWidgetHandle>(child),
            selectable
        );
    }
}

void quill_qt_widget_install_hover_recursive(
    QuillQtWidgetHandle widget,
    quill_qt_bridge_hover_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    installHoverFilterRecursive(
        target,
        std::make_shared<QuillQtHoverState>(callback, user_data, destroy)
    );
}

void quill_qt_widget_install_focus_recursive(
    QuillQtWidgetHandle widget,
    quill_qt_bridge_focus_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    installFocusFilterRecursive(
        target,
        std::make_shared<QuillQtFocusState>(callback, user_data, destroy)
    );
}

void quill_qt_widget_install_key_press_recursive(
    QuillQtWidgetHandle widget,
    quill_qt_bridge_key_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    installKeyPressFilterRecursive(
        target,
        std::make_shared<QuillQtKeyPressState>(callback, user_data, destroy)
    );
}

void quill_qt_widget_install_shortcut_dispatcher(
    QuillQtWidgetHandle window,
    quill_qt_bridge_shortcut_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QWidget *target = asWidget(window);
    if (target == nullptr || qApp == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    QuillQtShortcutFilter *filter = new QuillQtShortcutFilter(
        target,
        std::make_shared<QuillQtShortcutState>(callback, user_data, destroy),
        target
    );
    qApp->installEventFilter(filter);
}

void quill_qt_widget_connect_destroyed(
    QuillQtWidgetHandle widget,
    quill_qt_bridge_click_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        if (callback != nullptr && user_data != nullptr) {
            callback(user_data);
        }
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    QObject::connect(target, &QObject::destroyed, target, [callback, destroy, user_data]() {
        if (callback != nullptr) {
            callback(user_data);
        }
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
    });
}

void quill_qt_widget_request_focus_recursive(QuillQtWidgetHandle widget) {
    QWidget *target = asWidget(widget);
    QWidget *focusable = firstFocusableWidget(target);
    if (focusable == nullptr) {
        return;
    }
    if (QWidget *window = focusable->window()) {
        window->activateWindow();
        window->raise();
    }
    focusable->setFocus(Qt::OtherFocusReason);
}

void quill_qt_widget_request_focus_recursive_later(QuillQtWidgetHandle widget) {
    QPointer<QWidget> target(asWidget(widget));
    QTimer::singleShot(0, [target]() {
        if (target.isNull()) {
            return;
        }
        quill_qt_widget_request_focus_recursive(reinterpret_cast<QuillQtWidgetHandle>(target.data()));
    });
}

void quill_qt_widget_clear_focus_recursive(QuillQtWidgetHandle widget) {
    QWidget *target = asWidget(widget);
    QWidget *focused = QApplication::focusWidget();
    if (!widgetContains(target, focused)) {
        return;
    }
    focused->clearFocus();
}

void quill_qt_widget_set_allows_hit_testing_recursive(
    QuillQtWidgetHandle widget,
    int enabled
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        return;
    }

    if (enabled == 0) {
        target->setAttribute(Qt::WA_TransparentForMouseEvents, true);
        target->setFocusPolicy(Qt::NoFocus);
    } else {
        target->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    }

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        quill_qt_widget_set_allows_hit_testing_recursive(
            reinterpret_cast<QuillQtWidgetHandle>(child),
            enabled
        );
    }
}

void quill_qt_widget_set_enabled_recursive(
    QuillQtWidgetHandle widget,
    int enabled
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        return;
    }

    target->setEnabled(enabled != 0);

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        quill_qt_widget_set_enabled_recursive(
            reinterpret_cast<QuillQtWidgetHandle>(child),
            enabled
        );
    }
}

void quill_qt_widget_set_tooltip_recursive(
    QuillQtWidgetHandle widget,
    const char *text
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        return;
    }

    const QString tooltip = utf8(text);
    target->setToolTip(tooltip);
    target->setAccessibleDescription(tooltip);

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        quill_qt_widget_set_tooltip_recursive(
            reinterpret_cast<QuillQtWidgetHandle>(child),
            text
        );
    }
}

void quill_qt_widget_set_accessible_name_recursive(
    QuillQtWidgetHandle widget,
    const char *text
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        return;
    }

    const QString name = utf8(text);
    target->setAccessibleName(name);

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        quill_qt_widget_set_accessible_name_recursive(
            reinterpret_cast<QuillQtWidgetHandle>(child),
            text
        );
    }
}

void quill_qt_widget_set_accessible_description_recursive(
    QuillQtWidgetHandle widget,
    const char *text
) {
    QWidget *target = asWidget(widget);
    if (target == nullptr) {
        return;
    }

    const QString description = utf8(text);
    target->setAccessibleDescription(description);

    const QList<QWidget *> children = target->findChildren<QWidget *>(
        QString(),
        Qt::FindDirectChildrenOnly
    );
    for (QWidget *child : children) {
        quill_qt_widget_set_accessible_description_recursive(
            reinterpret_cast<QuillQtWidgetHandle>(child),
            text
        );
    }
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

QuillQtWidgetHandle quill_qt_make_divider(void) {
    QuillQtDividerFrame *divider = new QuillQtDividerFrame();
    return reinterpret_cast<QuillQtWidgetHandle>(divider);
}

int quill_qt_widget_is_divider(QuillQtWidgetHandle widget) {
    return dynamic_cast<QuillQtDividerFrame *>(asWidget(widget)) != nullptr ? 1 : 0;
}

void quill_qt_divider_set_orientation(
    QuillQtWidgetHandle divider,
    int vertical
) {
    QuillQtDividerFrame *frame = dynamic_cast<QuillQtDividerFrame *>(asWidget(divider));
    if (frame == nullptr) {
        return;
    }

    frame->setOrientation(vertical != 0 ? Qt::Vertical : Qt::Horizontal);
}

QuillQtWidgetHandle quill_qt_make_progress_bar(void) {
    QProgressBar *bar = new QProgressBar();
    bar->setTextVisible(false);
    bar->setMinimumWidth(96);
    return reinterpret_cast<QuillQtWidgetHandle>(bar);
}

void quill_qt_progress_bar_set_fraction(
    QuillQtWidgetHandle progress_bar,
    double fraction
) {
    QProgressBar *bar = qobject_cast<QProgressBar *>(asWidget(progress_bar));
    if (bar == nullptr) {
        return;
    }

    const double finiteFraction = std::isfinite(fraction) ? fraction : 0.0;
    const double clamped = std::max(0.0, std::min(1.0, finiteFraction));
    bar->setRange(0, 1000);
    bar->setValue(static_cast<int>(std::round(clamped * 1000.0)));
}

void quill_qt_progress_bar_set_indeterminate(QuillQtWidgetHandle progress_bar) {
    QProgressBar *bar = qobject_cast<QProgressBar *>(asWidget(progress_bar));
    if (bar == nullptr) {
        return;
    }

    bar->setRange(0, 0);
    bar->setValue(0);
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

void quill_qt_button_set_child(
    QuillQtWidgetHandle button_handle,
    QuillQtWidgetHandle child
) {
    QPushButton *button = qobject_cast<QPushButton *>(asWidget(button_handle));
    QWidget *childWidget = asWidget(child);
    if (button == nullptr || childWidget == nullptr) {
        return;
    }

    QHBoxLayout *layout = qobject_cast<QHBoxLayout *>(button->layout());
    if (layout == nullptr) {
        layout = new QHBoxLayout(button);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(0);
        button->setLayout(layout);
    } else {
        while (QLayoutItem *item = layout->takeAt(0)) {
            if (QWidget *oldChild = item->widget()) {
                oldChild->hide();
                oldChild->setParent(nullptr);
                oldChild->deleteLater();
            }
            delete item;
        }
    }

    childWidget->setParent(button);
    layout->addWidget(childWidget);
    const QSize childSize = resolvedWidgetSize(childWidget);
    button->setMinimumSize(childSize);
    button->setSizePolicy(QSizePolicy::Minimum, QSizePolicy::Minimum);
    childWidget->show();
}

void quill_qt_button_connect_pressed_changed(
    QuillQtWidgetHandle button_handle,
    quill_qt_bridge_toggle_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QPushButton *button = qobject_cast<QPushButton *>(asWidget(button_handle));
    if (button == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(button, &QPushButton::pressed, button, [callback, user_data]() {
            callback(1, user_data);
        });
        QObject::connect(button, &QPushButton::released, button, [callback, user_data]() {
            callback(0, user_data);
        });
    }

    if (destroy != nullptr) {
        QObject::connect(button, &QObject::destroyed, button, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

QuillQtWidgetHandle quill_qt_make_check_box(void) {
    QCheckBox *checkBox = new QCheckBox();
    return reinterpret_cast<QuillQtWidgetHandle>(checkBox);
}

void quill_qt_check_box_set_text(
    QuillQtWidgetHandle check_box,
    const char *text
) {
    QCheckBox *checkBox = qobject_cast<QCheckBox *>(asWidget(check_box));
    if (checkBox == nullptr) {
        return;
    }
    checkBox->setText(utf8(text));
}

void quill_qt_check_box_set_checked(
    QuillQtWidgetHandle check_box,
    int checked
) {
    QCheckBox *checkBox = qobject_cast<QCheckBox *>(asWidget(check_box));
    if (checkBox == nullptr) {
        return;
    }
    checkBox->setChecked(checked != 0);
}

void quill_qt_check_box_connect_toggled(
    QuillQtWidgetHandle check_box,
    quill_qt_bridge_toggle_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QCheckBox *checkBox = qobject_cast<QCheckBox *>(asWidget(check_box));
    if (checkBox == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(
            checkBox,
            &QAbstractButton::toggled,
            checkBox,
            [callback, user_data](bool checked) {
                callback(checked ? 1 : 0, user_data);
            }
        );
    }

    if (destroy != nullptr) {
        QObject::connect(checkBox, &QObject::destroyed, checkBox, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

QuillQtWidgetHandle quill_qt_make_line_edit(void) {
    QLineEdit *lineEdit = new QLineEdit();
    return reinterpret_cast<QuillQtWidgetHandle>(lineEdit);
}

void quill_qt_line_edit_set_placeholder_text(
    QuillQtWidgetHandle line_edit,
    const char *text
) {
    QLineEdit *lineEdit = qobject_cast<QLineEdit *>(asWidget(line_edit));
    if (lineEdit == nullptr) {
        return;
    }
    lineEdit->setPlaceholderText(utf8(text));
}

void quill_qt_line_edit_set_text(
    QuillQtWidgetHandle line_edit,
    const char *text
) {
    QLineEdit *lineEdit = qobject_cast<QLineEdit *>(asWidget(line_edit));
    if (lineEdit == nullptr) {
        return;
    }

    const QString updatedText = utf8(text);
    if (lineEdit->text() != updatedText) {
        lineEdit->setText(updatedText);
    }
}

void quill_qt_line_edit_connect_text_changed(
    QuillQtWidgetHandle line_edit,
    quill_qt_bridge_text_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QLineEdit *lineEdit = qobject_cast<QLineEdit *>(asWidget(line_edit));
    if (lineEdit == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(
            lineEdit,
            &QLineEdit::textChanged,
            lineEdit,
            [callback, user_data](const QString &text) {
                const QByteArray utf8Text = text.toUtf8();
                callback(utf8Text.constData(), user_data);
            }
        );
    }

    if (destroy != nullptr) {
        QObject::connect(lineEdit, &QObject::destroyed, lineEdit, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

void quill_qt_line_edit_connect_return_pressed(
    QuillQtWidgetHandle line_edit,
    quill_qt_bridge_click_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QLineEdit *lineEdit = qobject_cast<QLineEdit *>(asWidget(line_edit));
    if (lineEdit == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(lineEdit, &QLineEdit::returnPressed, lineEdit, [callback, user_data]() {
            callback(user_data);
        });
    }

    if (destroy != nullptr) {
        QObject::connect(lineEdit, &QObject::destroyed, lineEdit, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

QuillQtWidgetHandle quill_qt_make_combo_box(void) {
    QComboBox *comboBox = new QComboBox();
    return reinterpret_cast<QuillQtWidgetHandle>(comboBox);
}

void quill_qt_combo_box_add_item(
    QuillQtWidgetHandle combo_box,
    const char *text
) {
    QComboBox *comboBox = qobject_cast<QComboBox *>(asWidget(combo_box));
    if (comboBox == nullptr) {
        return;
    }
    comboBox->addItem(utf8(text));
}

void quill_qt_combo_box_set_current_index(
    QuillQtWidgetHandle combo_box,
    int index
) {
    QComboBox *comboBox = qobject_cast<QComboBox *>(asWidget(combo_box));
    if (comboBox == nullptr) {
        return;
    }
    comboBox->setCurrentIndex(index);
}

void quill_qt_combo_box_connect_current_index_changed(
    QuillQtWidgetHandle combo_box,
    quill_qt_bridge_index_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QComboBox *comboBox = qobject_cast<QComboBox *>(asWidget(combo_box));
    if (comboBox == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(
            comboBox,
            &QComboBox::currentIndexChanged,
            comboBox,
            [callback, user_data](int index) {
                callback(index, user_data);
            }
        );
    }

    if (destroy != nullptr) {
        QObject::connect(comboBox, &QObject::destroyed, comboBox, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

static QButtonGroup *segmentedPickerGroup(QWidget *container) {
    if (container == nullptr) {
        return nullptr;
    }
    return container->findChild<QButtonGroup *>("quill-segmented-picker-group");
}

QuillQtWidgetHandle quill_qt_make_segmented_picker(void) {
    QWidget *container = new QWidget();
    QHBoxLayout *layout = new QHBoxLayout(container);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    QButtonGroup *group = new QButtonGroup(container);
    group->setObjectName("quill-segmented-picker-group");
    group->setExclusive(true);

    container->setStyleSheet(
        "QPushButton {"
        "  background: rgba(255, 255, 255, 0.68);"
        "  border: 1px solid rgba(0, 0, 0, 0.20);"
        "  border-radius: 6px;"
        "  padding: 3px 10px;"
        "  min-height: 24px;"
        "}"
        "QPushButton + QPushButton { margin-left: -1px; }"
        "QPushButton:checked {"
        "  background: rgba(53, 132, 228, 0.18);"
        "  border-color: rgba(53, 132, 228, 0.52);"
        "  color: #1c71d8;"
        "}"
        "QPushButton:disabled {"
        "  color: rgba(0, 0, 0, 0.38);"
        "  background: rgba(255, 255, 255, 0.38);"
        "}"
    );

    return reinterpret_cast<QuillQtWidgetHandle>(container);
}

void quill_qt_segmented_picker_add_item(
    QuillQtWidgetHandle segmented_picker,
    const char *text,
    int index,
    int selected
) {
    QWidget *container = asWidget(segmented_picker);
    QHBoxLayout *layout = container != nullptr ? qobject_cast<QHBoxLayout *>(container->layout()) : nullptr;
    QButtonGroup *group = segmentedPickerGroup(container);
    if (layout == nullptr || group == nullptr) {
        return;
    }

    QPushButton *button = new QPushButton(utf8(text), container);
    button->setCheckable(true);
    button->setChecked(selected != 0);
    button->setSizePolicy(QSizePolicy::Minimum, QSizePolicy::Fixed);
    group->addButton(button, index);
    layout->addWidget(button);
}

void quill_qt_segmented_picker_connect_selected(
    QuillQtWidgetHandle segmented_picker,
    quill_qt_bridge_index_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QWidget *container = asWidget(segmented_picker);
    QButtonGroup *group = segmentedPickerGroup(container);
    if (container == nullptr || group == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(
            group,
            &QButtonGroup::idClicked,
            container,
            [callback, user_data](int index) {
                callback(index, user_data);
            }
        );
    }

    if (destroy != nullptr) {
        QObject::connect(container, &QObject::destroyed, container, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

QuillQtWidgetHandle quill_qt_make_menu_button(void) {
    QToolButton *button = new QToolButton();
    QMenu *menu = new QMenu(button);
    button->setMenu(menu);
    button->setPopupMode(QToolButton::InstantPopup);
    button->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    return reinterpret_cast<QuillQtWidgetHandle>(button);
}

void quill_qt_menu_button_set_text(
    QuillQtWidgetHandle menu_button,
    const char *text
) {
    QToolButton *button = qobject_cast<QToolButton *>(asWidget(menu_button));
    if (button == nullptr) {
        return;
    }
    button->setText(utf8(text));
}

void quill_qt_menu_button_add_action(
    QuillQtWidgetHandle menu_button,
    const char *text,
    quill_qt_bridge_click_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
) {
    QToolButton *button = qobject_cast<QToolButton *>(asWidget(menu_button));
    if (button == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    QMenu *menu = button->menu();
    if (menu == nullptr) {
        menu = new QMenu(button);
        button->setMenu(menu);
    }

    QAction *action = menu->addAction(utf8(text));
    if (action == nullptr) {
        if (destroy != nullptr && user_data != nullptr) {
            destroy(user_data);
        }
        return;
    }

    if (callback != nullptr) {
        QObject::connect(action, &QAction::triggered, action, [callback, user_data]() {
            callback(user_data);
        });
    }

    if (destroy != nullptr) {
        QObject::connect(action, &QObject::destroyed, action, [destroy, user_data]() {
            destroy(user_data);
        });
    }
}

void quill_qt_menu_button_add_separator(QuillQtWidgetHandle menu_button) {
    QToolButton *button = qobject_cast<QToolButton *>(asWidget(menu_button));
    if (button == nullptr) {
        return;
    }

    QMenu *menu = button->menu();
    if (menu == nullptr) {
        menu = new QMenu(button);
        button->setMenu(menu);
    }
    menu->addSeparator();
}

void quill_qt_menu_button_show_as_popup(QuillQtWidgetHandle menu_button) {
    QToolButton *button = qobject_cast<QToolButton *>(asWidget(menu_button));
    if (button == nullptr) {
        return;
    }
    button->setPopupMode(QToolButton::InstantPopup);
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

QuillQtWidgetHandle quill_qt_make_scroll_area(void) {
    QScrollArea *scroll = new QScrollArea();
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    scroll->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    return reinterpret_cast<QuillQtWidgetHandle>(scroll);
}

void quill_qt_scroll_area_set_widget(
    QuillQtWidgetHandle scroll_area,
    QuillQtWidgetHandle child
) {
    QScrollArea *scroll = qobject_cast<QScrollArea *>(asWidget(scroll_area));
    QWidget *childWidget = asWidget(child);
    if (scroll == nullptr || childWidget == nullptr) {
        return;
    }
    scroll->setWidget(childWidget);
    childWidget->show();
}

void quill_qt_scroll_area_set_axis(
    QuillQtWidgetHandle scroll_area,
    int horizontal,
    int vertical
) {
    QScrollArea *scroll = qobject_cast<QScrollArea *>(asWidget(scroll_area));
    if (scroll == nullptr) {
        return;
    }

    scroll->setHorizontalScrollBarPolicy(
        horizontal != 0 ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff
    );
    scroll->setVerticalScrollBarPolicy(
        vertical != 0 ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff
    );
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
