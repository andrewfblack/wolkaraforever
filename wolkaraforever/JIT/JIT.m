#import "JIT.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <objc/message.h>
#include <stdio.h>
#include <sys/sysctl.h>

// Built-in StikJIT bridge. Uses the iOS private NSExtension API to start this
// app's own embedded extension by identifier — exactly what Husk does for its
// built-in helper. No other app's extension is started and no private URL
// scheme is used.

static Class TKExtensionClass;

static BOOL TKExtensionClassLoad(NSError **error) {
    if (TKExtensionClass) return YES;
    dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW | RTLD_LOCAL);
    TKExtensionClass = NSClassFromString(@"NSExtension");
    if (!TKExtensionClass) {
        if (error) *error = [NSError errorWithDomain:@"TKJIT" code:1
            userInfo:@{ NSLocalizedDescriptionKey: @"iPadOS did not provide the extension API for the JIT helper." }];
        return NO;
    }
    return YES;
}

// CS_DEBUGGED survives detach; P_TRACED is set only while attached. We want
// "prepared or in the hands of the helper", so read CS_DEBUGGED.
static BOOL TKMayRunUnsignedCode(void) {
    extern int csops(pid_t, unsigned int, void *, size_t);
    uint32_t flags = 0;
    if (csops(getpid(), 0 /* CS_OPS_STATUS */, &flags, sizeof flags)) return NO;
#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000
#endif
    return (flags & CS_DEBUGGED) != 0;
}

static NSString *TKJITDocumentsDirectory(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"StikJIT"];
}

static NSString *TKJITPairingPath(void) {
    return [TKJITDocumentsDirectory() stringByAppendingPathComponent:@"pairingFile.plist"];
}

BOOL TKBuiltInJITHasPairing(void) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:TKJITPairingPath() error:NULL];
    return attributes.fileSize > 0 && attributes.fileSize <= 65536;
}

// Shows an alert with a message and runs completion on dismissal.
static void TKJITPresentAlert(UIViewController *presenter, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message.length ? message : @"JIT could not be prepared. Report this in the app's diagnostics."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    if (presenter.viewLoaded && presenter.view.window) [presenter presentViewController:alert animated:YES completion:nil];
}

// One request to the helper extension. Completion lands on the main queue.
static void TKJITRequest(NSString *operation, void (^completion)(BOOL ok, NSString *message)) {
    NSError *error = nil;
    if (!TKExtensionClassLoad(&error)) { completion(NO, error.localizedDescription); return; }
    NSURL *appex = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"JITHelper.appex"];
    NSString *helperId = [NSBundle bundleWithURL:appex].bundleIdentifier;
    if (!helperId.length) { completion(NO, @"The JIT helper extension is missing from this app."); return; }
    SEL factory = NSSelectorFromString(@"extensionWithIdentifier:error:");
    NSMethodSignature *sig = [TKExtensionClass methodSignatureForSelector:factory];
    if (!sig) { completion(NO, @"iPadOS did not provide the extension API for the JIT helper."); return; }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
    [invocation setTarget:TKExtensionClass];
    [invocation setSelector:factory];
    [invocation setArgument:&helperId atIndex:2];
    [invocation setArgument:&error atIndex:3];
    [invocation invoke];
    id __unsafe_unretained helper = nil;
    [invocation getReturnValue:&helper];
    if (!helper) { completion(NO, error.localizedDescription ?: @"The JIT helper could not be loaded."); return; }
    NSExtensionItem *item = [NSExtensionItem new];
    NSData *pairing = [NSData dataWithContentsOfFile:TKJITPairingPath()];
    if (!pairing) { completion(NO, @"The pairing file is missing."); return; }
    item.userInfo = @{ @"operation": operation ?: @"enable",
                       @"pairing": pairing,
                       @"targetPid": @([NSProcessInfo processInfo].processIdentifier) };
    if (![helper respondsToSelector:NSSelectorFromString(@"setRequestCompletionBlock:")] ||
        ![helper respondsToSelector:NSSelectorFromString(@"setRequestCancellationBlock:")] ||
        ![helper respondsToSelector:NSSelectorFromString(@"setRequestInterruptionBlock:")] ||
        ![helper respondsToSelector:NSSelectorFromString(@"beginExtensionRequestWithInputItems:completion:")]) {
        completion(NO, @"The helper extension does not expose the request API.");
        return;
    }
    __block BOOL finished = NO;
    void (^finish)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) return;
            finished = YES;
            completion(ok, message);
        });
    };
    ((void (*)(id, SEL, id))objc_msgSend)(helper, complete, ^(NSUUID * _Nullable uuid, NSArray * _Nullable items) {
        (void)uuid;
        NSExtensionItem *reply = [items.firstObject isKindOfClass:NSExtensionItem.class] ? items.firstObject : nil;
        NSString *status = reply.userInfo[@"status"];
        finish([status isEqualToString:@"ready"], status.length ? status : @"The helper returned no status.");
    });
    ((void (*)(id, SEL, id))objc_msgSend)(helper, cancel, ^(NSUUID * _Nullable uuid, NSError * _Nullable err) {
        (void)uuid; (void)err;
        finish(NO, @"The helper request was cancelled.");
    });
    ((void (*)(id, SEL, id))objc_msgSend)(helper, interrupt, ^(NSUUID * _Nullable uuid) {
        (void)uuid;
        finish(NO, @"The helper request was interrupted.");
    });
    ((void (*)(id, SEL, id, id))objc_msgSend)(helper, begin, @[item], ^(NSUUID * _Nullable uuid) {
        if (!uuid) finish(NO, @"The helper could not start (is the app signed with get-task-allow?).");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        finish(NO, @"The helper did not respond within five minutes.");
    });
}

void TKPrepareBuiltInJITIfNeeded(UIViewController * _Nonnull presenter, NSString * _Nullable appName, void (^ _Nonnull completion)(BOOL prepared)) {
    if (TKMayRunUnsignedCode()) { completion(YES); return; }
    if (!TKBuiltInJITHasPairing()) {
        TKJITPresentAlert(presenter, @"JIT Setup Needed",
            @"WolkaraForever could not start JIT. Copy your pairing file into Files > On My iPad > WolkaraForever > StikJIT > pairingFile.plist (the file iloader creates), then tap Play again.");
        completion(NO);
        return;
    }
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Preparing JIT"
        message:[NSString stringWithFormat:@"Starting the JIT helper for %@…", appName.length ? appName : @"the app"] preferredStyle:UIAlertControllerStyleAlert];
    [(presenter.viewLoaded && presenter.view.window ? presenter : nil) ?: UIApplication.sharedApplication.keyWindow.rootViewController
        presentViewController:progress animated:YES completion:nil];
    TKJITRequest(@"enable", ^(BOOL ok, NSString *message) {
        [progress dismissViewControllerAnimated:YES completion:^{
            if (!ok) TKJITPresentAlert(presenter, @"JIT Not Prepared", message);
            completion(ok);
        }];
    });
}
