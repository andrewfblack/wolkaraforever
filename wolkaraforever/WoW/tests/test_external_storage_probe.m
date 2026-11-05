#import <Foundation/Foundation.h>
#import "../launcher/WoW/ExternalStorageProbe.h"
#include <assert.h>

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *key=@"WolkaraForever.ExternalStorageProbe.BookmarkV1";
    id previous=[defaults objectForKey:key];
    [defaults removeObjectForKey:key];
    NSError *error=nil;
    assert(![TKExternalStorageProbe hasSelection]);
    assert(![TKExternalStorageProbe inspectSelectedFolder:&error]);
    assert(error && ![TKExternalStorageProbe hasSelection]);
    error=nil;
    assert(![TKExternalStorageProbe selectFolder:[NSURL URLWithString:@"https://example.invalid/folder"] error:&error]);
    assert(error && ![TKExternalStorageProbe hasSelection]);
    // A damaged bookmark cannot become an apparently available folder.
    [defaults setObject:[@"not a bookmark" dataUsingEncoding:NSUTF8StringEncoding] forKey:key];
    error=nil;
    assert(![TKExternalStorageProbe inspectSelectedFolder:&error]);
    assert(error && [TKExternalStorageProbe hasSelection]);
    if (previous) [defaults setObject:previous forKey:key];
    else [defaults removeObjectForKey:key];
    NSLog(@"external storage probe: missing and invalid selections fail closed");
} return 0; }
