#import "ExternalGameRecord.h"
#include <sys/stat.h>

static NSString *const TKExternalGameRecordKey=@"WolkaraForever.ExternalGameRecordV1";
static NSString *const TKGameFolder=@"World of Warcraft";

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

static NSDictionary *TKRecord(void) {
    id record=[NSUserDefaults.standardUserDefaults objectForKey:TKExternalGameRecordKey];
    return [record isKindOfClass:NSDictionary.class] ? record : nil;
}

static NSString *TKGameRoot(NSString *folderPath,NSString *rootRelative) {
    return rootRelative.length ? [folderPath stringByAppendingPathComponent:rootRelative] : folderPath;
}

@implementation TKExternalGameRecord
+ (BOOL)hasRecord {
    return TKRecord()!=nil && [TKRecord()[@"bookmark"] isKindOfClass:NSData.class];
}
+ (BOOL)hasExecutable {
    NSString *relative=self.recordedExecutable;
    return relative!=nil;
}
+ (nullable NSString *)recordedExecutable {
    NSString *relative=TKRecord()[@"executable"];
    return TKForeverExecutable(relative)?relative:nil;
}

// A pending install names a folder but no executable yet. The game root is
// reserved by refusing an existing folder of that name; nothing is written.
+ (BOOL)beginInstallInFolder:(NSURL *)folder error:(NSError **)error {
    if (!folder.isFileURL || ![folder startAccessingSecurityScopedResource]) {
        TKRecordError(error,@"The selected external folder is not accessible."); return NO;
    }
    @try {
        NSNumber *isDirectory=nil;
        if (![folder getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error] || !isDirectory.boolValue) {
            TKRecordError(error,@"External storage must be a folder."); return NO;
        }
        NSString *base=[folder.path stringByResolvingSymlinksInPath];
        NSString *root=[base stringByAppendingPathComponent:TKGameFolder];
        struct stat info;
        if (lstat(root.fileSystemRepresentation,&info)==0) {
            TKRecordError(error,@"The selected folder already contains World of Warcraft. It will not be replaced.");
            return NO;
        }
        NSData *bookmark=[folder bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:error];
        if (!bookmark) return NO;
        [NSUserDefaults.standardUserDefaults setObject:@{ @"bookmark":bookmark, @"root":TKGameFolder }
            forKey:TKExternalGameRecordKey];
        return YES;
    } @finally {
        [folder stopAccessingSecurityScopedResource];
    }
}

// Used by tests and a future installer: the folder itself is the game root.
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
        [NSUserDefaults.standardUserDefaults setObject:@{ @"bookmark":bookmark, @"root":@"", @"executable":relative }
            forKey:TKExternalGameRecordKey];
        return YES;
    } @finally {
        [root stopAccessingSecurityScopedResource];
    }
}

// After a verified download: record the executable so launches can resolve it.
+ (BOOL)attachExecutable:(NSString *)relative inFolder:(NSURL *)folder error:(NSError **)error {
    if (!TKForeverExecutable(relative)) {
        TKRecordError(error,@"The downloaded executable path is invalid."); return NO;
    }
    NSString *root=[self gameRootInFolder:folder.path error:error];
    if (!root || ![self validatedPathsInDirectory:root executable:relative error:error]) return NO;
    NSDictionary *record=TKRecord();
    if (!record) { TKRecordError(error,@"The external installation record is unavailable."); return NO; }
    NSMutableDictionary *updated=[record mutableCopy];
    updated[@"executable"]=relative;
    [NSUserDefaults.standardUserDefaults setObject:updated forKey:TKExternalGameRecordKey];
    return YES;
}

+ (nullable NSString *)gameRootInFolder:(NSString *)folderPath error:(NSError **)error {
    NSDictionary *record=TKRecord();
    if (!record) { TKRecordError(error,@"The external installation record is unavailable."); return nil; }
    if (![folderPath isKindOfClass:NSString.class] || !folderPath.isAbsolutePath) {
        TKRecordError(error,@"External game storage is unavailable."); return nil;
    }
    NSString *rootRelative=record[@"root"];
    if (rootRelative && (![rootRelative isKindOfClass:NSString.class] || !TKSafeRelative(rootRelative) ||
        [rootRelative containsString:@"/"])) {
        TKRecordError(error,@"The external installation record is invalid."); return nil;
    }
    NSString *root=TKGameRoot([folderPath stringByResolvingSymlinksInPath],rootRelative);
    return root;
}

// Installation access: the executable may not exist yet, but the bookmark and
// the selected folder must be reachable. A missing card never falls back.
+ (nullable NSURL *)beginInstallAccess:(NSError **)error {
    NSData *bookmark=TKRecord()[@"bookmark"];
    if (![bookmark isKindOfClass:NSData.class]) {
        TKRecordError(error,@"The external installation record is unavailable."); return nil;
    }
    BOOL stale=NO;
    NSURL *url=[NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:error];
    if (!url || stale || ![url startAccessingSecurityScopedResource]) {
        TKRecordError(error,@"External game storage is unavailable. Reconnect the card; no files were changed."); return nil;
    }
    NSNumber *isDirectory=nil;
    if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error] || !isDirectory.boolValue) {
        [url stopAccessingSecurityScopedResource];
        TKRecordError(error,@"External game storage is unavailable. Reconnect the card."); return nil;
    }
    return url;
}

+ (nullable NSURL *)beginAccess:(NSError **)error {
    NSURL *url=[self beginInstallAccess:error];
    if (!url) return nil;
    if (![self validatedPathsWithFolder:url error:error]) {
        [url stopAccessingSecurityScopedResource]; return nil;
    }
    return url;
}

+ (void)endAccess:(NSURL *)folder { [folder stopAccessingSecurityScopedResource]; }

+ (nullable NSDictionary<NSString *, NSString *> *)validatedPathsWithFolder:(NSURL *)folder error:(NSError **)error {
    NSString *root=[self gameRootInFolder:folder.path error:error];
    if (!root) return nil;
    NSString *relative=self.recordedExecutable;
    return [self validatedPathsInDirectory:root executable:relative error:error];
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
