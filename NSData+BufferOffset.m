//
//  NSData+BufferOffset.m
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//

#import "NSData+BufferOffset.h"

@implementation NSData (BufferOffset) 

- (int)getBytes:(char *)buf size:(size_t)size offset:(off_t)offset {
  size_t len = [self length];
  if (offset + size > len)
    size = len - offset;
  
  if (offset > len) {
    NSLog(@"read too many bytes %d > %d", offset, len);
    return 0;
  }
  
  NSRange range = NSMakeRange(offset, size);
  [self getBytes:buf range:range];
  return size;
}

- (int)readToBuffer:(char *)buffer 
               size:(size_t)size 
             offset:(off_t)offset 
              error:(NSError **)error {
  size_t len = [self length];
  if (offset + size > len) {
    size = len - offset;
  }
  if (offset > len) {
    return 0;
    // TODO:!
    //    *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
//    return -1;
  }
  
  NSRange range = NSMakeRange(offset, size);
  [self getBytes:buffer range:range];
  return size;
}


@end
