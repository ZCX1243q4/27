//
//  iOSTweaksToolbox-Bridging-Header.h
//

#ifndef iOSTweaksToolbox_Bridging_Header_h
#define iOSTweaksToolbox_Bridging_Header_h

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "Exploits/worse_query.h"
#import "Exploits/pathleak.h"

typedef struct CF_BRIDGED_TYPE(id) __SecTask *SecTaskRef;

SecTaskRef _Nullable SecTaskCreateFromSelf(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;
CFTypeRef _Nullable SecTaskCopyValueForEntitlement(SecTaskRef _Nonnull task,
                                                   CFStringRef _Nonnull entitlement,
                                                   CFErrorRef _Nullable * _Nullable error) CF_RETURNS_RETAINED;

#endif /* iOSTweaksToolbox_Bridging_Header_h */
