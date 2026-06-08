#ifndef QUILL_OBJC_FOUNDATION_H
#define QUILL_OBJC_FOUNDATION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <limits.h>
#include <math.h>
#include <time.h>
#include <unistd.h>

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

#ifdef __nullable
#undef __nullable
#endif

#ifdef __nonnull
#undef __nonnull
#endif

#ifndef _Nullable
#define _Nullable
#endif

#ifndef _Nonnull
#define _Nonnull
#endif

#define __nullable
#define __nonnull

#ifndef __unused
#define __unused __attribute__((unused))
#endif

typedef signed char BOOL;
typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;
typedef double NSTimeInterval;
typedef unsigned short unichar;

#ifndef QUILL_OBJC_UINT8_TYPEDEF
#define QUILL_OBJC_UINT8_TYPEDEF
typedef uint8_t UInt8;
#endif

#ifndef QUILL_OBJC_UINT16_TYPEDEF
#define QUILL_OBJC_UINT16_TYPEDEF
typedef uint16_t UInt16;
#endif

#ifndef QUILL_OBJC_UINT32_TYPEDEF
#define QUILL_OBJC_UINT32_TYPEDEF
typedef uint32_t UInt32;
#endif

#ifndef QUILL_OBJC_UINT64_TYPEDEF
#define QUILL_OBJC_UINT64_TYPEDEF
typedef uint64_t UInt64;
#endif

#include <CoreFoundation/CoreFoundation.h>

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
#define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#endif

#ifndef NS_ASSUME_NONNULL_END
#define NS_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
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

#ifndef MIN
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif

#ifndef MAX
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
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
@class NSCharacterSet;

typedef struct {
    unsigned long state;
    __unsafe_unretained id *itemsPtr;
    unsigned long *mutationsPtr;
    unsigned long extra[5];
} NSFastEnumerationState;

@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id [])buffer count:(NSUInteger)len;
@end

__attribute__((objc_root_class))
@interface NSObject
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
- (instancetype)init;
- (Class)class;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (void)doesNotRecognizeSelector:(SEL)aSelector;
@property (nonatomic, readonly) NSString *description;
@end

typedef NS_OPTIONS(NSUInteger, NSStringEnumerationOptions) {
    NSStringEnumerationByComposedCharacterSequences = 1UL << 1
};

@interface NSString : NSObject
@property (nonatomic, readonly) const char *UTF8String;
@property (nonatomic, readonly) NSUInteger length;
+ (instancetype)stringWithFormat:(NSString *)format, ...;
- (instancetype)initWithFormat:(NSString *)format, ...;
- (BOOL)hasSuffix:(NSString *)str;
- (BOOL)hasPrefix:(NSString *)str;
- (NSRange)rangeOfString:(NSString *)str;
- (NSString *)substringToIndex:(NSUInteger)to;
- (NSString *)substringWithRange:(NSRange)range;
- (NSString *)lowercaseString;
- (NSArray *)componentsSeparatedByString:(NSString *)separator;
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSString *)stringByAppendingString:(NSString *)string;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
- (NSInteger)integerValue;
- (unichar)characterAtIndex:(NSUInteger)index;
- (BOOL)isEqualToString:(NSString *)string;
- (void)enumerateSubstringsInRange:(NSRange)range
                           options:(NSStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop))block;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)capacity;
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

@interface NSArray<ObjectType> : NSObject <NSFastEnumeration>
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) ObjectType firstObject;
@property (nonatomic, readonly) ObjectType lastObject;
+ (instancetype)array;
+ (instancetype)arrayWithObject:(ObjectType)object;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)idx;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)array;
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)object;
@end

@interface NSDictionary<KeyType, ObjectType> : NSObject
+ (instancetype)dictionaryWithObjects:(const ObjectType [])objects forKeys:(const KeyType [])keys count:(NSUInteger)cnt;
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
+ (instancetype)dataWithLength:(NSUInteger)length;
+ (instancetype)dataWithCapacity:(NSUInteger)capacity;
@property (nonatomic) NSUInteger length;
@property (nonatomic, readonly) void *mutableBytes;
@end

@interface NSDate : NSObject
+ (instancetype)date;
- (NSDate *)dateByAddingTimeInterval:(NSTimeInterval)seconds;
@end

@interface NSDateComponents : NSObject
@property NSInteger year;
@property NSInteger month;
@property NSInteger day;
@property NSInteger hour;
@property NSInteger minute;
@property NSInteger second;
@property NSInteger weekday;
- (NSInteger)year;
- (NSInteger)month;
- (NSInteger)day;
- (NSInteger)weekday;
@end

typedef NS_ENUM(NSInteger, NSDateFormatterStyle) {
    NSDateFormatterNoStyle = 0,
    NSDateFormatterShortStyle = 1,
    NSDateFormatterMediumStyle = 2,
    NSDateFormatterLongStyle = 3,
    NSDateFormatterFullStyle = 4
};

@interface NSDateFormatter : NSObject
@property (nonatomic, copy) NSString *dateFormat;
- (void)setLocale:(NSLocale *)locale;
- (void)setDateStyle:(NSDateFormatterStyle)style;
- (void)setTimeStyle:(NSDateFormatterStyle)style;
- (void)setTimeZone:(NSTimeZone *)timeZone;
- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;
- (NSString *)AMSymbol;
- (NSString *)PMSymbol;
+ (NSString *)dateFormatFromTemplate:(NSString *)templateName options:(NSUInteger)opts locale:(NSLocale *)locale;
@end

@interface NSLocale : NSObject
+ (instancetype)currentLocale;
+ (instancetype)localeWithLocaleIdentifier:(NSString *)identifier;
@end

@interface NSCharacterSet : NSObject
+ (instancetype)characterSetWithCharactersInString:(NSString *)string;
- (NSCharacterSet *)invertedSet;
- (BOOL)characterIsMember:(unichar)aCharacter;
@end

@interface NSTimeZone : NSObject
+ (instancetype)localTimeZone;
+ (instancetype)timeZoneWithAbbreviation:(NSString *)abbreviation;
@property (nonatomic, readonly) NSString *name;
@end

typedef NS_OPTIONS(NSUInteger, NSCalendarUnit) {
    NSCalendarUnitEra = 1UL << 1,
    NSCalendarUnitYear = 1UL << 2,
    NSCalendarUnitMonth = 1UL << 3,
    NSCalendarUnitDay = 1UL << 4,
    NSCalendarUnitHour = 1UL << 5,
    NSCalendarUnitMinute = 1UL << 6,
    NSCalendarUnitSecond = 1UL << 7,
    NSCalendarUnitWeekday = 1UL << 9
};

typedef NSString *NSCalendarIdentifier;
static NSString * const NSCalendarIdentifierGregorian = @"gregorian";
static NSString * const NSGregorianCalendar = @"gregorian";

@interface NSCalendar : NSObject
+ (instancetype)currentCalendar;
- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)identifier;
- (void)setTimeZone:(NSTimeZone *)timeZone;
@property (nonatomic, strong) NSTimeZone *timeZone;
@property NSUInteger firstWeekday;
- (NSDate *)dateFromComponents:(NSDateComponents *)components;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date;
- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
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
NSString *NSStringFromClass(Class aClass);
void NSLog(NSString *format, ...);

typedef long dispatch_once_t;
typedef void *dispatch_queue_t;
typedef void (^dispatch_block_t)(void);

#ifndef DISPATCH_QUEUE_SERIAL
#define DISPATCH_QUEUE_SERIAL NULL
#endif

static inline void dispatch_once(dispatch_once_t *predicate, void (^block)(void)) {
    if (predicate != NULL && *predicate == 0) {
        *predicate = 1;
        block();
    }
}

static inline dispatch_queue_t dispatch_queue_create(const char *label, void *attr) {
    (void)label;
    (void)attr;
    return NULL;
}

static inline void dispatch_async(dispatch_queue_t queue, dispatch_block_t block) {
    (void)queue;
    if (block != NULL) {
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
