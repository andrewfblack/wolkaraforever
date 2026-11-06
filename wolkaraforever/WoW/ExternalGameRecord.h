#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// An app-private, data-only description of a future external installation.
// The record is never removed when its volume is missing, and never contains
// an absolute path or a copy of any game file. No UI creates one yet.
@interface TKExternalGameRecord : NSObject
+ (BOOL)hasRecord;
+ (BOOL)registerRoot:(NSURL *)root executable:(NSString *)relative error:(NSError **)error;
+ (nullable NSURL *)beginAccess:(NSError **)error;
+ (void)endAccess:(NSURL *)folder;
+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsWithFolder:(NSURL *)folder
    error:(NSError **)error;
+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsInDirectory:(NSString *)directory
    executable:(NSString *)relative error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
