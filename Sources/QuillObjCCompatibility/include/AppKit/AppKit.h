#ifndef QUILL_OBJC_APPKIT_H
#define QUILL_OBJC_APPKIT_H

#include <Foundation/Foundation.h>
#include <IOKit/hidsystem/IOHIDLib.h>

typedef struct CGPoint {
    CGFloat x;
    CGFloat y;
} CGPoint;

typedef struct CGSize {
    CGFloat width;
    CGFloat height;
} CGSize;

typedef struct CGRect {
    CGPoint origin;
    CGSize size;
} CGRect;

typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;

typedef struct CGAffineTransform {
    CGFloat a;
    CGFloat b;
    CGFloat c;
    CGFloat d;
    CGFloat tx;
    CGFloat ty;
} CGAffineTransform;

static const CGAffineTransform CGAffineTransformIdentity = { 1, 0, 0, 1, 0, 0 };

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) {
    CGPoint point = { x, y };
    return point;
}

static inline CGSize CGSizeMake(CGFloat width, CGFloat height) {
    CGSize size = { width, height };
    return size;
}

static const CGSize CGSizeZero = { 0, 0 };

static inline BOOL CGSizeEqualToSize(CGSize lhs, CGSize rhs) {
    return lhs.width == rhs.width && lhs.height == rhs.height;
}

static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    CGRect rect = { CGPointMake(x, y), CGSizeMake(width, height) };
    return rect;
}

static inline NSPoint NSMakePoint(CGFloat x, CGFloat y) {
    return CGPointMake(x, y);
}

static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    return CGRectMake(x, y, width, height);
}

static const NSSize NSZeroSize = { 0, 0 };
static const NSRect NSZeroRect = { { 0, 0 }, { 0, 0 } };
static const CGRect CGRectZero = { { 0, 0 }, { 0, 0 } };

#ifndef NSWidth
#define NSWidth(rect) ((rect).size.width)
#endif
#ifndef NSHeight
#define NSHeight(rect) ((rect).size.height)
#endif
#ifndef NSMinX
#define NSMinX(rect) ((rect).origin.x)
#endif
#ifndef NSMinY
#define NSMinY(rect) ((rect).origin.y)
#endif

static inline NSRect NSOffsetRect(NSRect rect, CGFloat dx, CGFloat dy) {
    rect.origin.x += dx;
    rect.origin.y += dy;
    return rect;
}

static inline BOOL NSPointInRect(NSPoint point, NSRect rect) {
    return point.x >= rect.origin.x
        && point.y >= rect.origin.y
        && point.x <= rect.origin.x + rect.size.width
        && point.y <= rect.origin.y + rect.size.height;
}

typedef void *CGContextRef;
typedef const void *CGColorRef;
typedef const void *CGColorSpaceRef;
typedef const void CGImage;
typedef const void *CGImageRef;
typedef const void *CGDataProviderRef;
typedef const void *CGEventRef;
typedef int CGLineCap;
typedef int CGLineJoin;
typedef int CGInterpolationQuality;
typedef int CGScrollEventUnit;
typedef int CGEventTapLocation;
typedef uint32_t CGImageAlphaInfo;
typedef uint32_t CGBitmapInfo;
typedef uint32_t CGWheelCount;
typedef int CGColorRenderingIntent;

#ifndef CG_EXTERN
#ifdef __cplusplus
#define CG_EXTERN extern "C"
#else
#define CG_EXTERN extern
#endif
#endif

static const CGLineCap kCGLineCapButt = 0;
static const CGLineCap kCGLineCapRound = 1;
static const CGLineCap kCGLineCapSquare = 2;
static const CGLineJoin kCGLineJoinMiter = 0;
static const CGLineJoin kCGLineJoinRound = 1;
static const CGLineJoin kCGLineJoinBevel = 2;
static const CGInterpolationQuality kCGInterpolationLow = 0;
static const CGScrollEventUnit kCGScrollEventUnitLine = 0;
static const CGScrollEventUnit kCGScrollEventUnitPixel = 1;
static const CGEventTapLocation kCGHIDEventTap = 0;
static const CGBitmapInfo kCGImageAlphaPremultipliedFirst = 1U << 0;
static const CGBitmapInfo kCGImageAlphaPremultipliedLast = 1U << 1;
static const CGBitmapInfo kCGImageAlphaFirst = 1U << 2;
static const CGBitmapInfo kCGImageAlphaLast = 1U << 3;
static const CGBitmapInfo kCGImageAlphaNone = 0;
static const CGBitmapInfo kCGImageAlphaNoneSkipFirst = 1U << 4;
static const CGBitmapInfo kCGBitmapAlphaInfoMask = 0x1fU;
static const CGBitmapInfo kCGBitmapByteOrder32Host = 1U << 12;
static const CGBitmapInfo kCGBitmapByteOrder32Big = 3U << 12;
static const CGColorRenderingIntent kCGRenderingIntentDefault = 0;

static inline void CGContextTranslateCTM(CGContextRef context, CGFloat tx, CGFloat ty) { (void)context; (void)tx; (void)ty; }
static inline void CGContextScaleCTM(CGContextRef context, CGFloat sx, CGFloat sy) { (void)context; (void)sx; (void)sy; }
static inline void CGContextSetInterpolationQuality(CGContextRef context, CGInterpolationQuality quality) { (void)context; (void)quality; }
static inline void CGContextDrawImage(CGContextRef context, CGRect rect, CGImageRef image) { (void)context; (void)rect; (void)image; }
static inline void CGContextClearRect(CGContextRef context, CGRect rect) { (void)context; (void)rect; }
static inline void CGContextFillRect(CGContextRef context, CGRect rect) { (void)context; (void)rect; }
static inline void CGContextSetFillColorWithColor(CGContextRef context, CGColorRef color) { (void)context; (void)color; }
static inline void CGContextSetStrokeColorWithColor(CGContextRef context, CGColorRef color) { (void)context; (void)color; }
static inline void CGContextSetAllowsAntialiasing(CGContextRef context, bool allowsAntialiasing) { (void)context; (void)allowsAntialiasing; }
static inline void CGContextSetShouldSmoothFonts(CGContextRef context, bool shouldSmoothFonts) { (void)context; (void)shouldSmoothFonts; }
static inline void CGContextSetAllowsFontSmoothing(CGContextRef context, bool allowsFontSmoothing) { (void)context; (void)allowsFontSmoothing; }
static inline void CGContextBeginPath(CGContextRef context) { (void)context; }
static inline void CGContextMoveToPoint(CGContextRef context, CGFloat x, CGFloat y) { (void)context; (void)x; (void)y; }
static inline void CGContextAddCurveToPoint(CGContextRef context, CGFloat cp1x, CGFloat cp1y, CGFloat cp2x, CGFloat cp2y, CGFloat x, CGFloat y) {
    (void)context; (void)cp1x; (void)cp1y; (void)cp2x; (void)cp2y; (void)x; (void)y;
}
static inline void CGContextAddLineToPoint(CGContextRef context, CGFloat x, CGFloat y) { (void)context; (void)x; (void)y; }
static inline void CGContextClosePath(CGContextRef context) { (void)context; }
static inline void CGContextEOFillPath(CGContextRef context) { (void)context; }
static inline void CGContextFillPath(CGContextRef context) { (void)context; }
static inline void CGContextStrokePath(CGContextRef context) { (void)context; }
static inline void CGContextSetMiterLimit(CGContextRef context, CGFloat limit) { (void)context; (void)limit; }
static inline void CGContextSetLineWidth(CGContextRef context, CGFloat width) { (void)context; (void)width; }
static inline void CGContextSetLineCap(CGContextRef context, CGLineCap cap) { (void)context; (void)cap; }
static inline void CGContextSetLineJoin(CGContextRef context, CGLineJoin join) { (void)context; (void)join; }
static inline CGContextRef CGBitmapContextCreate(void *data, size_t width, size_t height, size_t bitsPerComponent, size_t bytesPerRow, CGColorSpaceRef space, CGBitmapInfo bitmapInfo) {
    (void)width; (void)height; (void)bitsPerComponent; (void)bytesPerRow; (void)space; (void)bitmapInfo;
    return data != NULL ? data : (void *)1;
}
static inline CGImageRef CGBitmapContextCreateImage(CGContextRef context) { (void)context; return NULL; }
static inline void CGContextRelease(CGContextRef context) { (void)context; }
static inline CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void) { return NULL; }
static inline CGColorSpaceRef CGColorSpaceCreateDeviceGray(void) { return NULL; }
static inline void CGColorSpaceRelease(CGColorSpaceRef space) { (void)space; }
static inline CGColorRef CGColorRetain(CGColorRef color) { return color; }
static inline void CGColorRelease(CGColorRef color) { (void)color; }
static inline void CGImageRelease(CGImageRef image) { (void)image; }
static inline size_t CGImageGetWidth(CGImageRef image) { (void)image; return 0; }
static inline size_t CGImageGetHeight(CGImageRef image) { (void)image; return 0; }
static inline CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef image) { (void)image; return 0; }
static inline CGColorSpaceRef CGImageGetColorSpace(CGImageRef image) { (void)image; return NULL; }
static inline size_t CGImageGetBitsPerComponent(CGImageRef image) { (void)image; return 8; }
static inline size_t CGImageGetBitsPerPixel(CGImageRef image) { (void)image; return 32; }
static inline size_t CGImageGetBytesPerRow(CGImageRef image) { (void)image; return 0; }
static inline CGBitmapInfo CGImageGetBitmapInfo(CGImageRef image) { (void)image; return 0; }
static inline CGDataProviderRef CGImageGetDataProvider(CGImageRef image) { (void)image; return NULL; }
typedef void (*CGDataProviderReleaseDataCallback)(void *info, const void *data, size_t size);
static inline CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size, CGDataProviderReleaseDataCallback releaseData) {
    (void)info; (void)data; (void)size; (void)releaseData;
    return data;
}
static inline CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data) { return (CGDataProviderRef)data; }
static inline CFDataRef CGDataProviderCopyData(CGDataProviderRef provider) { (void)provider; return NULL; }
static inline CGImageRef CGImageCreate(size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel, size_t bytesPerRow, CGColorSpaceRef space, CGBitmapInfo bitmapInfo, CGDataProviderRef provider, const CGFloat decode[], bool shouldInterpolate, CGColorRenderingIntent intent) {
    (void)width; (void)height; (void)bitsPerComponent; (void)bitsPerPixel; (void)bytesPerRow; (void)space; (void)bitmapInfo; (void)provider; (void)decode; (void)shouldInterpolate; (void)intent;
    return provider;
}
static inline CGImageRef CGImageCreateWithImageInRect(CGImageRef image, CGRect rect) {
    (void)rect;
    return image;
}
static inline CGEventRef CGEventCreateScrollWheelEvent(void *source, CGScrollEventUnit units, CGWheelCount wheelCount, int32_t wheel1, int32_t wheel2) {
    (void)source; (void)units; (void)wheelCount; (void)wheel1; (void)wheel2;
    return NULL;
}
static inline void CGEventPost(CGEventTapLocation tap, CGEventRef event) { (void)tap; (void)event; }
typedef uint32_t LSRolesMask;
static const LSRolesMask kLSRolesAll = 0xffffffffU;
static inline CFArrayRef LSCopyApplicationURLsForURL(CFURLRef inURL, LSRolesMask inRoleMask) {
    (void)inURL; (void)inRoleMask;
    return NULL;
}

#if defined(__OBJC__)
@class NSColor;
@class NSImage;
@class NSBitmapImageRep;
@class NSView;
@class NSWindow;
@class NSWorkspace;
@class NSGraphicsContext;
@class NSOpenPanel;
@class NSSavePanel;
@class NSEvent;
@class NSCursor;
@class NSScreen;
@class NSFont;
@class NSFontDescriptor;
@class NSFontManager;
@class NSParagraphStyle;
@class NSMutableParagraphStyle;
@class NSTextAttachment;
@class NSTextContainer;
@class NSLayoutManager;
@class NSTextStorage;
@class NSTextField;
@class NSTextView;
@class NSScrollView;
@class NSPasteboard;
@class NSMenu;
@class NSMenuItem;
@class NSTrackingArea;
@class NSScroller;
@class NSClipView;
@class NSTextFieldCell;
@class CALayer;

typedef NSString *NSPasteboardType;
typedef NSString *NSTouchBarItemIdentifier;

static NSAttributedStringKey const NSFontAttributeName = @"NSFont";
static NSAttributedStringKey const NSForegroundColorAttributeName = @"NSColor";
static NSAttributedStringKey const NSBackgroundColorAttributeName = @"NSBackgroundColor";
static NSAttributedStringKey const NSUnderlineStyleAttributeName = @"NSUnderline";
static NSAttributedStringKey const NSStrikethroughStyleAttributeName = @"NSStrikethrough";
static NSAttributedStringKey const NSLinkAttributeName = @"NSLink";

typedef NS_ENUM(NSInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0,
    NSLineBreakByCharWrapping = 1,
    NSLineBreakByClipping = 2,
    NSLineBreakByTruncatingHead = 3,
    NSLineBreakByTruncatingTail = 4,
    NSLineBreakByTruncatingMiddle = 5
};

typedef NS_ENUM(NSInteger, NSControlSize) {
    NSControlSizeRegular = 0,
    NSControlSizeSmall = 1,
    NSControlSizeMini = 2,
    NSControlSizeLarge = 3
};

typedef NS_OPTIONS(NSUInteger, NSUnderlineStyle) {
    NSUnderlineStyleNone = 0,
    NSUnderlineStyleSingle = 1
};

typedef NS_OPTIONS(NSUInteger, NSFontTraitMask) {
    NSItalicFontMask = 1UL << 0,
    NSBoldFontMask = 1UL << 1
};

typedef NS_OPTIONS(uint32_t, NSFontSymbolicTraits) {
    NSFontItalicTrait = 1U << 0,
    NSFontBoldTrait = 1U << 1
};

typedef NS_OPTIONS(NSUInteger, NSTrackingAreaOptions) {
    NSTrackingMouseEnteredAndExited = 1UL << 0,
    NSTrackingMouseMoved = 1UL << 1,
    NSTrackingCursorUpdate = 1UL << 2,
    NSTrackingActiveInActiveApp = 1UL << 4,
    NSTrackingActiveInKeyWindow = 1UL << 5
};

typedef NS_ENUM(NSInteger, NSScrollElasticity) {
    NSScrollElasticityAutomatic = 0,
    NSScrollElasticityNone = 1,
    NSScrollElasticityAllowed = 2
};

typedef NSString *NSColorSpaceName;
static NSColorSpaceName const NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";

typedef NSUInteger NSEventModifierFlags;

static const NSEventModifierFlags NSEventModifierFlagCapsLock = 1UL << 16;
static const NSEventModifierFlags NSEventModifierFlagShift = 1UL << 17;
static const NSEventModifierFlags NSEventModifierFlagControl = 1UL << 18;
static const NSEventModifierFlags NSEventModifierFlagOption = 1UL << 19;
static const NSEventModifierFlags NSEventModifierFlagCommand = 1UL << 20;
static const NSEventModifierFlags NSAlphaShiftKeyMask = 1UL << 16;
static const NSEventModifierFlags NSShiftKeyMask = 1UL << 17;
static const NSEventModifierFlags NSControlKeyMask = 1UL << 18;
static const NSEventModifierFlags NSAlternateKeyMask = 1UL << 19;
static const NSEventModifierFlags NSCommandKeyMask = 1UL << 20;
static const NSEventModifierFlags NSDeviceIndependentModifierFlagsMask = 0xffff0000UL;

static inline NSSize NSMakeSize(CGFloat width, CGFloat height) {
    return CGSizeMake(width, height);
}

@interface NSColor : NSObject
+ (instancetype)clearColor;
+ (instancetype)blackColor;
+ (instancetype)whiteColor;
+ (instancetype)redColor;
+ (instancetype)colorWithDeviceRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;
@property (nonatomic, readonly) CGColorRef CGColor;
@end

@interface NSImage : NSObject
+ (instancetype)imageNamed:(NSString *)name;
+ (NSArray<NSString *> *)imageTypes;
- (instancetype)initWithSize:(NSSize)size;
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithCGImage:(CGImageRef)image size:(NSSize)size;
- (BOOL)isValid;
- (void)setSize:(NSSize)size;
- (void)addRepresentation:(NSBitmapImageRep *)imageRep;
- (NSData *)TIFFRepresentation;
- (void)lockFocus;
- (void)unlockFocus;
@end

@interface NSBitmapImageRep : NSObject
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes
                              pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height
                           bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp
                                hasAlpha:(BOOL)alpha
                                isPlanar:(BOOL)isPlanar
                          colorSpaceName:(NSColorSpaceName)colorSpaceName
                             bytesPerRow:(NSInteger)rowBytes
                            bitsPerPixel:(NSInteger)pixelBits;
@end

@interface NSGraphicsContext : NSObject
+ (instancetype)currentContext;
- (CGContextRef)graphicsPort;
@end

@interface NSScreen : NSObject
+ (instancetype)mainScreen;
@property (nonatomic, readonly) CGFloat backingScaleFactor;
@end

@protocol NSServicesMenuRequestor
@optional
- (id)validRequestorForSendType:(NSPasteboardType)sendType returnType:(NSPasteboardType)returnType;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard;
@end

@protocol NSTextViewDelegate <NSObject>
@optional
- (void)textDidChange:(NSNotification *)notification;
- (void)textViewDidChangeSelection:(NSNotification *)notification;
@end

@protocol NSLayoutManagerDelegate <NSObject>
@optional
@end

@interface NSView : NSObject
@property (nonatomic) NSRect frame;
@property (nonatomic) NSRect bounds;
@property (nonatomic) BOOL autoresizesSubviews;
@property (nonatomic) BOOL wantsLayer;
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic) BOOL needsDisplay;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) NSView *superview;
@property (nonatomic, readonly) NSScrollView *enclosingScrollView;
@property (nonatomic, readonly) NSArray<NSView *> *subviews;
@property (nonatomic, readonly) NSString *className;
- (instancetype)initWithFrame:(NSRect)frameRect;
- (void)addSubview:(NSView *)view;
- (void)addTrackingArea:(NSTrackingArea *)trackingArea;
- (void)removeTrackingArea:(NSTrackingArea *)trackingArea;
- (void)updateTrackingAreas;
- (void)setFrameSize:(NSSize)newSize;
- (void)setFrameOrigin:(NSPoint)newOrigin;
- (void)removeFromSuperview;
- (void)drawRect:(NSRect)dirtyRect;
- (void)mouseDown:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;
- (void)rightMouseDown:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface NSWindow : NSObject
@property (nonatomic, readonly) CGFloat backingScaleFactor;
@property (nonatomic, readonly) id firstResponder;
- (BOOL)makeFirstResponder:(id)responder;
- (BOOL)inLiveResize;
@end

@interface NSFontDescriptor : NSObject
@property (nonatomic, readonly) NSFontSymbolicTraits symbolicTraits;
@end

@interface NSFont : NSObject
+ (NSFont *)systemFontOfSize:(CGFloat)fontSize;
+ (NSFont *)boldSystemFontOfSize:(CGFloat)fontSize;
+ (NSFont *)fontWithName:(NSString *)fontName size:(CGFloat)fontSize;
@property (nonatomic, readonly) CGFloat pointSize;
@property (nonatomic, readonly) NSString *fontName;
@property (nonatomic, readonly) NSFontDescriptor *fontDescriptor;
@end

@interface NSFontManager : NSObject
+ (NSFontManager *)sharedFontManager;
- (NSFont *)convertFont:(NSFont *)font toSize:(CGFloat)size;
- (NSFont *)convertFont:(NSFont *)font toHaveTrait:(NSFontTraitMask)trait;
- (NSFont *)convertFont:(NSFont *)font toNotHaveTrait:(NSFontTraitMask)trait;
@end

@interface NSParagraphStyle : NSObject <NSCopying>
@end

@interface NSMutableParagraphStyle : NSParagraphStyle
@property (nonatomic) NSLineBreakMode lineBreakMode;
@property (nonatomic) CGFloat lineSpacing;
@property (nonatomic) CGFloat maximumLineHeight;
- (void)setLineSpacing:(CGFloat)lineSpacing;
- (void)setMaximumLineHeight:(CGFloat)maximumLineHeight;
@end

@interface NSTextAttachment : NSObject
@property (nonatomic) NSRect bounds;
@property (nonatomic, strong) NSImage *image;
- (instancetype)initWithData:(NSData *)contentData ofType:(NSString *)uti;
- (NSRect)attachmentBoundsForTextContainer:(NSTextContainer *)textContainer
                      proposedLineFragment:(NSRect)lineFrag
                             glyphPosition:(NSPoint)position
                            characterIndex:(NSUInteger)charIndex;
@end

@interface NSTextContainer : NSObject
@property (nonatomic) NSSize containerSize;
@property (nonatomic) CGFloat lineFragmentPadding;
@end

@interface NSLayoutManager : NSObject
@property (nonatomic, weak) id<NSLayoutManagerDelegate> delegate;
- (NSRect)usedRectForTextContainer:(NSTextContainer *)container;
- (void)ensureLayoutForTextContainer:(NSTextContainer *)container;
- (NSRange)glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange;
- (NSRect)boundingRectForGlyphRange:(NSRange)glyphRange inTextContainer:(NSTextContainer *)container;
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin;
@end

@interface NSTextStorage : NSMutableAttributedString
@end

@interface NSTextField : NSView
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, strong) NSAttributedString *attributedStringValue;
@property (nonatomic, strong) NSAttributedString *placeholderAttributedString;
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic) BOOL editable;
@property (nonatomic) BOOL selectable;
@property (nonatomic) BOOL bordered;
@property (nonatomic) BOOL bezeled;
@property (nonatomic) BOOL drawsBackground;
@property (nonatomic) NSInteger maximumNumberOfLines;
@property (nonatomic) NSLineBreakMode lineBreakMode;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL continuous;
- (NSTextFieldCell *)cell;
@end

@interface NSTextFieldCell : NSObject
- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode;
- (void)setTruncatesLastVisibleLine:(BOOL)flag;
@end

@interface NSTextView : NSView <NSServicesMenuRequestor>
@property (nonatomic, strong) NSTextStorage *textStorage;
@property (nonatomic, strong) NSLayoutManager *layoutManager;
@property (nonatomic, strong) NSTextContainer *textContainer;
@property (nonatomic, copy) NSString *string;
@property (nonatomic, readonly) NSAttributedString *attributedString;
@property (nonatomic) NSRange selectedRange;
@property (nonatomic, strong) NSColor *selectedTextColor;
@property (nonatomic, strong) NSColor *insertionPointColor;
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic) BOOL editable;
@property (nonatomic) BOOL selectable;
@property (nonatomic) BOOL richText;
@property (nonatomic) BOOL importsGraphics;
@property (nonatomic) BOOL drawsBackground;
@property (nonatomic) BOOL allowsUndo;
@property (nonatomic) BOOL continuousSpellCheckingEnabled;
@property (nonatomic) BOOL grammarCheckingEnabled;
@property (nonatomic) BOOL automaticSpellingCorrectionEnabled;
@property (nonatomic) BOOL automaticQuoteSubstitutionEnabled;
@property (nonatomic) BOOL automaticLinkDetectionEnabled;
@property (nonatomic) BOOL automaticDataDetectionEnabled;
@property (nonatomic) BOOL automaticDashSubstitutionEnabled;
@property (nonatomic, readonly) BOOL hasMarkedText;
@property (nonatomic, copy) NSDictionary<NSAttributedStringKey, id> *selectedTextAttributes;
@property (nonatomic, strong) NSUndoManager *undoManager;
@property (nonatomic, weak) id<NSTextViewDelegate> delegate;
@property (nonatomic, readonly) NSPoint textContainerOrigin;
- (void)setSelectedRange:(NSRange)range;
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (void)copy:(id)sender;
- (void)paste:(id)sender;
- (void)insertNewline:(id)sender;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
@end

static NSNotificationName const NSTextDidChangeNotification = @"NSTextDidChangeNotification";
static NSNotificationName const NSTextViewDidChangeSelectionNotification = @"NSTextViewDidChangeSelectionNotification";

@interface NSScrollView : NSView
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSClipView *contentView;
@property (nonatomic, readonly) NSScroller *verticalScroller;
@property (nonatomic, readonly) NSRect documentVisibleRect;
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic) BOOL drawsBackground;
@property (nonatomic) BOOL hasVerticalScroller;
@property (nonatomic) BOOL hasHorizontalScroller;
@property (nonatomic) NSScrollElasticity verticalScrollElasticity;
@property (nonatomic) NSScrollElasticity horizontalScrollElasticity;
@end

@interface NSScroller : NSView
@property (nonatomic) NSControlSize controlSize;
- (void)setControlSize:(NSControlSize)controlSize;
@end

@interface NSClipView : NSView
@property (nonatomic) NSRect documentRect;
@property (nonatomic) NSRect documentVisibleRect;
- (void)scrollToPoint:(NSPoint)newOrigin;
@end

@interface NSPasteboard : NSObject
+ (NSPasteboard *)generalPasteboard;
- (BOOL)canReadItemWithDataConformingToTypes:(NSArray<NSString *> *)types;
@end

@interface NSMenu : NSObject
@property (nonatomic, readonly) NSArray<NSMenuItem *> *itemArray;
- (void)addItem:(NSMenuItem *)item;
- (void)insertItem:(NSMenuItem *)item atIndex:(NSInteger)index;
- (void)removeItem:(NSMenuItem *)item;
@end

@interface NSMenuItem : NSObject
+ (NSMenuItem *)separatorItem;
- (instancetype)initWithTitle:(NSString *)title action:(SEL)selector keyEquivalent:(NSString *)charCode;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) SEL action;
@property (nonatomic, strong) NSMenu *submenu;
@property (nonatomic) NSEventModifierFlags keyEquivalentModifierMask;
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)mask;
@end

@interface NSTrackingArea : NSObject
- (instancetype)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options owner:(id)owner userInfo:(NSDictionary *)userInfo;
@end

@interface NSValue (AppKitGeometry)
+ (instancetype)valueWithPoint:(NSPoint)point;
+ (instancetype)valueWithRect:(NSRect)rect;
- (NSRect)rectValue;
- (CGRect)CGRectValue;
@end

@interface NSAttributedString (AppKitDrawing)
- (NSSize)size;
@end

@interface NSWorkspace : NSObject
+ (instancetype)sharedWorkspace;
- (BOOL)openURL:(NSURL *)url;
- (NSImage *)iconForFile:(NSString *)path;
@end

@interface NSOpenPanel : NSObject
+ (instancetype)openPanel;
@end

@interface NSSavePanel : NSObject
+ (instancetype)savePanel;
@end

@interface NSEvent : NSObject
+ (instancetype)eventWithCGEvent:(CGEventRef)event;
@property (nonatomic, readonly) CGFloat deltaX;
@property (nonatomic, readonly) CGFloat deltaY;
@property (nonatomic, readonly) NSUInteger keyCode;
@property (nonatomic, readonly) NSEventModifierFlags modifierFlags;
@end

@interface NSCursor : NSObject
@end
#endif

#endif
