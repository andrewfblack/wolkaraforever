#import <Foundation/Foundation.h>
#import "../launcher/WoW/ExternalGameRecord.h"
#include <assert.h>

static NSString *const Key=@"WolkaraForever.ExternalGameRecordV1";
static NSString *const Relative=@"_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft";

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    id previous=[defaults objectForKey:Key];
    [defaults removeObjectForKey:Key];
    NSFileManager *fm=NSFileManager.defaultManager;

    // Validation and path bounds, independent of the record.
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *executable=[root stringByAppendingPathComponent:Relative];
    assert([fm createDirectoryAtPath:executable.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"synthetic executable" writeToFile:executable atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSError *error=nil;
    NSDictionary *paths=[TKExternalGameRecord validatedPathsInDirectory:root executable:Relative error:&error];
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
    assert(![TKExternalGameRecord validatedPathsInDirectory:root executable:Relative error:&error] && error);
    assert([fm removeItemAtPath:root error:NULL]);
    error=nil;
    assert(![TKExternalGameRecord validatedPathsInDirectory:root executable:Relative error:&error] && error);
    assert([fm removeItemAtPath:outside error:NULL]);

    // A pending install reserves World of Warcraft without writing anything.
    NSString *card=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:card withIntermediateDirectories:YES attributes:nil error:NULL]);
    error=nil;
    assert([TKExternalGameRecord beginInstallInFolder:[NSURL fileURLWithPath:card isDirectory:YES] error:&error]);
    assert([TKExternalGameRecord hasRecord] && ![TKExternalGameRecord hasExecutable]);
    assert(![fm fileExistsAtPath:[card stringByAppendingPathComponent:@"World of Warcraft"]]);
    NSString *gameRoot=[TKExternalGameRecord gameRootInFolder:card error:&error];
    assert([gameRoot isEqual:[[card stringByResolvingSymlinksInPath]
        stringByAppendingPathComponent:@"World of Warcraft"]]);
    // Nothing to attach before the download: the record stays pending.
    error=nil;
    assert(![TKExternalGameRecord attachExecutable:Relative inFolder:[NSURL fileURLWithPath:card isDirectory:YES] error:&error] && error);
    assert([TKExternalGameRecord hasRecord] && ![TKExternalGameRecord hasExecutable]);

    // A completed download is attached and then resolves for launch.
    NSString *downloaded=[gameRoot stringByAppendingPathComponent:Relative];
    assert([fm createDirectoryAtPath:downloaded.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"downloaded executable" writeToFile:downloaded atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    error=nil;
    assert([TKExternalGameRecord attachExecutable:Relative inFolder:[NSURL fileURLWithPath:card isDirectory:YES] error:&error]);
    assert([TKExternalGameRecord hasExecutable]);
    error=nil;
    NSURL *lease=[TKExternalGameRecord beginAccess:&error];
    assert(lease);
    NSDictionary *launch=[TKExternalGameRecord validatedPathsWithFolder:lease error:&error];
    assert(launch && [launch[@"executable"] isEqual:downloaded] && [launch[@"root"] isEqual:gameRoot]);
    [TKExternalGameRecord endAccess:lease];

    // Refuse to take over an existing World of Warcraft folder.
    error=nil;
    assert(![TKExternalGameRecord beginInstallInFolder:[NSURL fileURLWithPath:card isDirectory:YES] error:&error] && error);

    // Disconnected: installation access fails but the record remains.
    NSString *hidden=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm moveItemAtPath:card toPath:hidden error:NULL]);
    error=nil;
    assert(![TKExternalGameRecord beginInstallAccess:&error] && error);
    assert([TKExternalGameRecord hasRecord] && [TKExternalGameRecord hasExecutable]);
    assert([fm moveItemAtPath:hidden toPath:card error:NULL]);
    error=nil;
    lease=[TKExternalGameRecord beginInstallAccess:&error];
    assert(lease);
    [TKExternalGameRecord endAccess:lease];
    assert([fm removeItemAtPath:card error:NULL]);

    if (previous) [defaults setObject:previous forKey:Key];
    else [defaults removeObjectForKey:Key];
    puts("external game record PASS: validated paths, traversal, symlink escape, pending install, attach and absent media");
} return 0; }
