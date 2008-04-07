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
//  GMFinderInfo.m
//  MacFUSE
//
//  Created by ted on 12/29/07.
//
#import "GMFinderInfo.h"

// All fields should be in network order. See CoreServices/CarbonCore/Finder.h
// for details on what flags and extendedFlags can be.
#pragma pack(push, 1)
typedef struct {
  union {
    struct {
      UInt32 type;
      UInt32 creator;
    } fileInfo;
    struct {
      UInt16 y1;  // Top left of window.
      UInt16 x1;
      UInt16 y2;  // Bottom right of window.
      UInt16 x2;
    } dirInfo;
  } fileOrDirInfo;
  UInt16 flags;  // Finder flags.
  struct {
    UInt16 y;
    UInt16 x;
  } location;
  UInt16 reserved;
} GenericFinderInfo;

typedef struct {
  UInt32 ignored0;
  UInt32 ignored1;
  UInt16 extendedFlags;  // Extended finder flags.
  UInt16 ignored3;
  UInt32 ignored4;
} GenericExtendedFinderInfo;

typedef struct {
  GenericFinderInfo base;
  GenericExtendedFinderInfo extended;
} PackedFinderInfo;
#pragma pack(pop)

@implementation GMFinderInfo

+ (NSData *)finderInfoWithFinderFlags:(UInt16)flags {
  return [GMFinderInfo finderInfoWithFinderFlags:flags
                                        typeCode:0
                                     creatorCode:0];
}

+ (NSData *)finderInfoWithFinderFlags:(UInt16)flags
                             typeCode:(OSType)typeCode
                          creatorCode:(OSType)creatorCode {
  PackedFinderInfo info;
  assert(sizeof(info) == 32);
  memset(&info, 0, sizeof(info));
  info.base.fileOrDirInfo.fileInfo.type = htonl(typeCode);
  info.base.fileOrDirInfo.fileInfo.creator = htonl(creatorCode);
  info.base.flags = htons(flags);
  return [NSData dataWithBytes:&info length:sizeof(info)];  
}

@end
