#import "ExternalStorageProbe.h"
#include <sys/mount.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

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
    NSURL *url=[self beginSelectedFolderAccess:error];
    if (!url) return nil;
    @try { return [self readMetadataAtURL:url error:error]; }
    @finally { [self endSelectedFolderAccess:url]; }
}

+ (nullable NSURL *)beginSelectedFolderAccess:(NSError **)error {
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
    if (![self startAccessingFolder:url error:error]) return nil;
    return url;
}

+ (void)endSelectedFolderAccess:(NSURL *)folder {
    [folder stopAccessingSecurityScopedResource];
}

// The fixture has no relation to WoW's installation or updater directories.
// It uses the same APFS clone and atomic swap primitives as Updater.m, but
// never selects a pre-existing child for replacement or deletion.
+ (nullable NSDictionary<NSString *, id> *)testSelectedFolder:(NSError **)error {
    NSData *bookmark=[NSUserDefaults.standardUserDefaults objectForKey:TKStorageBookmarkKey];
    if (![bookmark isKindOfClass:NSData.class]) {
        ProbeError(error,@"No folder selected yet."); return nil;
    }
    BOOL stale=NO;
    NSURL *root=[NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil
        bookmarkDataIsStale:&stale error:error];
    if (!root || stale) {
        if (!error || !*error) ProbeError(error,@"The selected folder is unavailable. Choose it again in Files.");
        return nil;
    }
    if (![self startAccessingFolder:root error:error]) return nil;
    @try {
        NSDictionary *metadata=[self readMetadataAtURL:root error:error];
        if (!metadata) return nil;
        // mkdir is exclusive: neither an existing user folder nor a symlink
        // can ever become the fixture's test directory.
        NSString *name=[@".wolkaraforever-storage-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSString *folder=[root.path stringByAppendingPathComponent:name];
        if (mkdir(folder.fileSystemRepresentation,0700)!=0) {
            ProbeError(error,[NSString stringWithFormat:@"Could not create a disposable test folder (%s).",strerror(errno)]);
            return nil;
        }
        BOOL cloned=NO, swapped=NO;
        NSString *detail=nil;
        @try {
            NSString *source=[folder stringByAppendingPathComponent:@"original"];
            NSString *copy=[folder stringByAppendingPathComponent:@"private-copy"];
            const char *value="storage-probe-original";
            int fd=open(source.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
            if (fd<0 || write(fd,value,strlen(value))!=(ssize_t)strlen(value) || fsync(fd)!=0) {
                if (fd>=0) close(fd);
                detail=[NSString stringWithFormat:@"Cannot create or sync the test file (%s).",strerror(errno)];
            } else {
                close(fd);
                if (clonefile(source.fileSystemRepresentation,copy.fileSystemRepresentation,CLONE_NOFOLLOW)!=0)
                    detail=[NSString stringWithFormat:@"APFS clone failed (%s).",strerror(errno)];
                else {
                    cloned=YES;
                    NSData *original=[NSData dataWithContentsOfFile:source];
                    NSData *duplicate=[NSData dataWithContentsOfFile:copy];
                    if (![original isEqualToData:duplicate]) detail=@"The cloned test file differs from its source.";
                    else {
                        const char *changed="storage-probe-updated";
                        fd=open(copy.fileSystemRepresentation,O_WRONLY|O_TRUNC|O_NOFOLLOW);
                        if (fd<0 || write(fd,changed,strlen(changed))!=(ssize_t)strlen(changed) || fsync(fd)!=0) {
                            if (fd>=0) close(fd);
                            detail=[NSString stringWithFormat:@"Cannot update the private clone (%s).",strerror(errno)];
                        } else {
                            close(fd);
                            if (![[NSData dataWithContentsOfFile:source] isEqualToData:original])
                                detail=@"Updating the clone changed the original file.";
                            else if (renamex_np(source.fileSystemRepresentation,copy.fileSystemRepresentation,RENAME_SWAP)!=0)
                                detail=[NSString stringWithFormat:@"Atomic swap failed (%s).",strerror(errno)];
                            else {
                                swapped=YES;
                                NSData *active=[NSData dataWithContentsOfFile:source];
                                if (![active isEqualToData:[NSData dataWithBytes:changed length:strlen(changed)]])
                                    detail=@"Atomic swap did not activate the updated file.";
                            }
                        }
                    }
                }
            }
        } @finally {
            // Only the just-created folder is removed; never clean by name
            // from a previous run or touch a sibling in the selected folder.
            NSError *cleanup=nil;
            if (![NSFileManager.defaultManager removeItemAtPath:folder error:&cleanup])
                detail=[NSString stringWithFormat:@"Test folder cleanup failed: %@",cleanup.localizedDescription];
        }
        if (detail) {
            ProbeError(error,detail); return nil;
        }
        return @{ @"filesystem":metadata[@"filesystem"], @"clone":@(cloned), @"swap":@(swapped) };
    } @finally {
        [root stopAccessingSecurityScopedResource];
    }
}

@end
