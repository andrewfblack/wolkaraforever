#import <Foundation/Foundation.h>

// Fixture-only: requests DDI preparation, never an attachment or guest entry.
void TKJITStartPreparation(NSData *pairing, void (^completion)(NSString *status));
