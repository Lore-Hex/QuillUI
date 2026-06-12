/* QuartzCore (CoreAnimation) Objective-C compatibility surface for Telegram
 * package islands compiled through QuillObjCCompatibility. */
#ifndef QUILL_OBJC_QUARTZCORE_H
#define QUILL_OBJC_QUARTZCORE_H

#include <Foundation/Foundation.h>

#if defined(__OBJC__)

@class CAAnimation;

@protocol CAAnimationDelegate <NSObject>
@optional
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
@end

@interface CAAnimation : NSObject
@property (nonatomic, weak) id<CAAnimationDelegate> delegate;
@property (nonatomic) BOOL removedOnCompletion;
@property (nonatomic) NSTimeInterval duration;
@end

@interface CAMediaTimingFunction : NSObject
+ (instancetype)functionWithName:(NSString *)name;
@end

@interface CABasicAnimation : CAAnimation
+ (instancetype)animationWithKeyPath:(NSString *)path;
@property (nonatomic, strong) id fromValue;
@property (nonatomic, strong) id toValue;
@property (nonatomic, strong) CAMediaTimingFunction *timingFunction;
@end

@interface CALayer : NSObject
@property (nonatomic) float opacity;
@property (nonatomic) CGRect frame;
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key;
- (void)removeAnimationForKey:(NSString *)key;
- (CAAnimation *)animationForKey:(NSString *)key;
- (NSArray<NSString *> *)animationKeys;
- (id)presentationLayer;
- (id)valueForKeyPath:(NSString *)keyPath;
@end

@interface CATransaction : NSObject
+ (void)begin;
+ (void)commit;
+ (void)setDisableActions:(BOOL)flag;
@end

static NSString * const kCAMediaTimingFunctionEaseOut = @"easeOut";

#endif

#endif
