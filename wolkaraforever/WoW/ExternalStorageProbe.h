#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Read-only folder probe. No game path is changed by selecting a folder.
// A nil result means that the selection is missing, inaccessible or stale.
@interface TKExternalStorageProbe : NSObject
+ (BOOL)hasSelection;
+ (nullable NSDictionary<NSString *, id> *)inspectSelectedFolder:(NSError **)error;
+ (nullable NSDictionary<NSString *, id> *)selectFolder:(NSURL *)url error:(NSError **)error;
// Explicitly requested test. Writes only to a newly created, uniquely named
// child of the selected folder, then removes that child if it still owns it.
+ (nullable NSDictionary<NSString *, id> *)testSelectedFolder:(NSError **)error;
// Internal-only access lease for the saved folder. No install action uses this
// yet; the holder must release it after the entire file operation or session.
+ (nullable NSURL *)beginSelectedFolderAccess:(NSError **)error;
+ (void)endSelectedFolderAccess:(NSURL *)folder;
@end

NS_ASSUME_NONNULL_END
