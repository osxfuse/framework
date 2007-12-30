//
//  GMFinderInfo.h
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GMFinderInfo : NSObject {
}

+ (NSData *)finderInfoWithFinderFlags:(UInt16)flags;

@end
