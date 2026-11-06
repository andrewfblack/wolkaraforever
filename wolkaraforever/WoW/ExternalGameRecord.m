#import "ExternalGameRecord.h"
#include <sys/stat.h>

static NSString *const TKExternalGameRecordKey=@"WolkaraForever.ExternalGameRecordV1";

static void TKRecordError(NSError **error,NSString *reason) {
    if (error) *error=[NSError errorWithDomain:@"TKExternalGameRecord" code:1
        userInfo:@{NSLocalizedDescriptionKey:reason}];
}

static BOOL TKSafeRelative(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length || value.length>4096 || value.isAbsolutePath) return NO;
    for (NSString *part in [value componentsSeparatedByString:@"/"])
        if (!part.length || [part isEqual:@"."] || [part isEqual:@".."] || [part containsString:@":"]) return NO;
    return YES;
}

static BOOL TKForeverExecutable(NSString *relative) {
    return TKSafeRelative(relative) && [relative hasPrefix:@"_forever_/"] &&
        [relative hasSuffix:@".app/Contents/MacOS/World of Warcraft"];
}

@implementation TKExternalGameRecord
+ (BOOL)hasRecord {
    return [[NSUserDefaults.standardUserDefaults objectForKey:TKExternalGameRecordKey] isKindOfClass:NSDictionary.class];
}
+ (nullable NSString *)recordedExecutable {
    NSDictionary *record=[NSUserDefaults.standardUserDefaults objectForKey:TKExternalGameRecordKey];
    NSString *relative=[record isKindOfClass:NSDictionary.class] ? record[@"executable"] : nil;
    return TKForeverExecutable(relative)?relative:nil;
}

+ (BOOL)registerRoot:(NSURL *)root executable:(NSString *)relative error:(NSError **)error {
    if (!root.isFileURL || ![root startAccessingSecurityScopedResource]) {
        TKRecordError(error,@"External storage is not accessible."); return NO;
    }
    @try {
        NSNumber *isDirectory=nil;
        if (![root getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error] || !isDirectory.boolValue) {
            TKRecordError(error,@"External storage is not a folder."); return NO;
        }
        if (![self validatedPathsInDirectory:root.path executable:relative error:error]) return NO;
        NSData *bookmark=[root bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:error];
        if (!bookmark) return NO;
        [NSUserDefaults.standardUserDefaults setObject:@{ @"bookmark":bookmark, @"executable":relative }
            forKey:TKExternalGameRecordKey];
        return YES;
    } @finally {
        [root stopAccessingSecurityScopedResource];
    }
}

+ (nullable NSURL *)beginAccess:(NSError **)error {
    id record=[NSUserDefaults.standardUserDefaults objectForKey:TKExternalGameRecordKey];
    NSData *bookmark=[record isKindOfClass:NSDictionary.class] ? record[@"bookmark"] : nil;
    if (![bookmark isKindOfClass:NSData.class]) {
        TKRecordError(error,@"The external installation record is unavailable."); return nil;
    }
    BOOL stale=NO;
    NSURL *url=[NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:error];
    if (!url || stale || ![url startAccessingSecurityScopedResource]) {
        TKRecordError(error,@"External game storage is unavailable. Reconnect the card; no files were changed."); return nil;
    }
    if (![self validatedPathsWithFolder:url error:error]) {
        [url stopAccessingSecurityScopedResource]; return nil;
    }
    return url;
}

+ (void)endAccess:(NSURL *)folder { [folder stopAccessingSecurityScopedResource]; }

+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsWithFolder:(NSURL *)folder error:(NSError **)error {
    id record=[NSUserDefaults.standardUserDefaults objectForKey:TKExternalGameRecordKey];
    NSString *relative=[record isKindOfClass:NSDictionary.class] ? record[@"executable"] : nil;
    return [self validatedPathsInDirectory:folder.path executable:relative error:error];
}

+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsInDirectory:(NSString *)directory
    executable:(NSString *)relative error:(NSError **)error {
    if (!TKForeverExecutable(relative) ||
        ![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath) {
        TKRecordError(error,@"The external installation record is invalid. No files were changed."); return nil;
    }
    struct stat rootInfo;
    if (lstat(directory.fileSystemRepresentation,&rootInfo) || !S_ISDIR(rootInfo.st_mode)) {
        TKRecordError(error,@"External game storage is unavailable. Reconnect the card."); return nil;
    }
    NSString *base=[directory stringByResolvingSymlinksInPath];
    NSString *game=[base stringByAppendingPathComponent:@"_forever_"];
    NSString *executable=[base stringByAppendingPathComponent:relative];
    struct stat gameInfo,exeInfo;
    if (lstat(game.fileSystemRepresentation,&gameInfo) || !S_ISDIR(gameInfo.st_mode) ||
        lstat(executable.fileSystemRepresentation,&exeInfo) || !S_ISREG(exeInfo.st_mode) ||
        ![[game stringByResolvingSymlinksInPath] isEqual:game] ||
        ![[executable stringByResolvingSymlinksInPath] isEqual:executable]) {
        TKRecordError(error,@"External game files are unavailable. Reconnect the card; no files were changed."); return nil;
    }
    return @{ @"root":base, @"workingDirectory":game, @"executable":executable };
}
@end
