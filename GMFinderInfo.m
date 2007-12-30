//
//  GMFinderInfo.m
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//
#import "GMFinderInfo.h"

// Taken from volicon.c
struct FndrGenericInfo {
  u_int32_t   ignored0;
  u_int32_t   ignored1;
  u_int16_t   flags;
  struct {
    int16_t ignored2;
    int16_t ignored3;
  } fdLocation;
  int16_t     ignored4;
} __attribute__((aligned(2), packed));
typedef struct FndrGenericInfo FndrGenericInfo;
#define XATTR_FINDERINFO_SIZE 32

@implementation GMFinderInfo

+ (NSData *)finderInfoWithFinderFlags:(UInt16)flags {
  char dataBytes[XATTR_FINDERINFO_SIZE];
  memset(dataBytes, 0, sizeof(dataBytes));
  ((struct FndrGenericInfo *)dataBytes)->flags |= htons(flags);
  return [NSData dataWithBytes:dataBytes length:XATTR_FINDERINFO_SIZE];  
}

@end
