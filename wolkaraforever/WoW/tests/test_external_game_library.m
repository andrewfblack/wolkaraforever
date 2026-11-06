#import <Foundation/Foundation.h>
#import "../launcher/WoW/ExternalGameLibrary.h"
#import "../launcher/WoW/ExternalGameRecord.h"
#include <assert.h>

// The record's defaults key, to put this test back as it found it.
static NSString *const RecordKey=@"WolkaraForever.ExternalGameRecordV1";

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    id previous=[defaults objectForKey:RecordKey];
    [defaults removeObjectForKey:RecordKey];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *relative=@"_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft";
    NSString *executable=[root stringByAppendingPathComponent:relative];
    assert([fm createDirectoryAtPath:executable.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"synthetic executable" writeToFile:executable atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    // No record: a launch fails closed and never falls back to Documents.
    NSError *error=nil;
    TKExternalGameLibrary *library=[TKExternalGameLibrary new];
    assert(![library beginLaunch:&error] && error);
    assert(library.access==nil);
    [library endLaunch];  // safe when nothing was acquired
    [library endLaunch];

    // A registered, present folder yields paths and holds one lease.
    error=nil;
    assert([TKExternalGameRecord registerRoot:[NSURL fileURLWithPath:root isDirectory:YES]
        executable:relative error:&error]);
    NSDictionary *paths=[library beginLaunch:&error];
    assert(paths && [paths[@"executable"] isEqual:executable]);
    assert([paths[@"workingDirectory"] isEqual:[root stringByAppendingPathComponent:@"_forever_"]]
        || [[paths[@"workingDirectory"] stringByResolvingSymlinksInPath]
            isEqual:[[root stringByAppendingPathComponent:@"_forever_"] stringByResolvingSymlinksInPath]]);
    assert(library.access!=nil);
    // Asking again while leased does not take a second lease or move the lease.
    NSURL *held=library.access;
    assert([library beginLaunch:&error]);
    assert(library.access==held);
    [library endLaunch];
    assert(library.access==nil);

    // The media disappears: the record survives, but launch fails closed.
    NSString *hidden=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm moveItemAtPath:root toPath:hidden error:NULL]);
    error=nil;
    assert([TKExternalGameRecord hasRecord]);
    assert(![library beginLaunch:&error] && error);
    assert(library.access==nil);
    assert([TKExternalGameRecord hasRecord]);
    assert([fm moveItemAtPath:hidden toPath:root error:NULL]);

    // And it works again after the card returns, with a fresh lease.
    error=nil;
    assert([library beginLaunch:&error]);
    assert(library.access!=nil);
    [library endLaunch];
    assert(library.access==nil);

    assert([fm removeItemAtPath:root error:NULL]);
    if (previous) [defaults setObject:previous forKey:RecordKey];
    else [defaults removeObjectForKey:RecordKey];
    puts("external game library PASS: fail closed, single lease, survives disconnected media");
} return 0; }
