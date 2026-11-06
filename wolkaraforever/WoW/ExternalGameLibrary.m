#import "ExternalGameLibrary.h"
#import "ExternalGameRecord.h"

@implementation TKExternalGameLibrary {
    NSURL *_access;
}
- (NSURL *)access { return _access; }
- (nullable NSDictionary<NSString *, NSString *> *)beginLaunch:(NSError **)error {
    if (_access) return [TKExternalGameRecord validatedPathsWithFolder:_access error:error];
    NSURL *folder=[TKExternalGameRecord beginAccess:error];
    if (!folder) return nil;
    NSDictionary *paths=[TKExternalGameRecord validatedPathsWithFolder:folder error:error];
    if (!paths) { [TKExternalGameRecord endAccess:folder]; return nil; }
    _access=folder;
    return paths;
}
- (void)endLaunch {
    if (_access) [TKExternalGameRecord endAccess:_access];
    _access=nil;
}
- (void)dealloc { [self endLaunch]; }
@end
