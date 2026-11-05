#import "ExternalStorageProbe.h"
#include <sys/mount.h>

static NSString *const TKStorageBookmarkKey = @"WolkaraForever.ExternalStorageProbe.BookmarkV1";

static BOOL ProbeError(NSError **error, NSString *message) {
    if (error) *error=[NSError errorWithDomain:@"TKExternalStorageProbe" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

@implementation TKExternalStorageProbe

+ (BOOL)hasSelection {
    return [[NSUserDefaults.standardUserDefaults objectForKey:TKStorageBookmarkKey] isKindOfClass:NSData.class];
}

// Only metadata is read. In particular, this never enumerates, opens, creates,
// moves or deletes any of the contents of the selected folder.
+ (nullable NSDictionary<NSString *, id> *)readMetadataAtURL:(NSURL *)url error:(NSError **)error {
    NSNumber *directory=nil;
    if (![url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:error] || !directory.boolValue) {
        if (!error || !*error) ProbeError(error,@"Choose a folder, not a file.");
        return nil;
    }
    NSDictionary *capacity=[NSFileManager.defaultManager attributesOfFileSystemForPath:url.path error:error];
    if (!capacity) return nil;
    struct statfs volume;
    NSString *filesystem=statfs(url.fileSystemRepresentation,&volume)==0 ? @(volume.f_fstypename) : @"Unknown";
    return @{ @"name":url.lastPathComponent?:@"Folder",
              @"filesystem":filesystem,
              @"freeBytes":capacity[NSFileSystemFreeSize]?:@0 };
}

+ (BOOL)startAccessingFolder:(NSURL *)url error:(NSError **)error {
    if (!url.isFileURL || ![url startAccessingSecurityScopedResource]) {
        ProbeError(error,@"Folder access was not granted. Choose the folder again in Files.");
        return NO;
    }
    return YES;
}

+ (nullable NSDictionary<NSString *, id> *)inspectURL:(NSURL *)url error:(NSError **)error {
    if (![self startAccessingFolder:url error:error]) return nil;
    @try {
        return [self readMetadataAtURL:url error:error];
    } @finally {
        [url stopAccessingSecurityScopedResource];
    }
}

+ (nullable NSDictionary<NSString *, id> *)selectFolder:(NSURL *)url error:(NSError **)error {
    if (![self startAccessingFolder:url error:error]) return nil;
    @try {
        NSDictionary *result=[self readMetadataAtURL:url error:error];
        if (!result) return nil;
        // Store only a bookmark, never an absolute path. Do not replace a working
        // selection when a new folder cannot be bookmarked.
        NSData *bookmark=[url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:error];
        if (!bookmark) return nil;
        [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:TKStorageBookmarkKey];
        return result;
    } @finally {
        [url stopAccessingSecurityScopedResource];
    }
}

+ (nullable NSDictionary<NSString *, id> *)inspectSelectedFolder:(NSError **)error {
    NSData *bookmark=[NSUserDefaults.standardUserDefaults objectForKey:TKStorageBookmarkKey];
    if (![bookmark isKindOfClass:NSData.class]) {
        ProbeError(error,@"No folder selected yet."); return nil;
    }
    BOOL stale=NO;
    NSURL *url=[NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil
        bookmarkDataIsStale:&stale error:error];
    if (!url) {
        if (!error || !*error) ProbeError(error,@"The saved folder could not be opened. Choose it again in Files.");
        return nil;
    }
    if (stale) {
        ProbeError(error,@"Folder permission expired. Choose the folder again in Files."); return nil;
    }
    return [self inspectURL:url error:error];
}

@end
