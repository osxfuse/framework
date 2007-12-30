//
//  GMAppleDouble.h
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

// Based on "AppleSingle/AppleDouble Formats for Foreign Files Developer's Note"
//
// Notes:
//  DoubleEntryFileDatesInfo
//    File creation, modification, backup, and access times as number of seconds 
//    before or after 12:00 AM Jan 1 2000 GMT as SInt32.
//  DoubleEntryFinderInfo
//    16 bytes of FinderInfo followed by 16 bytes of extended FinderInfo.
//    New FinderInfo should be zero'd out. For a directory, when the Finder 
//    encounters an entry with the init'd bit cleared, it will initialize the 
//    frView field of the to a value indicating how the contents of the
//    directory should be shown. Recommend to set frView to value of 256.
//  DoubleEntryMacFileInfo
//    This is a 32 bit flag that stores locked (bit 0) and protected (bit 1).
//
typedef enum {
  DoubleEntryInvalid = 0,
  DoubleEntryDataFork = 1,
  DoubleEntryResourceFork = 2,
  DoubleEntryRealName = 3,
  DoubleEntryComment = 4,
  DoubleEntryBlackAndWhiteIcon = 5,
  DoubleEntryColorIcon = 6,
  DoubleEntryFileDatesInfo = 8,  // See notes
  DoubleEntryFinderInfo = 9,     // See notes
  DoubleEntryMacFileInfo = 10,   // See notes
  DoubleEntryProDosFileInfo = 11,
  DoubleEntryMSDosFileinfo = 12,
  DoubleEntryShortName = 13,
  DoubleEntryAFPFileInfo = 14,
  DoubleEntryDirectoryID = 15,
} GMAppleDoubleEntryID;

@interface GMAppleDouble : NSObject {  
  NSMutableArray* entries_;
}
- (id)init;
- (void)dealloc;

// Adds an entry to the double file. The given data is retained.
- (void)addEntryWithID:(GMAppleDoubleEntryID)entryID data:(NSData *)data;

// Constructs and returns raw data for the double file.
- (NSData *)data;

@end
