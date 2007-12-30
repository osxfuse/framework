//
//  NSData+BufferOffset.h
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (BufferOffset)

- (int)getBytes:(char *)buf size:(size_t)size offset:(off_t)offset;

- (int)readToBuffer:(char *)buffer 
               size:(size_t)size 
             offset:(off_t)offset 
              error:(NSError **)error;

@end
