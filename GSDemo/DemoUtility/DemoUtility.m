//
//  DemoUtility.m
//  GSDemo
//
//  Created by DJI on 3/21/16.
//  Copyright © 2016 DJI. All rights reserved.
//

#import "DemoUtility.h"
#import <DJISDK/DJISDK.h>

inline void ShowMessage(NSString *title, NSString *message, NSString *state, id target, NSString *cancleBtnTitle)
{
    NSString *finalMessage = [NSString stringWithFormat:@"%@%@", message, state];
    dispatch_async(dispatch_get_main_queue(), ^{
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:finalMessage delegate:target cancelButtonTitle:cancleBtnTitle otherButtonTitles:nil];
        [alert show];
    });
}

@implementation DemoUtility

+(DJIFlightController*) fetchFlightController {
    if (![DJISDKManager product]) {
        return nil;
    }
    
    if ([[DJISDKManager product] isKindOfClass:[DJIAircraft class]]) {
        return ((DJIAircraft*)[DJISDKManager product]).flightController;
    }
    
    return nil;
}

@end
