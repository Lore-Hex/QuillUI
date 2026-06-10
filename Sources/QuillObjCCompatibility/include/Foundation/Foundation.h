#ifndef QUILL_OBJC_FOUNDATION_H
#define QUILL_OBJC_FOUNDATION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdlib.h>
#include <limits.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <assert.h>
#include <errno.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/stat.h>
#if defined(__linux__)
#include <endian.h>
#include <sys/random.h>
#endif

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
#define __nullable _Nullable
#endif

#ifndef __nonnull
#define __nonnull _Nonnull
#endif

#ifndef __unused
#define __unused __attribute__((unused))
#endif

#ifndef DEPRECATED_MSG_ATTRIBUTE
#define DEPRECATED_MSG_ATTRIBUTE(msg) __attribute__((deprecated(msg)))
#endif

typedef signed char BOOL;
typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;
typedef double NSTimeInterval;
typedef unsigned short unichar;
typedef struct _NSZone NSZone;

#ifndef QUILL_OBJC_UINT8_TYPEDEF
#define QUILL_OBJC_UINT8_TYPEDEF
typedef uint8_t UInt8;
#endif

#ifndef QUILL_OBJC_BYTE_TYPEDEF
#define QUILL_OBJC_BYTE_TYPEDEF
typedef uint8_t Byte;
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

static inline NSUInteger NSMaxRange(NSRange range) {
    return range.location + range.length;
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

#ifndef FOUNDATION_EXPORT
#ifdef __cplusplus
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) _type _name; enum
#endif

#ifndef NS_OPTIONS
#define NS_OPTIONS(_type, _name) _type _name; enum
#endif

#ifndef MIN
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif

#ifndef MAX
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#endif

typedef void (*IMP)(void);

#if defined(__OBJC__)
@class NSString;
@class NSNumber;
@class NSArray;
@class NSMutableArray;
@class NSDictionary;
@class NSMutableDictionary;
@class NSSet;
@class NSMutableSet;
@class NSOrderedSet;
@class NSMutableOrderedSet;
@class NSEnumerator;
@class NSData;
@class NSMutableData;
@class NSAttributedString;
@class NSMutableAttributedString;
@class NSDate;
@class NSDateFormatter;
@class NSDateComponentsFormatter;
@class NSTimer;
@class NSRunLoop;
@class NSLocale;
@class NSTimeZone;
@class NSBundle;
@class NSProcessInfo;
@class NSError;
@class NSValue;
@class NSNumberFormatter;
@class NSCharacterSet;
@class NSURL;
@class NSURLRequest;
@class NSMutableURLRequest;
@class NSURLResponse;
@class NSHTTPURLResponse;
@class NSURLSession;
@class NSURLSessionConfiguration;
@class NSURLSessionTask;
@class NSURLSessionDataTask;
@class NSURLComponents;
@class NSOperationQueue;
@class NSXMLParser;
@class NSTextCheckingResult;
@class NSDataDetector;
@class NSRegularExpression;
@class NSException;
@class NSFileManager;
@class NSOutputStream;
@class NSPredicate;
@class NSCoder;
@class NSKeyedArchiver;
@class NSKeyedUnarchiver;
@class NSIndexSet;
@class NSMutableIndexSet;
@class NSScanner;
@class NSThread;
@class NSNull;
@class NSNotification;
@class NSNotificationCenter;
@class NSUserDefaults;
@class NSUndoManager;

typedef struct {
    unsigned long state;
    __unsafe_unretained id *itemsPtr;
    unsigned long *mutationsPtr;
    unsigned long extra[5];
} NSFastEnumerationState;

@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id [])buffer count:(NSUInteger)len;
@end

@protocol NSCopying
- (id)copyWithZone:(NSZone *)zone;
@end

@protocol NSURLSessionDelegate
@end

@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@optional
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
@end

typedef NS_ENUM(NSInteger, NSURLSessionResponseDisposition) {
    NSURLSessionResponseCancel = 0,
    NSURLSessionResponseAllow = 1,
    NSURLSessionResponseBecomeDownload = 2,
    NSURLSessionResponseBecomeStream = 3
};

@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
@end

@protocol NSCoding
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
@end

@protocol NSSecureCoding <NSCoding>
@required
+ (BOOL)supportsSecureCoding;
@end

@protocol NSObject
@required
+ (Class)class;
- (Class)class;
- (BOOL)respondsToSelector:(SEL)aSelector;
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isEqual:(id)object;
- (id)self;
- (NSUInteger)hash;
@optional
- (NSString *)description;
- (NSString *)debugDescription;
@end

typedef NS_ENUM(NSInteger, NSComparisonResult) {
    NSOrderedAscending = -1,
    NSOrderedSame = 0,
    NSOrderedDescending = 1
};

__attribute__((objc_root_class))
@interface NSObject <NSObject>
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
- (instancetype)init;
- (Class)class;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (BOOL)isKindOfClass:(Class)aClass;
- (id)performSelector:(SEL)aSelector;
+ (void)performSelector:(SEL)aSelector onThread:(NSThread *)thread withObject:(id)arg waitUntilDone:(BOOL)wait;
- (void)performSelector:(SEL)aSelector onThread:(NSThread *)thread withObject:(id)arg waitUntilDone:(BOOL)wait;
- (IMP)methodForSelector:(SEL)aSelector;
- (BOOL)isEqual:(id)object;
- (id)self;
- (NSUInteger)hash;
- (void)doesNotRecognizeSelector:(SEL)aSelector;
- (id)valueForKey:(NSString *)key;
- (id)valueForKeyPath:(NSString *)keyPath;
- (void)setValue:(id)value forKey:(NSString *)key;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath;
- (id)copy;
- (id)mutableCopy;
@property (nonatomic, readonly) NSString *description;
@property (nonatomic, readonly) NSString *debugDescription;
@end

typedef NS_OPTIONS(NSUInteger, NSStringEnumerationOptions) {
    NSStringEnumerationByComposedCharacterSequences = 1UL << 1
};

typedef NS_OPTIONS(NSUInteger, NSStringCompareOptions) {
    NSCaseInsensitiveSearch = 1UL << 0,
    NSLiteralSearch = 1UL << 1,
    NSBackwardsSearch = 1UL << 2,
    NSAnchoredSearch = 1UL << 3,
    NSNumericSearch = 1UL << 6,
    NSRegularExpressionSearch = 1UL << 10
};

@interface NSString : NSObject
@property (nonatomic, readonly) const char *UTF8String;
@property (nonatomic, readonly) NSUInteger length;
@property (nonatomic, readonly) NSString *lastPathComponent;
+ (instancetype)string;
+ (instancetype)stringWithFormat:(NSString *)format, ...;
+ (instancetype)stringWithUTF8String:(const char *)bytes;
+ (instancetype)stringWithCString:(const char *)cString encoding:(NSUInteger)encoding;
+ (instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSUInteger)encoding error:(NSError **)error;
- (instancetype)initWithUTF8String:(const char *)bytes;
- (instancetype)initWithFormat:(NSString *)format, ...;
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)argList;
- (instancetype)initWithData:(NSData *)data encoding:(NSUInteger)encoding;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)len encoding:(NSUInteger)encoding;
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)len encoding:(NSUInteger)encoding freeWhenDone:(BOOL)freeBuffer;
+ (instancetype)stringWithCharacters:(const unichar *)characters length:(NSUInteger)length;
- (BOOL)hasSuffix:(NSString *)str;
- (BOOL)hasPrefix:(NSString *)str;
- (NSRange)rangeOfString:(NSString *)str;
- (NSRange)rangeOfString:(NSString *)str options:(NSUInteger)options;
- (NSRange)rangeOfString:(NSString *)str options:(NSUInteger)options range:(NSRange)range;
- (NSRange)lineRangeForRange:(NSRange)range;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(NSUInteger)options range:(NSRange)range;
- (NSString *)substringToIndex:(NSUInteger)to;
- (NSString *)substringFromIndex:(NSUInteger)from;
- (NSString *)substringWithRange:(NSRange)range;
- (NSString *)lowercaseString;
- (NSString *)uppercaseString;
- (NSArray *)componentsSeparatedByString:(NSString *)separator;
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSString *)stringByAppendingString:(NSString *)string;
- (NSString *)stringByAppendingFormat:(NSString *)format, ...;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement options:(NSStringCompareOptions)options range:(NSRange)searchRange;
- (NSString *)stringByReplacingCharactersInRange:(NSRange)range withString:(NSString *)replacement;
- (NSString *)stringByDeletingPathExtension;
- (NSString *)stringByAddingPercentEscapesUsingEncoding:(NSUInteger)encoding;
- (NSString *)stringByReplacingPercentEscapesUsingEncoding:(NSUInteger)encoding;
- (NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)allowedCharacters;
- (NSString *)stringByRemovingPercentEncoding;
- (NSInteger)integerValue;
- (float)floatValue;
- (double)doubleValue;
- (unichar)characterAtIndex:(NSUInteger)index;
- (NSData *)dataUsingEncoding:(NSUInteger)encoding;
- (const char *)cStringUsingEncoding:(NSUInteger)encoding;
- (NSUInteger)lengthOfBytesUsingEncoding:(NSUInteger)encoding;
- (BOOL)isEqualToString:(NSString *)string;
- (NSComparisonResult)compare:(NSString *)string;
- (NSComparisonResult)compare:(NSString *)string options:(NSStringCompareOptions)options;
- (void)enumerateSubstringsInRange:(NSRange)range
                           options:(NSStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop))block;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)capacity;
+ (instancetype)stringWithString:(NSString *)string;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithString:(NSString *)string;
- (void)appendString:(NSString *)string;
- (void)appendFormat:(NSString *)format, ...;
- (NSUInteger)replaceOccurrencesOfString:(NSString *)target
                               withString:(NSString *)replacement
                                  options:(NSUInteger)options
                                    range:(NSRange)searchRange;
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
+ (NSNumber *)numberWithUnsignedShort:(unsigned short)value;
- (instancetype)initWithInt:(int)value;
- (BOOL)boolValue;
- (int)intValue;
- (unsigned int)unsignedIntValue;
- (NSInteger)integerValue;
- (NSUInteger)unsignedIntegerValue;
- (float)floatValue;
- (short)shortValue;
- (double)doubleValue;
- (long long)longLongValue;
- (unsigned long long)unsignedLongLongValue;
- (NSComparisonResult)compare:(NSNumber *)otherNumber;
@end

@interface NSNull : NSObject <NSCopying, NSSecureCoding>
+ (NSNull *)null;
@end

@interface NSArray<ObjectType> : NSObject <NSFastEnumeration>
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) ObjectType firstObject;
@property (nonatomic, readonly) ObjectType lastObject;
@property (nonatomic, readonly) NSEnumerator *objectEnumerator;
@property (nonatomic, readonly) NSEnumerator *reverseObjectEnumerator;
+ (instancetype)array;
+ (instancetype)arrayWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)arrayWithObject:(ObjectType)object;
+ (instancetype)arrayWithObjects:(ObjectType)firstObject, ...;
+ (instancetype)arrayWithObjects:(const ObjectType [])objects count:(NSUInteger)cnt;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (ObjectType)objectAtIndex:(NSUInteger)index;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)idx;
- (BOOL)containsObject:(ObjectType)object;
- (NSUInteger)indexOfObject:(ObjectType)object;
- (BOOL)isEqualToArray:(NSArray<ObjectType> *)otherArray;
- (NSString *)componentsJoinedByString:(NSString *)separator;
- (NSArray<ObjectType> *)sortedArrayUsingSelector:(SEL)comparator;
- (NSArray<ObjectType> *)filteredArrayUsingPredicate:(NSPredicate *)predicate;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparisonResult (^)(ObjectType obj1, ObjectType obj2))comparator;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)array;
+ (instancetype)arrayWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)object;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)insertObject:(ObjectType)object atIndex:(NSUInteger)index;
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(ObjectType)object;
- (void)exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2;
- (void)removeObject:(ObjectType)object;
- (void)removeObjectIdenticalTo:(ObjectType)object;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeObjectsInArray:(NSArray<ObjectType> *)otherArray;
- (void)removeObjectsInRange:(NSRange)range;
- (void)removeLastObject;
- (void)removeAllObjects;
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes;
- (void)sortUsingSelector:(SEL)comparator;
- (void)sortUsingComparator:(NSComparisonResult (^)(ObjectType obj1, ObjectType obj2))comparator;
- (void)setObject:(ObjectType)object atIndexedSubscript:(NSUInteger)idx;
@end

@interface NSIndexSet : NSObject <NSCopying>
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger firstIndex;
@property (nonatomic, readonly) NSUInteger lastIndex;
+ (instancetype)indexSet;
+ (instancetype)indexSetWithIndex:(NSUInteger)value;
+ (instancetype)indexSetWithIndexesInRange:(NSRange)range;
- (BOOL)containsIndex:(NSUInteger)value;
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger idx, BOOL *stop))block;
@end

@interface NSMutableIndexSet : NSIndexSet
- (void)addIndex:(NSUInteger)value;
- (void)addIndexes:(NSIndexSet *)indexSet;
- (void)addIndexesInRange:(NSRange)range;
- (void)removeIndex:(NSUInteger)value;
- (void)removeIndexes:(NSIndexSet *)indexSet;
- (void)removeIndexesInRange:(NSRange)range;
- (void)shiftIndexesStartingAtIndex:(NSUInteger)index by:(NSInteger)delta;
@end

@interface NSDictionary<KeyType, ObjectType> : NSObject <NSFastEnumeration>
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSArray<KeyType> *allKeys;
@property (nonatomic, readonly) NSArray<ObjectType> *allValues;
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithDictionary:(NSDictionary<KeyType, ObjectType> *)dict;
+ (instancetype)dictionaryWithObject:(ObjectType)object forKey:(KeyType)key;
+ (instancetype)dictionaryWithObjectsAndKeys:(ObjectType)firstObject, ...;
+ (instancetype)dictionaryWithObjects:(const ObjectType [])objects forKeys:(const KeyType [])keys count:(NSUInteger)cnt;
- (instancetype)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)otherDictionary;
- (ObjectType)objectForKey:(KeyType)key;
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;
@end

@interface NSMutableDictionary<KeyType, ObjectType> : NSDictionary<KeyType, ObjectType>
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)otherDictionary;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)setObject:(ObjectType)obj forKey:(KeyType)key;
- (void)setValue:(ObjectType)value forKey:(KeyType)key;
- (void)setObject:(ObjectType)obj forKeyedSubscript:(KeyType)key;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeAllObjects;
@end

@interface NSSet<ObjectType> : NSObject <NSFastEnumeration>
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSArray<ObjectType> *allObjects;
+ (instancetype)set;
+ (instancetype)setWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)setWithObject:(ObjectType)object;
+ (instancetype)setWithSet:(NSSet<ObjectType> *)set;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
- (BOOL)containsObject:(ObjectType)object;
- (ObjectType)anyObject;
- (NSSet<ObjectType> *)setByAddingObject:(ObjectType)object;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, BOOL *stop))block;
@end

@interface NSMutableSet<ObjectType> : NSSet<ObjectType>
+ (instancetype)set;
+ (instancetype)setWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)setWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
- (void)addObject:(ObjectType)object;
- (void)removeObject:(ObjectType)object;
- (void)removeAllObjects;
- (void)minusSet:(NSSet<ObjectType> *)otherSet;
- (void)unionSet:(NSSet<ObjectType> *)otherSet;
@end

@interface NSOrderedSet<ObjectType> : NSObject <NSFastEnumeration>
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSArray<ObjectType> *array;
+ (instancetype)orderedSetWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (ObjectType)objectAtIndex:(NSUInteger)idx;
- (BOOL)containsObject:(ObjectType)object;
@end

@interface NSMutableOrderedSet<ObjectType> : NSOrderedSet<ObjectType>
+ (instancetype)orderedSetWithArray:(NSArray<ObjectType> *)array;
- (void)addObject:(ObjectType)object;
- (void)removeObject:(ObjectType)object;
@end

@interface NSEnumerator<ObjectType> : NSObject <NSFastEnumeration>
@property (nonatomic, readonly) NSArray<ObjectType> *allObjects;
- (ObjectType)nextObject;
@end

@interface NSError : NSObject
@property (nonatomic, readonly) NSString *domain;
@property (nonatomic, readonly) NSInteger code;
@property (nonatomic, readonly) NSDictionary *userInfo;
@property (nonatomic, readonly) NSString *localizedDescription;
+ (instancetype)errorWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict;
@end

@interface NSCoder : NSObject
- (BOOL)allowsKeyedCoding;
- (BOOL)containsValueForKey:(NSString *)key;
- (id)decodeObjectForKey:(NSString *)key;
- (BOOL)decodeBoolForKey:(NSString *)key;
- (int)decodeIntForKey:(NSString *)key;
- (int32_t)decodeInt32ForKey:(NSString *)key;
- (int64_t)decodeInt64ForKey:(NSString *)key;
- (NSInteger)decodeIntegerForKey:(NSString *)key;
- (float)decodeFloatForKey:(NSString *)key;
- (double)decodeDoubleForKey:(NSString *)key;
- (void)encodeObject:(id)objv forKey:(NSString *)key;
- (void)encodeBool:(BOOL)boolv forKey:(NSString *)key;
- (void)encodeInt:(int)intv forKey:(NSString *)key;
- (void)encodeInt32:(int32_t)intv forKey:(NSString *)key;
- (void)encodeInt64:(int64_t)intv forKey:(NSString *)key;
- (void)encodeInteger:(NSInteger)intv forKey:(NSString *)key;
- (void)encodeFloat:(float)realv forKey:(NSString *)key;
- (void)encodeDouble:(double)realv forKey:(NSString *)key;
@end

@interface NSKeyedArchiver : NSCoder
+ (NSData *)archivedDataWithRootObject:(id)rootObject;
+ (NSData *)archivedDataWithRootObject:(id)rootObject requiringSecureCoding:(BOOL)requiresSecureCoding error:(NSError **)error;
@end

@interface NSKeyedUnarchiver : NSCoder
+ (id)unarchiveObjectWithData:(NSData *)data;
+ (id)unarchiveObjectWithFile:(NSString *)path;
@end

typedef NS_OPTIONS(NSUInteger, NSDataBase64DecodingOptions) {
    NSDataBase64DecodingIgnoreUnknownCharacters = 1UL << 0
};

typedef NS_OPTIONS(NSUInteger, NSDataBase64EncodingOptions) {
    NSDataBase64Encoding64CharacterLineLength = 1UL << 0,
    NSDataBase64Encoding76CharacterLineLength = 1UL << 1,
    NSDataBase64EncodingEndLineWithCarriageReturn = 1UL << 4,
    NSDataBase64EncodingEndLineWithLineFeed = 1UL << 5
};

@interface NSData : NSObject
+ (instancetype)data;
+ (instancetype)dataWithContentsOfFile:(NSString *)path;
+ (instancetype)dataWithData:(NSData *)data;
+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length;
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)freeWhenDone;
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length;
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)freeWhenDone;
- (instancetype)initWithBase64EncodedString:(NSString *)base64String options:(NSDataBase64DecodingOptions)options;
- (instancetype)initWithBase64Encoding:(NSString *)base64String;
@property (nonatomic, readonly) const void *bytes;
@property (nonatomic, readonly) NSUInteger length;
- (void)getBytes:(void *)buffer length:(NSUInteger)length;
- (void)getBytes:(void *)buffer range:(NSRange)range;
- (NSData *)subdataWithRange:(NSRange)range;
- (BOOL)isEqualToData:(NSData *)other;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile;
- (NSData *)base64EncodedDataWithOptions:(NSDataBase64EncodingOptions)options;
- (NSString *)base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)options;
- (NSString *)base64Encoding;
@end

@interface NSMutableData : NSData
+ (instancetype)dataWithLength:(NSUInteger)length;
+ (instancetype)dataWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithLength:(NSUInteger)length;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
@property (nonatomic) NSUInteger length;
@property (nonatomic, readonly) void *mutableBytes;
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length;
- (void)appendData:(NSData *)data;
- (void)increaseLengthBy:(NSUInteger)extraLength;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)replacementBytes length:(NSUInteger)replacementLength;
@end

typedef NSString *NSAttributedStringKey;

@interface NSAttributedString : NSObject <NSCopying>
@property (nonatomic, readonly) NSString *string;
@property (nonatomic, readonly) NSUInteger length;
- (instancetype)initWithString:(NSString *)str;
- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary *)attrs;
- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr;
- (BOOL)isEqualToAttributedString:(NSAttributedString *)other;
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range;
- (id)attribute:(NSAttributedStringKey)attrName atIndex:(NSUInteger)location effectiveRange:(NSRange *)range;
- (void)enumerateAttribute:(NSAttributedStringKey)attrName
                   inRange:(NSRange)enumerationRange
                   options:(NSUInteger)opts
                usingBlock:(void (^)(id value, NSRange range, BOOL *stop))block;
- (void)enumerateAttributesInRange:(NSRange)enumerationRange
                            options:(NSUInteger)opts
                         usingBlock:(void (^)(NSDictionary<NSAttributedStringKey, id> *attrs, NSRange range, BOOL *stop))block;
@end

@interface NSMutableAttributedString : NSAttributedString
+ (instancetype)alloc;
- (instancetype)init;
- (instancetype)initWithString:(NSString *)str;
- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr;
- (void)setAttributedString:(NSAttributedString *)attrStr;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str;
- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)attrString;
- (void)addAttribute:(NSAttributedStringKey)name value:(id)value range:(NSRange)range;
- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range;
- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range;
- (void)removeAttribute:(NSAttributedStringKey)name range:(NSRange)range;
@end

@interface NSDate : NSObject
+ (instancetype)date;
+ (instancetype)distantFuture;
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)seconds;
- (NSDate *)dateByAddingTimeInterval:(NSTimeInterval)seconds;
- (NSTimeInterval)timeIntervalSinceNow;
@property (nonatomic, readonly) NSTimeInterval timeIntervalSince1970;
@end

typedef NSString *NSRunLoopMode;
static NSString * const NSDefaultRunLoopMode = @"NSDefaultRunLoopMode";
static NSString * const NSRunLoopCommonModes = @"NSRunLoopCommonModes";

@interface NSRunLoop : NSObject
@property (nonatomic, readonly) NSRunLoopMode currentMode;
+ (NSRunLoop *)currentRunLoop;
+ (NSRunLoop *)mainRunLoop;
- (void)run;
- (void)runUntilDate:(NSDate *)limitDate;
- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;
- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode;
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

typedef NS_ENUM(NSInteger, NSDateComponentsFormatterUnitsStyle) {
    NSDateComponentsFormatterUnitsStylePositional = 0,
    NSDateComponentsFormatterUnitsStyleAbbreviated = 1,
    NSDateComponentsFormatterUnitsStyleShort = 2,
    NSDateComponentsFormatterUnitsStyleFull = 3,
    NSDateComponentsFormatterUnitsStyleSpellOut = 4
};

@interface NSDateComponentsFormatter : NSObject
@property NSDateComponentsFormatterUnitsStyle unitsStyle;
- (NSString *)stringFromTimeInterval:(NSTimeInterval)ti;
@end

@interface NSLocale : NSObject
+ (instancetype)currentLocale;
+ (instancetype)localeWithLocaleIdentifier:(NSString *)identifier;
+ (NSString *)canonicalLanguageIdentifierFromString:(NSString *)string;
+ (NSArray<NSString *> *)preferredLanguages;
- (instancetype)initWithLocaleIdentifier:(NSString *)identifier;
- (id)objectForKey:(NSString *)key;
- (NSString *)displayNameForKey:(id)key value:(id)value;
@end

typedef NS_ENUM(NSInteger, NSLocaleLanguageDirection) {
    NSLocaleLanguageDirectionUnknown = 0,
    NSLocaleLanguageDirectionLeftToRight = 1,
    NSLocaleLanguageDirectionRightToLeft = 2,
    NSLocaleLanguageDirectionTopToBottom = 3,
    NSLocaleLanguageDirectionBottomToTop = 4
};

@interface NSLocale (QuillLanguageDirection)
+ (NSLocaleLanguageDirection)characterDirectionForLanguage:(NSString *)isoLangCode;
@end

static NSString * const NSLocaleCountryCode = @"kCFLocaleCountryCode";

@interface NSInputStream : NSObject
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithURL:(NSURL *)url;
- (void)open;
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len;
- (void)close;
- (BOOL)hasBytesAvailable;
@end

@interface NSOutputStream : NSObject
- (instancetype)initToMemory;
- (void)open;
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len;
- (id)propertyForKey:(NSString *)key;
- (void)close;
- (BOOL)hasSpaceAvailable;
@end

static NSString * const NSStreamDataWrittenToMemoryStreamKey = @"NSStreamDataWrittenToMemoryStreamKey";

@interface NSThread : NSObject
@property (nonatomic, copy) NSString *name;
+ (NSThread *)currentThread;
+ (BOOL)isMainThread;
+ (void)sleepForTimeInterval:(NSTimeInterval)timeInterval;
- (instancetype)initWithTarget:(id)target selector:(SEL)selector object:(id)argument;
- (BOOL)isMainThread;
- (void)start;
@end

@interface NSCharacterSet : NSObject
+ (instancetype)characterSetWithCharactersInString:(NSString *)string;
+ (instancetype)alphanumericCharacterSet;
+ (instancetype)decimalDigitCharacterSet;
+ (instancetype)whitespaceCharacterSet;
+ (instancetype)newlineCharacterSet;
+ (instancetype)whitespaceAndNewlineCharacterSet;
+ (instancetype)URLQueryAllowedCharacterSet;
- (NSCharacterSet *)invertedSet;
- (BOOL)characterIsMember:(unichar)aCharacter;
- (BOOL)isSupersetOfSet:(NSCharacterSet *)other;
@end

@protocol NSXMLParserDelegate
@optional
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributeDict;
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName;
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string;
@end

@interface NSXMLParser : NSObject
@property (nonatomic, weak) id<NSXMLParserDelegate> delegate;
- (instancetype)initWithData:(NSData *)data;
- (BOOL)parse;
@end

@interface NSTimeZone : NSObject
+ (instancetype)localTimeZone;
+ (instancetype)timeZoneWithAbbreviation:(NSString *)abbreviation;
@property (nonatomic, readonly) NSString *name;
- (NSInteger)secondsFromGMT;
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
+ (instancetype)bundleWithURL:(NSURL *)url;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
- (NSDictionary *)infoDictionary;
- (id)objectForInfoDictionaryKey:(NSString *)key;
- (NSString *)bundleIdentifier;
- (NSArray<NSString *> *)preferredLocalizations;
@end

@interface NSProcessInfo : NSObject
+ (NSProcessInfo *)processInfo;
- (NSString *)operatingSystemVersionString;
@end

@interface NSFileManager : NSObject
+ (instancetype)defaultManager;
- (NSString *)displayNameAtPath:(NSString *)path;
- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeItemAtURL:(NSURL *)URL error:(NSError **)error;
@end

@interface NSURL : NSObject
+ (instancetype)fileURLWithPath:(NSString *)path;
+ (instancetype)URLWithString:(NSString *)URLString;
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *scheme;
@property (nonatomic, readonly) NSString *query;
@property (nonatomic, readonly) const char *fileSystemRepresentation;
@end

@interface NSURLComponents : NSObject
@property (nonatomic, copy) NSString *percentEncodedQuery;
@property (nonatomic, readonly) NSURL *URL;
+ (instancetype)componentsWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve;
- (instancetype)initWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve;
@end

typedef void (^NSURLSessionDataTaskCompletionHandler)(NSData *data, NSURLResponse *response, NSError *error);

typedef NS_ENUM(NSUInteger, NSURLRequestCachePolicy) {
    NSURLRequestUseProtocolCachePolicy = 0,
    NSURLRequestReloadIgnoringLocalCacheData = 1,
    NSURLRequestReturnCacheDataElseLoad = 2,
    NSURLRequestReturnCacheDataDontLoad = 3
};

@interface NSURLRequest : NSObject
@property (nonatomic, readonly) NSURL *URL;
+ (instancetype)requestWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval;
@end

@interface NSMutableURLRequest : NSURLRequest
@property (nonatomic, copy) NSString *HTTPMethod;
@property (nonatomic, copy) NSData *HTTPBody;
+ (instancetype)requestWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval;
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field;
- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field;
@end

@interface NSURLResponse : NSObject
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSString *MIMEType;
@property (nonatomic, readonly) NSString *textEncodingName;
@property (nonatomic, readonly) long long expectedContentLength;
@end

@interface NSHTTPURLResponse : NSURLResponse
@property (nonatomic, readonly) NSInteger statusCode;
@property (nonatomic, readonly) NSDictionary *allHeaderFields;
+ (NSString *)localizedStringForStatusCode:(NSInteger)statusCode;
@end

@interface NSURLSessionConfiguration : NSObject
@property (nonatomic, copy) NSDictionary *HTTPAdditionalHeaders;
@property NSTimeInterval timeoutIntervalForRequest;
+ (instancetype)defaultSessionConfiguration;
+ (instancetype)ephemeralSessionConfiguration;
@end

@interface NSURLSessionTask : NSObject
- (void)resume;
- (void)cancel;
@end

@interface NSURLSessionDataTask : NSURLSessionTask
@end

@interface NSURLSession : NSObject
+ (NSURLSession *)sharedSession;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                  delegate:(id<NSURLSessionDelegate>)delegate
                             delegateQueue:(NSOperationQueue *)queue;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(NSURLSessionDataTaskCompletionHandler)completionHandler;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;
@end

@interface NSOperation : NSObject
@property (getter=isCancelled, readonly) BOOL cancelled;
@property (getter=isExecuting, readonly) BOOL executing;
@property (getter=isFinished, readonly) BOOL finished;
@property (getter=isAsynchronous, readonly) BOOL asynchronous;
@property (copy) void (^completionBlock)(void);
- (void)start;
- (void)main;
- (void)cancel;
@end

typedef NS_ENUM(NSInteger, NSQualityOfService) {
    NSQualityOfServiceUserInteractive = 0x21,
    NSQualityOfServiceUserInitiated = 0x19,
    NSQualityOfServiceUtility = 0x11,
    NSQualityOfServiceBackground = 0x09,
    NSQualityOfServiceDefault = -1
};

@interface NSOperationQueue : NSObject
@property NSInteger maxConcurrentOperationCount;
@property (nonatomic, copy) NSString *name;
@property NSQualityOfService qualityOfService;
+ (NSOperationQueue *)mainQueue;
- (void)addOperation:(NSOperation *)operation;
- (void)addOperationWithBlock:(void (^)(void))block;
- (void)cancelAllOperations;
@end

typedef NS_OPTIONS(uint64_t, NSTextCheckingType) {
    NSTextCheckingTypeLink = 1ULL << 5,
    NSTextCheckingTypePhoneNumber = 1ULL << 11
};

typedef NSUInteger NSMatchingOptions;
typedef NSUInteger NSMatchingFlags;
typedef NSUInteger NSRegularExpressionOptions;

static const NSRegularExpressionOptions NSRegularExpressionCaseInsensitive = 1UL << 0;
static const NSRegularExpressionOptions NSRegularExpressionDotMatchesLineSeparators = 1UL << 3;
static const NSMatchingOptions NSMatchingWithoutAnchoringBounds = 1UL << 4;

@interface NSTextCheckingResult : NSObject
@property (nonatomic, readonly) NSTextCheckingType resultType;
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) NSUInteger numberOfRanges;
@property (nonatomic, readonly) NSURL *URL;
- (NSRange)rangeAtIndex:(NSUInteger)idx;
@end

@interface NSDataDetector : NSObject
+ (instancetype)dataDetectorWithTypes:(NSTextCheckingType)checkingTypes error:(NSError **)error;
- (void)enumerateMatchesInString:(NSString *)string
                         options:(NSMatchingOptions)options
                           range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop))block;
@end

@interface NSRegularExpression : NSObject
+ (instancetype)regularExpressionWithPattern:(NSString *)pattern options:(NSUInteger)options error:(NSError **)error;
- (void)enumerateMatchesInString:(NSString *)string
                         options:(NSMatchingOptions)options
                           range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop))block;
- (NSUInteger)numberOfMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range;
- (NSTextCheckingResult *)firstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range;
- (NSUInteger)replaceMatchesInString:(NSMutableString *)string
                              options:(NSMatchingOptions)options
                                range:(NSRange)range
                         withTemplate:(NSString *)templ;
@end

@interface NSScanner : NSObject
@property NSUInteger scanLocation;
@property BOOL caseSensitive;
+ (instancetype)scannerWithString:(NSString *)string;
- (instancetype)initWithString:(NSString *)string;
- (BOOL)scanString:(NSString *)string intoString:(NSString **)result;
- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)result;
- (BOOL)scanInt:(int *)result;
- (BOOL)scanInteger:(NSInteger *)result;
- (BOOL)scanLongLong:(long long *)result;
- (BOOL)scanHexInt:(unsigned *)result;
- (BOOL)scanHexLongLong:(unsigned long long *)result;
@end

@interface NSException : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *reason;
@property (nonatomic, readonly) NSDictionary *userInfo;
+ (void)raise:(NSString *)name format:(NSString *)format, ...;
+ (instancetype)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo;
- (instancetype)initWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo;
- (void)raise;
@end

@interface NSPredicate : NSObject
+ (instancetype)predicateWithFormat:(NSString *)format, ...;
+ (instancetype)predicateWithBlock:(BOOL (^)(id evaluatedObject, NSDictionary *bindings))block;
@end

@interface NSValue : NSObject
+ (instancetype)valueWithRange:(NSRange)range;
- (NSRange)rangeValue;
@end

typedef NSString *NSNotificationName;

@interface NSNotification : NSObject
+ (instancetype)notificationWithName:(NSNotificationName)aName object:(id)anObject;
@property (nonatomic, readonly) NSNotificationName name;
@property (nonatomic, readonly) id object;
@end

@interface NSNotificationCenter : NSObject
+ (NSNotificationCenter *)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSNotificationName)aName object:(id)anObject;
- (void)removeObserver:(id)observer;
- (void)postNotificationName:(NSNotificationName)aName object:(id)anObject;
@end

@interface NSUserDefaults : NSObject
+ (NSUserDefaults *)standardUserDefaults;
- (id)objectForKey:(NSString *)defaultName;
- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (BOOL)boolForKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;
@end

@interface NSUndoManager : NSObject
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)object;
- (void)removeAllActionsWithTarget:(id)target;
- (void)removeAllActions;
- (void)setActionName:(NSString *)actionName;
@property (nonatomic, readonly) BOOL isUndoing;
@property (nonatomic, readonly) BOOL isRedoing;
@end

NSString *NSStringFromClass(Class aClass);

typedef NS_OPTIONS(NSUInteger, NSJSONReadingOptions) {
    NSJSONReadingMutableContainers = 1UL << 0,
    NSJSONReadingMutableLeaves = 1UL << 1,
    NSJSONReadingFragmentsAllowed = 1UL << 2,
    NSJSONReadingAllowFragments = 1UL << 2
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
#ifndef NSLocalizedStringWithDefaultValue
#define NSLocalizedStringWithDefaultValue(key, tableName, bundle, value, comment) (value)
#endif
NSString *NSStringFromClass(Class aClass);
Class NSClassFromString(NSString *aClassName);
SEL NSSelectorFromString(NSString *aSelectorName);
NSString *NSStringFromSelector(SEL aSelector);
NSString *NSHomeDirectory(void);
void NSLog(NSString *format, ...);

static inline uint32_t arc4random(void) {
#if defined(__linux__)
    uint32_t value = 0;
    if (getrandom(&value, sizeof(value), 0) == (ssize_t)sizeof(value)) {
        return value;
    }
#endif
    return 4;
}

static inline void arc4random_buf(void *buffer, size_t length) {
#if defined(__linux__)
    if (buffer != NULL && getrandom(buffer, length, 0) == (ssize_t)length) {
        return;
    }
#endif
    uint8_t *bytes = (uint8_t *)buffer;
    for (size_t index = 0; index < length; index++) {
        bytes[index] = (uint8_t)arc4random();
    }
}

static inline uint32_t arc4random_uniform(uint32_t upperBound) {
    if (upperBound == 0) {
        return 0;
    }
    uint32_t threshold = (uint32_t)(-upperBound % upperBound);
    for (;;) {
        uint32_t value = arc4random();
        if (value >= threshold) {
            return value % upperBound;
        }
    }
}

static inline uint16_t OSSwapInt16(uint16_t value) {
    return __builtin_bswap16(value);
}

static inline uint32_t OSSwapInt32(uint32_t value) {
    return __builtin_bswap32(value);
}

static inline uint64_t OSSwapInt64(uint64_t value) {
    return __builtin_bswap64(value);
}

static inline uint16_t OSSwapHostToBigInt16(uint16_t value) {
    return htons(value);
}

static inline uint16_t OSSwapBigToHostInt16(uint16_t value) {
    return ntohs(value);
}

static NSString * const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
static NSString * const NSURLErrorDomain = @"NSURLErrorDomain";
static NSString * const NSURLErrorKey = @"NSErrorFailingURLKey";
static NSString * const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
static NSString * const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
static NSString * const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
static NSString * const NSUnderlyingErrorKey = @"NSUnderlyingError";
static NSString * const NSGenericException = @"NSGenericException";
static NSString * const NSInvalidArgumentException = @"NSInvalidArgumentException";
static const NSUInteger NSASCIIStringEncoding = 1;
static const NSUInteger NSUTF8StringEncoding = 4;
static const long long NSURLResponseUnknownLength = -1;
static const NSUInteger kNilOptions = 0;

typedef long dispatch_once_t;
typedef uint64_t dispatch_time_t;
typedef void *dispatch_object_t;
#ifndef QUILL_OBJC_DISPATCH_QUEUE_T_TYPEDEF
#define QUILL_OBJC_DISPATCH_QUEUE_T_TYPEDEF
typedef void *dispatch_queue_t;
#endif
typedef void *dispatch_queue_attr_t;
typedef void *dispatch_semaphore_t;
typedef void *dispatch_group_t;
typedef void *dispatch_source_t;
typedef const void *dispatch_source_type_t;
typedef void (*dispatch_function_t)(void *);
typedef void (^dispatch_block_t)(void);

static __thread dispatch_queue_t quill_dispatch_current_queue = NULL;

#ifndef DISPATCH_QUEUE_SERIAL
#define DISPATCH_QUEUE_SERIAL NULL
#endif

#ifndef DISPATCH_QUEUE_CONCURRENT
#define DISPATCH_QUEUE_CONCURRENT ((dispatch_queue_attr_t)1)
#endif

#ifndef DISPATCH_QUEUE_PRIORITY_HIGH
#define DISPATCH_QUEUE_PRIORITY_HIGH 2
#endif

#ifndef DISPATCH_QUEUE_PRIORITY_DEFAULT
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#endif

#ifndef DISPATCH_QUEUE_PRIORITY_LOW
#define DISPATCH_QUEUE_PRIORITY_LOW (-2)
#endif

#ifndef DISPATCH_QUEUE_PRIORITY_BACKGROUND
#define DISPATCH_QUEUE_PRIORITY_BACKGROUND INT16_MIN
#endif

#ifndef OS_OBJECT_HAVE_OBJC_SUPPORT
#define OS_OBJECT_HAVE_OBJC_SUPPORT 0
#endif

#ifndef DISPATCH_TIME_NOW
#define DISPATCH_TIME_NOW ((dispatch_time_t)0)
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
    return malloc(1);
}

static inline dispatch_queue_t dispatch_get_global_queue(long identifier, unsigned long flags) {
    (void)identifier;
    (void)flags;
    static char queue;
    return &queue;
}

static inline dispatch_queue_t dispatch_get_main_queue(void) {
    static char queue;
    return &queue;
}

static inline dispatch_queue_t dispatch_get_current_queue(void) {
    return quill_dispatch_current_queue;
}

static inline dispatch_semaphore_t dispatch_semaphore_create(long value) {
    (void)value;
    return NULL;
}

static inline long dispatch_semaphore_wait(dispatch_semaphore_t semaphore, uint64_t timeout) {
    (void)semaphore;
    (void)timeout;
    return 0;
}

static inline long dispatch_semaphore_signal(dispatch_semaphore_t semaphore) {
    (void)semaphore;
    return 0;
}

static inline dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta) {
    return when + (dispatch_time_t)delta;
}

static inline void quill_dispatch_execute(dispatch_queue_t queue, dispatch_block_t block) {
    if (block == NULL) {
        return;
    }
    dispatch_queue_t previousQueue = quill_dispatch_current_queue;
    quill_dispatch_current_queue = queue;
    block();
    quill_dispatch_current_queue = previousQueue;
}

static inline void dispatch_async(dispatch_queue_t queue, dispatch_block_t block) {
    quill_dispatch_execute(queue, block);
}

static inline void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block) {
    quill_dispatch_execute(queue, block);
}

static inline void dispatch_set_target_queue(dispatch_object_t object, dispatch_queue_t queue) {
    (void)object;
    (void)queue;
}

static inline void dispatch_queue_set_specific(dispatch_queue_t queue, const void *key, void *context, dispatch_function_t destructor) {
    (void)queue;
    (void)key;
    (void)context;
    (void)destructor;
}

static inline void *dispatch_get_specific(const void *key) {
    (void)key;
    return NULL;
}

static inline void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    (void)when;
    dispatch_async(queue, block);
}

static inline void dispatch_retain(dispatch_object_t object) {
    (void)object;
}

static inline void dispatch_release(dispatch_object_t object) {
    (void)object;
}

static inline dispatch_source_t dispatch_source_create(dispatch_source_type_t type, uintptr_t handle, unsigned long mask, dispatch_queue_t queue) {
    (void)type;
    (void)handle;
    (void)mask;
    (void)queue;
    return NULL;
}

static inline void dispatch_source_set_timer(dispatch_source_t source, dispatch_time_t start, uint64_t interval, uint64_t leeway) {
    (void)source;
    (void)start;
    (void)interval;
    (void)leeway;
}

static inline void dispatch_source_set_event_handler(dispatch_source_t source, dispatch_block_t handler) {
    (void)source;
    (void)handler;
}

static inline void dispatch_source_set_cancel_handler(dispatch_source_t source, dispatch_block_t handler) {
    (void)source;
    (void)handler;
}

static inline unsigned long dispatch_source_get_data(dispatch_source_t source) {
    (void)source;
    return 0;
}

static inline void dispatch_source_cancel(dispatch_source_t source) {
    (void)source;
}

static inline void dispatch_resume(dispatch_object_t object) {
    (void)object;
}

static inline void dispatch_suspend(dispatch_object_t object) {
    (void)object;
}

static inline dispatch_group_t dispatch_group_create(void) {
    return NULL;
}

static inline void dispatch_group_enter(dispatch_group_t group) {
    (void)group;
}

static inline void dispatch_group_leave(dispatch_group_t group) {
    (void)group;
}

static inline long dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout) {
    (void)group;
    (void)timeout;
    return 0;
}

static inline void dispatch_group_notify(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block) {
    (void)group;
    dispatch_async(queue, block);
}

#ifndef DISPATCH_TIME_FOREVER
#define DISPATCH_TIME_FOREVER UINT64_MAX
#endif

#ifndef DISPATCH_SOURCE_TYPE_TIMER
#define DISPATCH_SOURCE_TYPE_TIMER ((dispatch_source_type_t)1)
#endif

#ifndef DISPATCH_SOURCE_TYPE_READ
#define DISPATCH_SOURCE_TYPE_READ ((dispatch_source_type_t)2)
#endif

#ifndef DISPATCH_SOURCE_TYPE_WRITE
#define DISPATCH_SOURCE_TYPE_WRITE ((dispatch_source_type_t)3)
#endif

#ifndef NSEC_PER_SEC
#define NSEC_PER_SEC 1000000000ull
#endif

#ifndef NSEC_PER_MSEC
#define NSEC_PER_MSEC 1000000ull
#endif

#ifndef NSEC_PER_USEC
#define NSEC_PER_USEC 1000ull
#endif

#ifndef QOS_CLASS_USER_INITIATED
#define QOS_CLASS_USER_INITIATED 0x19
#endif

#ifndef NSAssert
#define NSAssert(condition, desc, ...) ((void)0)
#endif

#ifndef NSCAssert
#define NSCAssert(condition, desc, ...) ((void)0)
#endif

#ifndef NSParameterAssert
#define NSParameterAssert(condition) ((void)0)
#endif

#else

typedef struct objc_object NSObject;
typedef struct objc_object NSString;
typedef struct objc_object NSNumber;
typedef struct objc_object NSArray;
typedef struct objc_object NSMutableArray;
typedef struct objc_object NSDictionary;
typedef struct objc_object NSMutableDictionary;
typedef struct objc_object NSSet;
typedef struct objc_object NSMutableSet;
typedef struct objc_object NSData;
typedef struct objc_object NSMutableData;
typedef struct objc_object NSDate;
typedef struct objc_object NSError;
typedef struct objc_object NSURL;
typedef struct objc_object NSURLRequest;
typedef struct objc_object NSURLResponse;
typedef struct objc_object NSValue;
typedef struct objc_object NSNull;

#endif

#ifndef ABS
#define ABS(x) (((x) < 0) ? -(x) : (x))
#endif

#endif
