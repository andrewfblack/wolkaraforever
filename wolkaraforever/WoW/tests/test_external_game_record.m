#import <Foundation/Foundation.h>
#import "../launcher/WoW/ExternalGameRecord.h"
#include <assert.h>

int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *relative=@"_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft";
    NSString *executable=[root stringByAppendingPathComponent:relative];
    assert([fm createDirectoryAtPath:executable.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"synthetic executable" writeToFile:executable atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSError *error=nil;
    NSDictionary *paths=[TKExternalGameRecord validatedPathsInDirectory:root executable:relative error:&error];
    assert(paths && [paths[@"executable"] isEqual:executable]);
    for (NSString *bad in @[@"../escape.app/Contents/MacOS/World of Warcraft",
        @"_forever_/../../Escape.app/Contents/MacOS/World of Warcraft",
        @"/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft"]) {
        error=nil;
        assert(![TKExternalGameRecord validatedPathsInDirectory:root executable:bad error:&error] && error);
    }
    NSString *game=[root stringByAppendingPathComponent:@"_forever_"];
    NSString *outside=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([fm moveItemAtPath:game toPath:[outside stringByAppendingPathComponent:@"game"] error:NULL]);
    assert([fm createSymbolicLinkAtPath:game withDestinationPath:[outside stringByAppendingPathComponent:@"game"] error:NULL]);
    error=nil;
    assert(![TKExternalGameRecord validatedPathsInDirectory:root executable:relative error:&error] && error);
    assert([fm removeItemAtPath:root error:NULL]);
    error=nil;
    assert(![TKExternalGameRecord validatedPathsInDirectory:root executable:relative error:&error] && error);
    assert([fm removeItemAtPath:outside error:NULL]);
    puts("external game record PASS: validated paths, traversal, symlink escape and absent media");
} return 0; }
