#ifndef QUILL_OBJC_FOUNDATION_H
#define QUILL_OBJC_FOUNDATION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <limits.h>
#include <time.h>

#ifndef __has_feature
#define __has_feature(x) 0
#endif

#ifndef nil
#define nil ((id)0)
#endif

#ifndef Nil
#define Nil ((Class)0)
#endif

#ifndef YES
#define YES ((BOOL)1)
#endif

#ifndef NO
#define NO ((BOOL)0)
#endif

#ifndef NULL
#define NULL ((void *)0)
#endif

#ifndef _Nullable
#define _Nullable
#endif

#ifndef _Nonnull
#define _Nonnull
#endif

#ifndef __nullable
#define __nullable
#endif

#ifndef __nonnull
#define __nonnull
#endif

#ifndef __unused
#define __unused __attribute__((unused))
#endif

typedef signed char BOOL;
typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;

typedef struct _NSRange {
    NSUInteger location;
    NSUInteger length;
} NSRange;

#ifndef NSUIntegerMax
#define NSUIntegerMax ULONG_MAX
#endif

static const NSUInteger NSNotFound = NSUIntegerMax;

static inline NSRange NSMakeRange(NSUInteger location, NSUInteger length) {
    NSRange range = { location, length };
    return range;
}

#ifndef NS_ASSUME_NONNULL_BEGIN
#define NS_ASSUME_NONNULL_BEGIN
#endif

#ifndef NS_ASSUME_NONNULL_END
#define NS_ASSUME_NONNULL_END
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(_name)
#endif

#ifndef NS_REFINED_FOR_SWIFT
#define NS_REFINED_FOR_SWIFT
#endif

#ifndef NS_DESIGNATED_INITIALIZER
#define NS_DESIGNATED_INITIALIZER
#endif

#ifndef NS_UNAVAILABLE
#define NS_UNAVAILABLE __attribute__((unavailable))
#endif

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#ifndef NS_OPTIONS
#define NS_OPTIONS(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#if defined(__OBJC__)
@class NSString;
@class NSNumber;
@class NSArray;
@class NSMutableArray;
@class NSDictionary;
@class NSMutableDictionary;
@class NSData;
@class NSMutableData;
@class NSDate;
@class NSDateFormatter;
@class NSLocale;
@class NSTimeZone;
@class NSBundle;
@class NSError;
@class NSValue;
@class NSNumberFormatter;

__attribute__((objc_root_class))
@interface NSObject
+ (instancetype)alloc;
- (instancetype)init;
@end

@interface NSString : NSObject
@property (nonatomic, readonly) const char *UTF8String;
@property (nonatomic, readonly) NSUInteger length;
+ (instancetype)stringWithFormat:(NSString *)format, ...;
- (instancetype)initWithFormat:(NSString *)format, ...;
- (BOOL)hasSuffix:(NSString *)str;
- (BOOL)hasPrefix:(NSString *)str;
- (NSRange)rangeOfString:(NSString *)str;
- (NSString *)substringToIndex:(NSUInteger)to;
- (NSString *)lowercaseString;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
- (BOOL)isEqualToString:(NSString *)string;
@end

@interface NSMutableString : NSString
- (void)appendString:(NSString *)string;
- (void)appendFormat:(NSString *)format, ...;
@end

@interface NSNumber : NSObject
+ (NSNumber *)numberWithBool:(BOOL)value;
+ (NSNumber *)numberWithChar:(char)value;
+ (NSNumber *)numberWithDouble:(double)value;
+ (NSNumber *)numberWithFloat:(float)value;
+ (NSNumber *)numberWithInt:(int)value;
+ (NSNumber *)numberWithInteger:(NSInteger)value;
+ (NSNumber *)numberWithLong:(long)value;
+ (NSNumber *)numberWithLongLong:(long long)value;
+ (NSNumber *)numberWithUnsignedInt:(unsigned int)value;
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)value;
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)value;
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)value;
- (BOOL)boolValue;
- (int)intValue;
@end

@interface NSArray<ObjectType> : NSObject
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
@end

@interface NSDictionary<KeyType, ObjectType> : NSObject
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;
@end

@interface NSMutableDictionary<KeyType, ObjectType> : NSDictionary<KeyType, ObjectType>
- (void)setObject:(ObjectType)obj forKeyedSubscript:(KeyType)key;
@end

@interface NSData : NSObject
+ (instancetype)dataWithContentsOfFile:(NSString *)path;
@property (nonatomic, readonly) const void *bytes;
@property (nonatomic, readonly) NSUInteger length;
@end

@interface NSMutableData : NSData
@end

@interface NSDate : NSObject
+ (instancetype)date;
@end

typedef NS_ENUM(NSInteger, NSDateFormatterStyle) {
    NSDateFormatterNoStyle = 0,
    NSDateFormatterShortStyle = 1,
    NSDateFormatterMediumStyle = 2,
    NSDateFormatterLongStyle = 3,
    NSDateFormatterFullStyle = 4
};

@interface NSDateFormatter : NSObject
- (void)setLocale:(NSLocale *)locale;
- (void)setDateStyle:(NSDateFormatterStyle)style;
- (void)setTimeStyle:(NSDateFormatterStyle)style;
- (void)setTimeZone:(NSTimeZone *)timeZone;
- (NSString *)stringFromDate:(NSDate *)date;
- (NSString *)AMSymbol;
- (NSString *)PMSymbol;
+ (NSString *)dateFormatFromTemplate:(NSString *)templateName options:(NSUInteger)opts locale:(NSLocale *)locale;
@end

@interface NSLocale : NSObject
+ (instancetype)currentLocale;
@end

@interface NSTimeZone : NSObject
+ (instancetype)localTimeZone;
@end

@interface NSBundle : NSObject
+ (instancetype)mainBundle;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
@end

typedef NS_OPTIONS(NSUInteger, NSJSONReadingOptions) {
    NSJSONReadingMutableContainers = 1UL << 0,
    NSJSONReadingMutableLeaves = 1UL << 1,
    NSJSONReadingFragmentsAllowed = 1UL << 2
};

@interface NSJSONSerialization : NSObject
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error;
@end

typedef NS_ENUM(NSUInteger, NSNumberFormatterStyle) {
    NSNumberFormatterNoStyle = 0,
    NSNumberFormatterDecimalStyle = 1,
    NSNumberFormatterCurrencyStyle = 2
};

@interface NSNumberFormatter : NSObject
- (void)setNumberStyle:(NSNumberFormatterStyle)style;
- (void)setCurrencyCode:(NSString *)currencyCode;
- (void)setNegativeFormat:(NSString *)format;
- (NSString *)stringFromNumber:(NSNumber *)number;
@end

NSString *NSLocalizedString(NSString *key, NSString *comment);

typedef long dispatch_once_t;
static inline void dispatch_once(dispatch_once_t *predicate, void (^block)(void)) {
    if (predicate != NULL && *predicate == 0) {
        *predicate = 1;
        block();
    }
}

#ifndef NSAssert
#define NSAssert(condition, desc, ...) ((void)0)
#endif

#endif

#ifndef ABS
#define ABS(x) (((x) < 0) ? -(x) : (x))
#endif

#endif
