#import "HostBridge.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

// NSExtension is iOS SPI. This fixture is for sideloading, not App Store use.
// Keep its invocation isolated instead of linking a private framework into
// Tolkara's normal Developer-service app.
static NSMutableSet *TKActiveRequests;

void TKJITStartPreparation(NSData *pairing, void (^completion)(NSString *status)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ TKJITStartPreparation(pairing, completion); });
        return;
    }
    if (!pairing.length || pairing.length>65536 || !completion) return;
    NSURL *helperURL=[NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"JITHelperFixture.appex"];
    NSString *identifier=[NSBundle bundleWithURL:helperURL].bundleIdentifier;
    if (!identifier.length) { completion(@"The embedded helper was not found; JIT was not enabled."); return; }
    Class extension=NSClassFromString(@"NSExtension");
    if (!extension) {
        dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation",RTLD_NOW|RTLD_LOCAL);
        extension=NSClassFromString(@"NSExtension");
    }
    SEL factory=NSSelectorFromString(@"extensionWithIdentifier:error:");
    if (!extension || ![extension respondsToSelector:factory]) {
        completion(@"iPadOS did not provide the helper extension API; JIT was not enabled."); return;
    }
    NSError *error=nil;
    id request=((id (*)(Class,SEL,id,NSError **))objc_msgSend)(extension,factory,identifier,&error);
    if (!request) { completion(@"The helper could not be opened; JIT was not enabled."); return; }
    if (!TKActiveRequests) TKActiveRequests=[NSMutableSet new];
    [TKActiveRequests addObject:request];
    __weak id weakRequest=request;
    __block BOOL finished=NO;
    void (^finish)(NSString *)=^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) return;
            finished=YES;
            if (weakRequest) [TKActiveRequests removeObject:weakRequest];
            completion(message);
        });
    };
    SEL complete=NSSelectorFromString(@"setRequestCompletionBlock:");
    SEL cancel=NSSelectorFromString(@"setRequestCancellationBlock:");
    SEL interrupted=NSSelectorFromString(@"setRequestInterruptionBlock:");
    SEL begin=NSSelectorFromString(@"beginExtensionRequestWithInputItems:completion:");
    if (![request respondsToSelector:complete] || ![request respondsToSelector:cancel] ||
        ![request respondsToSelector:interrupted] || ![request respondsToSelector:begin]) {
        finish(@"The helper request API is unavailable; JIT was not enabled."); return;
    }
    ((void (*)(id,SEL,id))objc_msgSend)(request,complete,^(NSUUID *uuid,NSArray *items) {
        (void)uuid;
        NSString *status=[items.firstObject isKindOfClass:NSExtensionItem.class]?
            ((NSExtensionItem *)items.firstObject).userInfo[@"status"]:nil;
        finish([status isKindOfClass:NSString.class]?status:@"The helper returned no status; JIT was not enabled.");
    });
    ((void (*)(id,SEL,id))objc_msgSend)(request,cancel,^(NSUUID *uuid,NSError *reason) {
        (void)uuid;(void)reason; finish(@"The helper request was cancelled; JIT was not enabled.");
    });
    ((void (*)(id,SEL,id))objc_msgSend)(request,interrupted,^(NSUUID *uuid) {
        (void)uuid; finish(@"The helper request was interrupted; JIT was not enabled.");
    });
    NSExtensionItem *item=[NSExtensionItem new];
    item.userInfo=@{ @"operation":@"prepare", @"pairing":pairing };
    ((void (*)(id,SEL,id,id))objc_msgSend)(request,begin,@[item],^(NSUUID *uuid) {
        if (!uuid) finish(@"The helper did not start; JIT was not enabled.");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        finish(@"The helper did not respond within five minutes; JIT was not enabled.");
    });
}
