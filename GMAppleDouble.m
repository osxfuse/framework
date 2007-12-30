//
//  GMAppleDouble.m
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//
#import "GMAppleDouble.h"

typedef struct {
  UInt32 magicNumber;      // Should be 0x00051607
  UInt32 versionNumber;    // Should be 0x00020000
  char filler[16];         // Zero-filled bytes.
  UInt16 numberOfEntries;  // Number of entries.
} __attribute__((packed)) DoubleHeader;

typedef struct {
  UInt32 entryID;  // Defines what entry is (0 is invalid)
  UInt32 offset;   // Offset from beginning of file to entry data.
  UInt32 length;   // Length of entry data in bytes.
} __attribute__((packed)) DoubleEntryHeader;

@interface GMAppleDoubleEntry : NSObject {
  UInt32 entryID_;
  NSData* data_;
}
- (id)initWithEntryID:(UInt32)entryID data:(NSData *)data;
- (void)dealloc;
- (UInt32)entryID;
- (NSData *)data;
@end

@implementation GMAppleDoubleEntry

+ (GMAppleDoubleEntry *)entryWithID:(UInt32)entryID data:(NSData *)data {
  return [[[GMAppleDoubleEntry alloc] 
           initWithEntryID:entryID data:data] autorelease];
}

- (id)initWithEntryID:(UInt32)entryID
                 data:(NSData *)data {
  if ((self = [super init])) {
    entryID_ = entryID;
    data_ = [data retain];
  }
  return self;
}

- (void)dealloc {
  [data_ release];
  [super dealloc];
}

- (UInt32)entryID {
  return entryID_;
}
- (NSData *)data {
  return data_;
}

@end

@implementation GMAppleDouble

+ (GMAppleDouble *)appleDouble {
  return [[[GMAppleDouble alloc] init] autorelease];
}

- (id)init {
  if ((self = [super init])) {
    entries_ = [[NSMutableArray alloc] init];
  }
  return self;  
}

- (void)dealloc {
  [entries_ release];
  [super dealloc];
}

- (void)addEntryWithID:(GMAppleDoubleEntryID)entryID data:(NSData *)data {
  [entries_ addObject:[GMAppleDoubleEntry entryWithID:entryID data:data]];
}

- (NSData *)data {
  NSMutableData* entryListData = [NSMutableData data];
  NSMutableData* entryData = [NSMutableData data];
  int dataStartOffset = 
    sizeof(DoubleHeader) + [entries_ count] * sizeof(DoubleEntryHeader);
  for (int i = 0; i < [entries_ count]; ++i) {
    GMAppleDoubleEntry* entry = [entries_ objectAtIndex:i];

    DoubleEntryHeader entryHeader;
    memset(&entryHeader, 0, sizeof(entryHeader));
    entryHeader.entryID = htonl([entry entryID]);
    entryHeader.offset = htonl(dataStartOffset + [entryData length]);
    entryHeader.length = htonl([[entry data] length]);
    [entryListData appendBytes:&entryHeader length:sizeof(entryHeader)];
    [entryData appendData:[entry data]];
  }
  
  NSMutableData* data = [NSMutableData data];

  DoubleHeader header;
  memset(&header, 0, sizeof(header));
  header.magicNumber = htonl(0x00051607);
  header.versionNumber = htonl(0x00020000);
  header.numberOfEntries = htons([entries_ count]);
  [data appendBytes:&header length:sizeof(header)];
  [data appendData:entryListData];
  [data appendData:entryData];
  return data;
}

@end
