//
//  CoreWLANConfigurationBridge.m
//  mac-duo-status
//

#import <CoreWLAN/CoreWLAN.h>
#import <Foundation/Foundation.h>

int32_t DuoStatusCommitWiFiConfiguration(CWInterface *interface, CWConfiguration *configuration) {
    NSError *error = nil;
    BOOL committed = [interface commitConfiguration:configuration authorization:nil error:&error];
    return committed ? 0 : (int32_t)(error.code == 0 ? -3931 : error.code);
}
