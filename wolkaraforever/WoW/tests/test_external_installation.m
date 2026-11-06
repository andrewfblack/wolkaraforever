#import "../launcher/WoW/Installation.h"
#import "../launcher/WoW/Manifest.h"
#import "../launcher/WoW/ExternalGameRecord.h"
#include <assert.h>

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *key=@"WolkaraForever.ExternalGameRecordV1";
    id previous=[defaults objectForKey:key];
    [defaults removeObjectForKey:key];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *card=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:card withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSDictionary *product=@{@"id":@"wowf",@"folder":@"_forever_"};
    NSString *version=@"synthetic-1", *build=TKWoWMD5([@"build" dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *cdn=TKWoWMD5([@"cdn" dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *file=@"World of Warcraft.app/Contents/MacOS/World of Warcraft";
    NSData *bytes=[@"synthetic game executable" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *plan=@{@"product":@"wowf",@"locale":@"enUS",@"version":@{
        @"VersionsName":version,@"BuildConfig":build,@"CDNConfig":cdn},
        @"files":@[@{@"path":file,@"size":@(bytes.length),@"contentKey":TKWoWMD5(bytes)}]};
    NSError *error=nil;
    assert([TKExternalGameRecord beginInstallInFolder:[NSURL fileURLWithPath:card isDirectory:YES] error:&error]);
    TKWoWInstallation *state=TKWoWInspectExternalInstallation(product,plan);
    assert(state.state==TKWoWInstallationMissing && !state.app);

    NSString *root=[card stringByAppendingPathComponent:@"World of Warcraft"];
    NSString *exe=[[root stringByAppendingPathComponent:@"_forever_"] stringByAppendingPathComponent:file];
    assert([fm createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([bytes writeToFile:exe atomically:YES]);
    NSString *row=[NSString stringWithFormat:@"Product|Active|Build Key|CDN Key|Version|Tags\nwowf|1|%@|%@|%@|OSX arm64 EU enUS text?\n",build,cdn,version];
    assert([row writeToFile:[root stringByAppendingPathComponent:@".build.info"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    state=TKWoWInspectExternalInstallation(product,plan);
    assert(state.state==TKWoWInstallationReady && [TKExternalGameRecord hasExecutable]);
    assert(!state.app); // the library registers the verified executable separately

    NSString *hidden=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm moveItemAtPath:card toPath:hidden error:NULL]);
    state=TKWoWInspectExternalInstallation(product,plan);
    assert(state.state==TKWoWInstallationNeedsRepair && state.error && [TKExternalGameRecord hasRecord]);
    assert([fm moveItemAtPath:hidden toPath:card error:NULL]);
    state=TKWoWInspectExternalInstallation(product,plan);
    assert(state.state==TKWoWInstallationReady);

    assert([fm removeItemAtPath:card error:NULL]);
    if (previous) [defaults setObject:previous forKey:key];
    else [defaults removeObjectForKey:key];
    puts("external installation PASS: pending, verified, disconnected is not Missing, reconnect without download");
} return 0; }
