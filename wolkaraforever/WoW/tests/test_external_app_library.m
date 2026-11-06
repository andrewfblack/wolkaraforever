#import <Foundation/Foundation.h>
#import "../launcher/App/AppLibrary.h"
#import "../launcher/WoW/ExternalGameRecord.h"
#include <assert.h>

static NSString *const RecordKey=@"WolkaraForever.ExternalGameRecordV1";
static NSString *const Relative=@"_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft";

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    id previous=[defaults objectForKey:RecordKey];
    [defaults removeObjectForKey:RecordKey];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *work=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *documents=[work stringByAppendingPathComponent:@"Documents"];
    NSString *storage=[work stringByAppendingPathComponent:@"Library"];
    NSString *card=[work stringByAppendingPathComponent:@"Card"];
    NSString *executable=[card stringByAppendingPathComponent:Relative];
    assert([fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([fm createDirectoryAtPath:storage withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([fm createDirectoryAtPath:executable.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"synthetic executable" writeToFile:executable atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    TKAppLibrary *library=[[TKAppLibrary alloc] initWithDocuments:documents storage:storage profiles:@[]];
    NSError *error=nil;
    // No bookmark: registration fails and no app appears.
    assert(![library registerExternalExecutable:Relative error:&error] && error);
    assert(library.apps.count==0);

    // The record is validated and then registered as an external app.
    error=nil;
    assert([TKExternalGameRecord registerRoot:[NSURL fileURLWithPath:card isDirectory:YES]
        executable:Relative error:&error]);
    TKApp *app=[library registerExternalExecutable:Relative error:&error];
    assert(app && app.source==TKAppSourceExternal && library.apps.count==1);
    error=nil;
    NSString *path=[library executablePathForApp:app error:&error];
    assert(path && [[path stringByResolvingSymlinksInPath] isEqual:[executable stringByResolvingSymlinksInPath]]);
    NSURL *leased=[TKExternalGameRecord beginAccess:&error];
    assert(leased);  // the app's own lookups do not consume the launch lease
    error=nil;
    NSString *directory=[library workingDirectoryForApp:app error:&error];
    assert(directory && [[directory stringByResolvingSymlinksInPath]
        isEqual:[[card stringByAppendingPathComponent:@"_forever_"] stringByResolvingSymlinksInPath]]);
    [TKExternalGameRecord endAccess:leased];
    // Registering the same validated executable again does not add a second row.
    error=nil;
    assert([library registerExternalExecutable:Relative error:&error] && library.apps.count==1);

    // The card disappears: the row survives, but paths fail closed with a reason.
    NSString *hidden=[work stringByAppendingPathComponent:@"Card-removed"];
    assert([fm moveItemAtPath:card toPath:hidden error:NULL]);
    error=nil;
    assert(![library executablePathForApp:app error:&error] && error);
    error=nil;
    assert(![library workingDirectoryForApp:app error:&error] && error);
    assert(library.apps.count==1);
    assert([TKExternalGameRecord hasRecord]);
    assert([fm moveItemAtPath:hidden toPath:card error:NULL]);
    error=nil;
    assert([library executablePathForApp:app error:&error]);

    // An on-disk record that points outside the external source is rejected.
    NSString *badStorage=[work stringByAppendingPathComponent:@"BadLibrary"];
    assert([fm createDirectoryAtPath:badStorage withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSDictionary *bad=@{@"format":@1,@"apps":@[@{@"id":NSUUID.UUID.UUIDString,@"name":@"Bad",
        @"source":@"external",@"executable":Relative,@"workingDirectory":@"Documents",@"added":@1}],
        @"dismissedProfiles":@[]};
    NSData *json=[NSJSONSerialization dataWithJSONObject:bad options:0 error:NULL];
    assert([json writeToFile:[badStorage stringByAppendingPathComponent:@"apps.json"] atomically:YES]);
    TKAppLibrary *rejected=[[TKAppLibrary alloc] initWithDocuments:documents storage:badStorage profiles:@[]];
    assert(rejected.apps.count==0);

    assert([fm removeItemAtPath:work error:NULL]);
    if (previous) [defaults setObject:previous forKey:RecordKey];
    else [defaults removeObjectForKey:RecordKey];
    puts("external app library PASS: registration, path resolution, one row, disconnect fails closed, bad record rejected");
} return 0; }
