#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Internal launch adapter: an app-private record contains no absolute path.
// The launch lease remains open for the whole guest lifetime. Its absence is
// a hard failure, never a reason to use Documents as a fallback.
@interface TKExternalGameLibrary : NSObject
@property(nonatomic, readonly, strong, nullable) NSURL *access;
- (nullable NSDictionary<NSString *, NSString *> *)beginLaunch:(NSError **)error;
- (void)endLaunch;
@end

NS_ASSUME_NONNULL_END
