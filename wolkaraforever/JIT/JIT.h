#import <Foundation/Foundation.h>
@class UIViewController;

NS_ASSUME_NONNULL_BEGIN

// Built-in StikJIT entry points for the sideloaded External-JIT launcher.
// These functions report preparation state and run the JIT helper embedded in
// this app. They do not change how Developer-service launches behave.

// Whether the app carries an eligible pairing file in
// Documents/StikJIT/pairingFile.plist.
BOOL TKBuiltInJITHasPairing(void);

// If this process is already prepared (CS_DEBUGGED set) calls
// completion(YES) without UI. Otherwise presents the import flow and runs
// the helper's prepare operation. Completion runs on the main queue.
void TKPrepareBuiltInJITIfNeeded(UIViewController *presenter,
                                 NSString *_Nullable appName,
                                 void (^completion)(BOOL prepared));

NS_ASSUME_NONNULL_END
