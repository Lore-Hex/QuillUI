#ifndef QUILL_OBJC_JAVASCRIPTCORE_H
#define QUILL_OBJC_JAVASCRIPTCORE_H

#include <Foundation/Foundation.h>

@class JSContext;

@interface JSValue : NSObject
+ (JSValue *)valueWithObject:(id)value inContext:(JSContext *)context;
- (JSValue *)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKeyedSubscript:(id)key;
- (JSValue *)callWithArguments:(NSArray *)arguments;
- (BOOL)isString;
- (NSString *)toString;
@end

typedef void (^JSContextExceptionHandler)(JSContext *context, JSValue *exception);

@interface JSContext : NSObject
@property (nonatomic, copy) JSContextExceptionHandler exceptionHandler;
- (JSValue *)evaluateScript:(NSString *)script;
- (JSValue *)evaluateScript:(NSString *)script withSourceURL:(NSURL *)sourceURL;
- (JSValue *)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKeyedSubscript:(id)key;
@end

#endif
