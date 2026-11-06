#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// An app-private, data-only description of an external game installation.
// The record is never removed when its volume is missing, contains no absolute
// path and copies no game file. A pending record (bookmark, no executable) is
// what an install action creates; it never marks an installation ready.
@interface TKExternalGameRecord : NSObject
+ (BOOL)hasRecord;
+ (BOOL)hasExecutable;
+ (nullable NSString *)recordedExecutable;
// Reserves `World of Warcraft` under the selected folder. Refuses an existing
// folder and writes nothing else.
+ (BOOL)beginInstallInFolder:(NSURL *)folder error:(NSError **)error;
// Tests and a future installer: the folder itself is the game root.
+ (BOOL)registerRoot:(NSURL *)root executable:(NSString *)relative error:(NSError **)error;
// Records the executable of a completed, verified download.
+ (BOOL)attachExecutable:(NSString *)relative inFolder:(NSURL *)folder error:(NSError **)error;
+ (nullable NSString *)gameRootInFolder:(NSString *)folderPath error:(NSError **)error;
// A lease for installation: the executable may not exist yet.
+ (nullable NSURL *)beginInstallAccess:(NSError **)error;
// A lease for launch: the executable and its folder must validate.
+ (nullable NSURL *)beginAccess:(NSError **)error;
+ (void)endAccess:(NSURL *)folder;
+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsWithFolder:(NSURL *)folder
    error:(NSError **)error;
+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsInDirectory:(NSString *)directory
    executable:(NSString *)relative error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
