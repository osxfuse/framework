//
//  GMResourceFork.m
//  MacFUSE
//
//  Created by ted on 12/29/07.
//  Copyright 2007 Google, Inc. All rights reserved.
//
// See the following URL for documentation on resource fork format:
//  http://developer.apple.com/documentation/mac/MoreToolbox/MoreToolbox-99.html
//
#import "GMResourceFork.h"

// The format for a resource fork is as follows ('+' means one-or-more):
//
// ResourceForkHeader
// {ResourceDataItem, <data_for_resource>}+
// ResourceMapHeader
// ResourceTypeListHeader
// ResourceTypeListItem+
// ResourceReferenceListItem+
// {ResourceNameListItem, <name_for_resource>}+
//
typedef struct {
  UInt32 resourceDataOffset;    // Offset from beginning to resource data.
  UInt32 resourceMapOffset;     // Offset from beginning to resource map.
  UInt32 resourceDataLength;    // Length of entire data segment in bytes.
  UInt32 resourceMapLength;     // Length of resource map in bytes.
} __attribute__((packed)) ResourceForkHeader;

typedef struct {
  UInt32 dataLength;  // Length of data that follows.
  // Followed by: variable length byte[] of data.
} __attribute__((packed)) ResourceDataItem;

typedef struct {
  // The next three fields should be zero'd out. It looks like they are reserved
  // for in-memory use by an entity loading the resource fork.
  char reservedForResourceForkHeader[sizeof(ResourceForkHeader)];
  UInt32 reservedForHandle;
  UInt16 reservedForFileReferenceNumber;
  
  SInt16 resourceForkAttributes;  // ResFileAttributes attribs of resource fork.
  UInt16 typeListOffset;  // Offset from beginning of map to resource type list.
  UInt16 nameListOffset;  // Offset from beginning of map to resource name list.
} __attribute__((packed)) ResourceMapHeader;

typedef struct {
  UInt16 numTypesMinusOne;  // Number of types in the map minus 1.
} __attribute__((packed)) ResourceTypeListHeader;

typedef struct {
  ResType type;        // FourCharCode resource type, i.e. 'icns'
  UInt16 numMinusOne;  // Number of resources of this type in map minus 1.
  UInt16 referenceListOffset;  // Offset from beginning of resource type list to 
                               // the reference list for this type.
} __attribute__((packed)) ResourceTypeListItem;

typedef struct {
  SInt16 resid;  // ResID type; resource ID
  SInt16 nameListOffset;  // Offset from beginning of resource name list to 
                          // resource name for this resource. A value of -1 is
                          // used when the resource does not have a name.
  UInt8 attributes;  // ResAttributes?: resource attributes.
  UInt8 resourceDataOffset1;  // These three bytes are the offset from beginning
  UInt8 resourceDataOffset2;  // of resource data to data for this resource.
  UInt8 resourceDataOffset3;  //  TODO: What endian order, etc?
  UInt32 reservedForHandleToResource;  // Reserved, zero out.
} __attribute__((packed)) ResourceReferenceListItem;

typedef struct {
  UInt8 nameLength;  // Length of name in bytes.
  // Followed by: variable length char[] for resource name.
} __attribute__((packed)) ResourceNameListItem;

@implementation GMResource

+ (GMResource *)resourceWithType:(ResType)resType
                           resID:(ResID)resID
                            name:(NSString *)name  // May be nil
                            data:(NSData *)data {
  return [[[GMResource alloc] 
           initWithType:resType resID:resID name:name data:data] autorelease];
}


- (id)initWithType:(ResType)resType
             resID:(ResID)resID 
              name:(NSString *)name
              data:(NSData *)data {
  if ((self = [super init])) {
    resType_ = resType;
    resID_ = resID;
    name_ = [name retain];
    data_ = [data retain];
  }
  return self;
}

- (void)dealloc {
  [name_ release];
  [data_ release];
  [super dealloc];
}

- (ResID)resID {
  return resID_;
}
- (ResType)resType {
  return resType_;
}
- (NSString *)name {
  return name_;
}
- (NSData *)data {
  return data_;
}

@end

@implementation GMResourceFork

+ (GMResourceFork *)resourceFork {
  return [[[GMResourceFork alloc] init] autorelease];
}

- (id)init {
  if ((self = [super init])) {
    resourcesByType_ = [[NSMutableDictionary alloc] init];
  }
  return self;    
}

- (void)dealloc {
  [resourcesByType_ release];
  [super dealloc];
}

// Add a new resource.
- (void)addResourceWithType:(ResType)resType
                      resID:(ResID)resID
                       name:(NSString *)name
                       data:(NSData *)data {
  GMResource* resource = [GMResource resourceWithType:resType
                                                resID:resID
                                                 name:name
                                                 data:data];
  [self addResource:resource];
}

- (void)addResource:(GMResource *)resource {
  ResType type = [resource resType];
  NSNumber* key = [NSNumber numberWithLong:type];
  NSMutableArray* resources = [resourcesByType_ objectForKey:key];
  if (resources == nil) {
    resources = [NSMutableArray array];
    [resourcesByType_ setObject:resources forKey:key];
  }
  [resources addObject:resource];
}


// Constructs the raw data for the resource fork containing all added resources.
- (NSData *)data {
  NSMutableData* resourceData = [NSMutableData data];
  NSMutableData* typeListData = [NSMutableData data];
  NSMutableData* referenceListData = [NSMutableData data];
  NSMutableData* nameListData = [NSMutableData data];

  NSArray* keys = [resourcesByType_ allKeys];
  int refListStartOffset = sizeof(ResourceTypeListHeader) + 
    ([keys count] * sizeof(ResourceTypeListItem));

  // For each resource type.
  for ( int i = 0; i < [keys count]; ++i ) {
    NSArray* resources = [resourcesByType_ objectForKey:[keys objectAtIndex:i]];

    // -- Append the ResourceTypeListItem to typeListData --
    ResourceTypeListItem typeItem;
    memset(&typeItem, 0, sizeof(typeItem));
    UInt16 refListOffset = refListStartOffset + [referenceListData length];
    ResType type = [[resources lastObject] resType];
    typeItem.type = htonl(type);
    typeItem.numMinusOne = htons([resources count] - 1);
    typeItem.referenceListOffset = htons(refListOffset);
    [typeListData appendBytes:&typeItem length:sizeof(typeItem)];
    
    // For each resource of that type.
    for ( int j = 0; j < [resources count]; ++j ) {
      GMResource* resource = [resources objectAtIndex:j];
      NSString* name = [resource name];
      
      // -- Append the ResourceReferenceListItem to referenceListData --
      ResourceReferenceListItem referenceItem;
      memset(&referenceItem, 0, sizeof(referenceItem));
      UInt32 dataOffset = [resourceData length];
      referenceItem.resid = htons([resource resID]);
      referenceItem.nameListOffset = 
        htons((name == nil) ? (SInt16)(-1) : [nameListData length]);
      referenceItem.attributes = 0;  // TODO: Support attributes?
      referenceItem.resourceDataOffset1 = (dataOffset & 0x00FF0000) >> 16;
      referenceItem.resourceDataOffset2 = (dataOffset & 0x0000FF00) >> 8;
      referenceItem.resourceDataOffset3 = (dataOffset & 0x000000FF);
      [referenceListData appendBytes:&referenceItem length:sizeof(referenceItem)];

      // -- Append the ResourceNameListItem and name data nameListData --
      if ([resource name] != nil) {
        ResourceNameListItem nameItem;
        memset(&nameItem, 0, sizeof(nameItem));
        NSString* name = [resource name];
        int nameLen = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];    
        nameItem.nameLength = nameLen;      
        [nameListData appendBytes:&nameItem length:sizeof(nameItem)];
        [nameListData appendBytes:[name UTF8String] length:nameLen];
      }

      // -- Append the ResourceDataItem and resource data to resourceData --
      ResourceDataItem dataItem;
      memset(&dataItem, 0, sizeof(dataItem));
      dataItem.dataLength = htonl([[resource data] length]);
      [resourceData appendBytes:&dataItem length:sizeof(dataItem)];
      [resourceData appendData:[resource data]];
    }
  }

  ResourceForkHeader forkHeader;
  memset(&forkHeader, 0, sizeof(forkHeader));
  ResourceMapHeader mapHeader;
  memset(&mapHeader, 0, sizeof(mapHeader));
  ResourceTypeListHeader typeListHeader;
  memset(&typeListHeader, 0, sizeof(typeListHeader));
  
  // It looks like OS X prefers the resource data to start at offset 256 bytes.
  UInt32 dataOffset = sizeof(forkHeader) > 256 ? sizeof(forkHeader) : 256;
  UInt32 dataLen = [resourceData length];
  UInt32 mapOffset = dataOffset + dataLen;
  UInt32 mapLen = sizeof(ResourceMapHeader) +
                  sizeof(ResourceTypeListHeader) +
                  [typeListData length] +
                  [referenceListData length] +
                  [nameListData length];

  forkHeader.resourceDataOffset = htonl(dataOffset);
  forkHeader.resourceMapOffset = htonl(mapOffset);
  forkHeader.resourceDataLength = htonl(dataLen);
  forkHeader.resourceMapLength = htonl(mapLen);
  
  mapHeader.resourceForkAttributes = htons(0);  // TODO: Support attributes?
  mapHeader.typeListOffset = htons(sizeof(mapHeader));
  mapHeader.nameListOffset = htons(sizeof(mapHeader) + 
                                   sizeof(ResourceTypeListHeader) +
                                   [typeListData length] +
                                   [referenceListData length]);
  
  typeListHeader.numTypesMinusOne = htons([resourcesByType_ count] - 1);

  NSMutableData* data = [NSMutableData data];  
  [data appendBytes:&forkHeader length:sizeof(forkHeader)];
  [data setLength:dataOffset];
  [data appendData:resourceData];
  [data appendBytes:&mapHeader length:sizeof(mapHeader)];
  [data appendBytes:&typeListHeader length:sizeof(typeListHeader)];
  [data appendData:typeListData];
  [data appendData:referenceListData];
  [data appendData:nameListData];
  
  return data;
}

@end
