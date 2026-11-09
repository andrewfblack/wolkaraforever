#import <Foundation/Foundation.h>

// Fixture-only bridge to the embedded helper. Calls never enable JIT on their
// own: "prepare" only checks readiness; "enable" attaches the helper to this
// process for the JIT test, after which the caller must run the self test.
void TKJITStartOperation(NSString *operation, NSData *pairing, int32_t targetPid,
                         void (^completion)(NSString *status));
// Synthetic gate using the product's own DebuggerArena path.
size_t TKJITSelfTest(char *out, size_t size);
