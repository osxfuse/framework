// ================================================================
// Copyright (c) 2007, Google Inc.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
// * Redistributions of source code must retain the above copyright
//   notice, this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above
//   copyright notice, this list of conditions and the following disclaimer
//   in the documentation and/or other materials provided with the
//   distribution.
// * Neither the name of Google Inc. nor the names of its
//   contributors may be used to endorse or promote products derived from
//   this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// ================================================================
//
//  GMDataBackedFileDelegate.m
//  MacFUSE
//
//  Created by ted on 1/5/08.
//
#import "GMDataBackedFileDelegate.h"

@implementation GMDataBackedFileDelegate

+ (GMDataBackedFileDelegate *)fileDelegateWithData:(NSData *)data {
  return [[[self alloc] initWithData:data] autorelease];
}

- (id)initWithData:(NSData *)data {
  if ((self = [super init])) {
    data_ = [data retain];
  }
  return self;
}

- (void)dealloc {
  [data_ release];
  [super dealloc];
}

- (NSData *)data {
  return data_;
}

- (int)readToBuffer:(char *)buffer 
               size:(size_t)size 
             offset:(off_t)offset 
              error:(NSError **)error {
  size_t len = [data_ length];
  if (offset > len) {
    return 0;  // No data to read.
  }
  if (offset + size > len) {
    size = len - offset;
  }
  NSRange range = NSMakeRange(offset, size);
  [data_ getBytes:buffer range:range];
  return size;
}

@end

@implementation GMMutableDataBackedFileDelegate

+ (GMMutableDataBackedFileDelegate *)fileDelegateWithData:(NSMutableData *)data {
  return [[[self alloc] initWithMutableData:data] autorelease];
}

- (id)initWithMutableData:(NSMutableData *)data {
  if ((self = [super initWithData:data])) {
  }
  return self;
}

- (int)writeFromBuffer:(const char *)buffer 
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error {
  // Take the lazy way out.  We just extend the NSData to be as large as needed
  // and then replace whatever bytes they want to write.
  NSMutableData* data = (NSMutableData*)[self data];
  if ([data length] < (offset + size)) {
    int bytesBeyond = (offset + size) - [data length];
    [(NSMutableData *)data increaseLengthBy:bytesBeyond];
  }
  NSRange range = NSMakeRange(offset, size);
  [data replaceBytesInRange:range withBytes:buffer];
  return size;
}

- (BOOL)truncateToOffset:(off_t)offset 
                   error:(NSError **)error {
  NSMutableData* data = (NSMutableData*)[self data];
  [data setLength:offset];
  return YES;
}

@end