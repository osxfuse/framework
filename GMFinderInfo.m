//
//  GMFinderInfo.m
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
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
  PackedFinderInfo info;
  assert(sizeof(info) == 32);
  memset(&info, 0, sizeof(info));
  info.base.flags = htons(flags);
  return [NSData dataWithBytes:&info length:sizeof(info)];
}

@end
