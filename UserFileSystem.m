//
//  UserFileSystem.m
//
//  Created by ted on 12/29/07.
//  Based on FUSEFileSystem originally by alcor.
//  Copyright 2007 Google. All rights reserved.
//

#import "UserFileSystem.h"

#define FUSE_USE_VERSION 26
#include <fuse.h>

#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/mount.h>

#import <Foundation/Foundation.h>
#import "GMAppleDouble.h"
#import "GMFinderInfo.h"
#import "GMResourceFork.h"
#import "NSData+BufferOffset.h"

#define kFinderInfoXAttr   @"com.apple.FinderInfo"
#define kResourceForkXattr @"com.apple.ResourceFork"

@interface UserFileSystem (UserFileSystemPrivate)

+ (UserFileSystem *)currentFS;

- (void)mount:(NSDictionary *)args;

// Determines whether the given path is a for a resource managed by 
// UserFileSystem, such as a custom icon for a file. The optional
// "type" param is set to the type of the managed resource. The optional
// "dataPath" param is set to the file that represents this resource. For
// example, for a custom icon resource fork, this would be the corresponding 
// data fork. For a custom directory icon, this would be the directory itself.
- (BOOL)isManagedResourceAtPath:(NSString *)path type:(NSString **)type
                       dataPath:(NSString **)dataPath;

- (NSData *)managedContentsForPath:(NSString *)path;

- (BOOL)fillStatBuffer:(struct stat *)stbuf 
               forPath:(NSString *)path
                 error:(NSError **)error;
- (BOOL)fillStatvfsBuffer:(struct statvfs *)stbuf 
                  forPath:(NSString *)path
                    error:(NSError **)error;

- (void)fuseInit;
- (void)fuseDestroy;

@end

@implementation UserFileSystem

- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe {
  if ((self = [super init])) {
    isMounted_ = NO;
    isThreadSafe_ = isThreadSafe;
    delegate_ = delegate;
  }
  return self;
}

- (void)dealloc {
  [mountPath_ release];
  [super dealloc];
}

- (void)setDelegate:(id)delegate {
  delegate_ = delegate;
}
- (id)delegate {
  return delegate_;
}

- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options {
  [self mountAtPath:mountPath
        withOptions:options
   shouldForeground:YES
    detachNewThread:YES];   
}

- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options
   shouldForeground:(BOOL)shouldForeground
    detachNewThread:(BOOL)detachNewThread {
  NSDictionary* args = 
  [[NSDictionary alloc] initWithObjectsAndKeys:
   mountPath, @"mountPath",
   options, @"options",
   [NSNumber numberWithBool:shouldForeground], @"shouldForeground", 
   nil, nil];
  if (detachNewThread) {
    [NSThread detachNewThreadSelector:@selector(mount:) 
                             toTarget:self 
                           withObject:args];
  } else {
    [self mount:args];
  }
}

- (void)umount {
  if ([delegate_ respondsToSelector:@selector(willUmount)]) {
    [delegate_ willUmount];
  }
  NSArray* args = [NSArray arrayWithObjects:@"-v", mountPath_, nil];
  NSTask *unmountTask = [NSTask launchedTaskWithLaunchPath:@"/sbin/umount" 
                                                 arguments:args];
  [unmountTask waitUntilExit];
}

+ (NSError *)errorWithCode:(int)code {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

+ (UserFileSystem *)currentFS {
  struct fuse_context* context = fuse_get_context();
  assert(context);
  return (UserFileSystem *)context->private_data;
}

- (void)fuseInit {    
  isMounted_ = YES;
  
  // TODO: The mount point won't actually show up until this winds its way
  // back through the kernel after this routine returns.
  if ([delegate_ respondsToSelector:@selector(didMount)]) {
    [delegate_ didMount]; 
  }
}

- (void)fuseDestroy {
  isMounted_ = NO;
  if ([delegate_ respondsToSelector:@selector(didUmount)]) {
    [delegate_ didUmount];
  }
}

#pragma mark Finder Info, Resource Forks and HFS headers

- (BOOL)usesResourceForks{
  return ([delegate_ respondsToSelector:@selector(finderFlagsForPath:)] ||
          [delegate_ respondsToSelector:@selector(iconDataForPath:)] ||
          [delegate_ respondsToSelector:@selector(URLContentOfWeblocAtPath:)]);
}

- (UInt16)finderFlagsForPath:(NSString *)path {
  UInt16 flags = 0;
  if ([delegate_ respondsToSelector:@selector(finderFlagsForPath:)]) {
    return [delegate_ finderFlagsForPath:path];
  } else if ([delegate_ respondsToSelector:@selector(iconDataForPath:)] &&
             [delegate_ iconDataForPath:path] != nil) {
    flags |= kHasCustomIcon;
  }
  return flags;
}

- (BOOL)hasCustomIconAtPath:(NSString *)path {
  UInt16 flags = [self finderFlagsForPath:path];
  return (flags & kHasCustomIcon);
}

- (NSData *)resourceForkContentsForPath:(NSString *)path {
  NSURL* url = nil;
  if ([path hasSuffix:@".webloc"] &&
       [delegate_ respondsToSelector:@selector(URLContentOfWeblocAtPath:)]) {
    url = [delegate_ URLContentOfWeblocAtPath:path];
  }
  NSData* imageData = nil;
  if ([delegate_ respondsToSelector:@selector(iconDataForPath:)]) {
    imageData = [delegate_ iconDataForPath:path];
  }
  if (imageData || url) {
    GMResourceFork* fork = [GMResourceFork resourceFork];
    if (imageData) {
      [fork addResourceWithType:'icns'
                          resID:kCustomIconResource // -16455
                           name:nil
                           data:imageData];
    }
    if (url) {
      NSString* urlString = [url absoluteString];
      NSData* data = [urlString dataUsingEncoding:NSUTF8StringEncoding];
      [fork addResourceWithType:'url '
                          resID:256
                           name:nil
                           data:data];
    }
    return [fork data];
  }
  return nil;
}

// Determines whether the given path is a for a resource managed by 
// UserFileSystem, such as a custom icon for a file. The optional
// "type" param is set to the type of the managed resource. The optional
// "dataPath" param is set to the file that represents this resource. For
// example, for a custom icon resource fork, this would be the corresponding 
// data fork. For a custom directory icon, this would be the directory itself.
NSString* const FUSEManagedDirectoryIconFile = @"FUSEManagedDirectoryIconFile";
NSString* const FUSEManagedDirectoryIconResource = @"FUSEManagedDirectoryIconResource";
NSString* const FUSEManagedFileResource = @"FUSEMangedFileResource";
NSString* const FUSEManagedDirectoryResource = @"FUSEManagedDirectoryResource";
- (BOOL)isManagedResourceAtPath:(NSString *)path
                           type:(NSString **)type
                       dataPath:(NSString **)dataPath {
  if (![self usesResourceForks]) {
    return NO;
  }
  NSString* parentDir = [path stringByDeletingLastPathComponent];
  NSString* name = [path lastPathComponent];
  if ([name isEqualToString:@"Icon\r"]) {
    if (type) {
      *type = FUSEManagedDirectoryIconFile;
    }
    if (dataPath) {
      *dataPath = parentDir;
    }
    return YES;
  } else if ([name isEqualToString:@"._Icon\r"]) {
    if (type) {
      *type = FUSEManagedDirectoryIconResource;
    }
    if (dataPath) {
      *dataPath = parentDir;
    }
    return YES;
  } else if ([name hasPrefix:@"._"]) {
    if (type || dataPath) {
      // Since this is a request for a resource fork, we fix up the path to 
      // refer the data fork.
      name = [name substringFromIndex:2];
      NSString* dp = [parentDir stringByAppendingPathComponent:name];
      if (type) {
        BOOL isDirectory = NO; // Default to NO
        [self fileExistsAtPath:dp isDirectory:&isDirectory];
        if (isDirectory) {
          *type = FUSEManagedDirectoryResource;
        } else {
          *type = FUSEManagedFileResource;
        }
      }
      if (dataPath) {
        *dataPath = dp;
      }
    }
    return YES;
  }
  return NO;
}

- (NSData *)managedContentsForPath:(NSString *)path {
  NSString* dataPath = path;  // Default to the given path.
  NSString* type = nil;
  BOOL isManagedResource = 
  [self isManagedResourceAtPath:path type:&type dataPath:&dataPath];
  if (!isManagedResource) {
    return nil;
  }
  
  if ([type isEqualToString:FUSEManagedDirectoryIconFile]) {
    return nil;  // The Icon\r file contains no data.
  }
  
  int flags = [self finderFlagsForPath:dataPath];
  BOOL includeResource = YES;
  if ([type isEqualToString:FUSEManagedDirectoryIconResource]) {
    flags |= kIsInvisible;
    includeResource = YES;
  } else if ([type isEqualToString:FUSEManagedFileResource]) {
    includeResource = YES;
  } else if ([type isEqualToString:FUSEManagedDirectoryResource]) {
    includeResource = NO;
  } else {
    NSLog(@"Unknown managed file type: %@", type);
    return nil;
  }
  
  NSData* finderInfo = [GMFinderInfo finderInfoWithFinderFlags:flags];
  GMAppleDouble* doubleFile = [GMAppleDouble appleDouble];
  [doubleFile addEntryWithID:DoubleEntryFinderInfo data:finderInfo];
  if (includeResource) {
    [doubleFile addEntryWithID:DoubleEntryResourceFork 
                          data:[self resourceForkContentsForPath:dataPath]];
  }
  return [doubleFile data];
}


#pragma mark Advanced File Operations

- (BOOL)fillStatvfsBuffer:(struct statvfs *)stbuf 
                  forPath:(NSString *)path 
                    error:(NSError **)error {
  NSDictionary* attributes = [self attributesOfFileSystemForPath:path error:error];
  if (!attributes) {
    return NO;
  }
  
  // Maximum length of filenames
  // TODO: Create our own key so that a fileSystem can override this.
  stbuf->f_namemax = 255;
  
  // Block size
  // TODO: Create our own key so that a fileSystem can override this.
  stbuf->f_bsize = stbuf->f_frsize = 4096;
  
  // Size in blocks
  NSNumber* size = [attributes objectForKey:NSFileSystemSize];
  assert(size);
  stbuf->f_blocks = (fsblkcnt_t)([size longLongValue] / stbuf->f_frsize);
  
  // Number of free / available blocks
  NSNumber* freeSize = [attributes objectForKey:NSFileSystemFreeSize];
  assert(freeSize);
  stbuf->f_bfree = stbuf->f_bavail = 
    (fsblkcnt_t)([freeSize longLongValue] / stbuf->f_frsize);
  
  // Number of nodes
  NSNumber* numNodes = [attributes objectForKey:NSFileSystemNodes];
  assert(numNodes);
  stbuf->f_files = (fsfilcnt_t)[numNodes longLongValue];
  
  // Number of free / available nodes
  NSNumber* freeNodes = [attributes objectForKey:NSFileSystemFreeNodes];
  assert(freeNodes);
  stbuf->f_ffree = stbuf->f_favail = (fsfilcnt_t)[freeNodes longLongValue];
  
  return YES;
}

- (BOOL)fillStatBuffer:(struct stat *)stbuf 
               forPath:(NSString *)path 
                 error:(NSError **)error {
  NSDictionary* attributes = [self attributesOfItemAtPath:path error:error];
  if (!attributes) {
    return NO;
  }
  
  // Permissions (mode)
  NSNumber* perm = [attributes objectForKey:NSFilePosixPermissions];
  stbuf->st_mode = [perm longValue];
  NSString* fileType = [attributes objectForKey:NSFileType];
  if ([fileType isEqualToString:NSFileTypeDirectory ]) {
    stbuf->st_mode |= S_IFDIR;
  } else if ([fileType isEqualToString:NSFileTypeRegular]) {
    stbuf->st_mode |= S_IFREG;
  } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
    stbuf->st_mode |= S_IFLNK;
  } else {
    *error = [UserFileSystem errorWithCode:EFTYPE];
    NSLog(@"Illegal file type: '%@' at path '%@'", fileType, path);
    return NO;
  }
  
  // Owner and Group
  // Note that if the owner or group IDs are not specified, the effective
  // user and group IDs for the current process are used as defaults.
  NSNumber* uid = [attributes objectForKey:NSFileOwnerAccountID];
  NSNumber* gid = [attributes objectForKey:NSFileGroupOwnerAccountID];
  stbuf->st_uid = uid ? [uid longValue] : geteuid();
  stbuf->st_gid = gid ? [gid longValue] : getegid();

  // nlink
  NSNumber* nlink = [attributes objectForKey:NSFileReferenceCount];
  stbuf->st_nlink = [nlink longValue];
      
  // TODO: For the timespec, there is a .tv_nsec (= nanosecond) part as well.
  // Since the NSDate returns a double, we can fill this in as well.

  // mtime, atime
  NSDate* mdate = [attributes objectForKey:NSFileModificationDate];
  if (mdate) {
    time_t t = (time_t) [mdate timeIntervalSince1970];
    stbuf->st_mtimespec.tv_sec = t;
    stbuf->st_atimespec.tv_sec = t;
  }

  // ctime  TODO: ctime is not "creation time" rather it's the last time the 
  // inode was changed.  mtime would probably be a closer approximation.
  NSDate* cdate = [attributes objectForKey:NSFileCreationDate];
  if (cdate) {
    stbuf->st_ctimespec.tv_sec = [cdate timeIntervalSince1970];
  }

  // Size for regular files.
  // TODO: Revisit size for directories.
  if (![fileType isEqualToString:NSFileTypeDirectory]) {
    NSNumber* size = [attributes objectForKey:NSFileSize];
    if (size) {
      stbuf->st_size = [size longLongValue];
    } else {
      // NOTE: We use the given path here, since managedContentsForPath will
      // handle managed resources and return the proper data.
      NSData* data = [self managedContentsForPath:path];
      if (data) {
        stbuf->st_size = [data length];
      } else {
        stbuf->st_size = 0;
      }
    }
  }

  // Set the number of blocks used so that Finder will display size on disk 
  // properly. The man page says that this is in terms of 512 byte blocks.
  if (stbuf->st_size > 0) {
    stbuf->st_blocks = stbuf->st_size / 512;
    if (stbuf->st_size % 512) {
      ++(stbuf->st_blocks);
    }
  }

  return YES;  
}

#pragma mark Moving an Item

- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(moveItemAtPath:toPath:error:)]) {
    return [delegate_ moveItemAtPath:source toPath:destination error:error];
  }  
  
  *error = [UserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Removing an Item

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(removeItemAtPath:error:)]) {
    return [delegate_ removeItemAtPath:path error:error];
  }

  *error = [UserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(createDirectoryAtPath:attributes:error:)]) {
    return [delegate_ createDirectoryAtPath:path attributes:attributes error:error];
  }

  *error = [UserFileSystem errorWithCode:EACCES];
  return NO;
}

- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
               outHandle:(id *)outHandle
                   error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(createFileAtPath:attributes:outHandle:error:)]) {
    return [delegate_ createFileAtPath:path attributes:attributes 
                             outHandle:outHandle error:error];
  }  

  *error = [UserFileSystem errorWithCode:EACCES];
  return NO;
}


#pragma mark Linking an Item

// TODO: fusefm version.
- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(linkItemAtPath:toPath:error:)]) {
    return [delegate_ linkItemAtPath:path toPath:otherPath error:error];
  }  

  *error = [UserFileSystem errorWithCode:ENOTSUP];  // TODO: not in man page.
  return NO;
}

#pragma mark Symbolic Links

// TODO: The fusefm_ equivalent is not yet implemented.
- (BOOL)createSymbolicLinkAtPath:(NSString *)path 
             withDestinationPath:(NSString *)otherPath
                           error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(createSymbolicLinkAtPath:withDestinationPath:error:)]) {
    return [delegate_ createSymbolicLinkAtPath:path
                           withDestinationPath:otherPath
                                         error:error];
  }

  *error = [UserFileSystem errorWithCode:ENOTSUP];  // TODO: not in man page.
  return NO; 
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(destinationOfSymbolicLinkAtPath:error:)]) {
    return [delegate_ destinationOfSymbolicLinkAtPath:path error:error];
  }

  *error = [UserFileSystem errorWithCode:ENOENT];
  return nil;
}

#pragma mark File Contents

- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
             outHandle:(id *)outHandle 
                 error:(NSError **)error {
  // First see if it is an AppleDouble or Icon\r file that we handle.
  *outHandle = [self managedContentsForPath:path];
  if ( *outHandle != nil) {
    return YES;
  }

  if ([delegate_ respondsToSelector:@selector(contentsAtPath:)]) {
    *outHandle = [delegate_ contentsAtPath:path];
    if (*outHandle != nil) {
      return YES;
    }
  } else if ([delegate_ respondsToSelector:@selector(openFileAtPath:mode:outHandle:error:)]) {
    return [delegate_ openFileAtPath:path 
                                mode:mode 
                           outHandle:outHandle 
                               error:error];
  }
  *error = [UserFileSystem errorWithCode:ENOENT];
  return NO;
}

- (void)releaseFileAtPath:(NSString *)path handle:(id)handle {
  if ([delegate_ respondsToSelector:@selector(releaseFileAtPath:handle:)]) {
    [delegate_ releaseFileAtPath:path handle:handle];
  }
}

- (int)readFileAtPath:(NSString *)path 
               handle:(id)handle
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(readFileAtPath:handle:buffer:size:offset:error:)]) {
    return [delegate_ readFileAtPath:path 
                              handle:handle 
                              buffer:buffer 
                                size:size 
                              offset:offset 
                               error:error];
  } else if (handle != nil &&
             [handle respondsToSelector:@selector(readToBuffer:size:offset:error:)]) {
    return [handle readToBuffer:buffer size:size offset:offset error:error];
  }
  *error = [UserFileSystem errorWithCode:EACCES];
  return -1;
}

- (int)writeFileAtPath:(NSString *)path 
                handle:(id)handle 
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(writeFileAtPath:handle:buffer:size:offset:error:)]) {
    return [delegate_ writeFileAtPath:path 
                               handle:handle 
                               buffer:buffer 
                                 size:size 
                               offset:offset 
                                error:error];
  } else if (handle != nil &&
             [handle respondsToSelector:@selector(writeFromBuffer:size:offset:error:)]) {
    return [handle writeFromBuffer:buffer size:size offset:offset error:error];
  }

  *error = [UserFileSystem errorWithCode:EACCES];
  return -1; 
}

- (BOOL)truncateFileAtPath:(NSString *)path 
                    offset:(off_t)offset 
                     error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(truncateFileAtPath:offset:error:)]) {
    return [delegate_ truncateFileAtPath:path 
                                  offset:offset 
                                   error:error];
  }

  *error = [UserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Directory Contents

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
  if ([delegate_ respondsToSelector:@selector(fileExistsAtPath:isDirectory:)]) {
    return [delegate_ fileExistsAtPath:path isDirectory:isDirectory];
  }  
  
  *isDirectory = [path isEqualToString:@"/"];
  return YES; 
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
  *error = nil;
  NSArray* contents = nil;
  if ([delegate_ respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)]) {
    contents = [delegate_ contentsOfDirectoryAtPath:path error:error];
  } else if ([path isEqualToString:@"/"]) {
    contents = [NSArray array];
  }
  if (!contents) {
    if (*error == nil) {
      *error = [UserFileSystem errorWithCode:ENOENT];
    }
    return nil;
  }
  
  NSMutableArray *fullContents = [NSMutableArray array];
  [fullContents addObject:@"."];
  [fullContents addObject:@".."];
  [fullContents addObjectsFromArray:contents];
  
  // TODO: Check if we actually need to list this in the dir or if Finder can
  // find it for us.
  if ([self hasCustomIconAtPath:path]) {
    [fullContents addObject:@"Icon\r"];      
  }

  return fullContents;
}

#pragma mark Getting and Setting Attributes

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
                                   error:(NSError **)error {
  NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
  [attributes setObject:[NSNumber numberWithLong:0555] 
                 forKey:NSFilePosixPermissions];
  [attributes setObject:[NSNumber numberWithLong:1]
                 forKey:NSFileReferenceCount];    // 1 means "don't know"
  
  NSString* dataPath = path;  // Default to the given path.
  BOOL isManagedResource = [self usesResourceForks] ? 
    [self isManagedResourceAtPath:path type:nil dataPath:&dataPath] : NO;

  BOOL needFileExists = NO;
  
  // The delegate can override any of the above defaults by implementing the
  // attributesOfItemAtPath: selector and returning a custom dictionary.
  if ([delegate_ respondsToSelector:@selector(attributesOfFileSystemForPath:error:)]) {
    *error = nil;
    NSDictionary* customAttribs = 
      [delegate_ attributesOfItemAtPath:dataPath error:error];    
    if (!customAttribs) {
      if (!(*error)) {
        *error = [UserFileSystem errorWithCode:ENOENT];
      }
      return nil;
    }
    [attributes addEntriesFromDictionary:customAttribs];
  } else {
    needFileExists = YES;
  }
  if (![attributes objectForKey:NSFileType]) {
    needFileExists = YES;
  }
  if (needFileExists) {
    if ([delegate_ respondsToSelector:@selector(fileExistsAtPath:isDirectory:)]) {
      BOOL isDirectory;
      if (![delegate_ fileExistsAtPath:dataPath isDirectory:&isDirectory]) {
        *error = [UserFileSystem errorWithCode:ENOENT];
        return nil;
      }
      [attributes setObject:(isDirectory ? NSFileTypeDirectory : NSFileTypeRegular)
                      forKey:NSFileType];      
    } else {
      NSLog(@"You must either fill in the NSFileType or implement the "
            "fileExistsAtPath:isDirectory selector.");
      *error = [UserFileSystem errorWithCode:ENOENT];
      return nil;
    }
  }
  
  if (isManagedResource) {
    [attributes setObject:NSFileTypeRegular forKey:NSFileType];
    [attributes removeObjectForKey:NSFileSize];
  }
  return attributes;
}

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error {
  NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
  NSNumber* defaultSize = [NSNumber numberWithLongLong:(2LL * 1024 * 1024 * 1024)];
  [attributes setObject:defaultSize forKey:NSFileSystemSize];
  [attributes setObject:defaultSize forKey:NSFileSystemFreeSize];
  [attributes setObject:defaultSize forKey:NSFileSystemNodes];
  [attributes setObject:defaultSize forKey:NSFileSystemFreeNodes];
  // TODO: NSFileSystemNumber? Or does fuse do that for us?
  
  // The delegate can override any of the above defaults by implementing the
  // attributesOfFileSystemForPath selector and returning a custom dictionary.
  if ([delegate_ respondsToSelector:@selector(attributesOfFileSystemForPath:error:)]) {
    *error = nil;
    NSDictionary* customAttribs = 
      [delegate_ attributesOfFileSystemForPath:path error:error];    
    if (!customAttribs) {
      if (!(*error)) {
        *error = [UserFileSystem errorWithCode:ENODEV];
      }
      return nil;
    }
    [attributes addEntriesFromDictionary:customAttribs];
  }
  return attributes;
}

- (BOOL)setAttributes:(NSDictionary *)attributes 
         ofItemAtPath:(NSString *)path
                error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(setAttributes:ofItemAtPath:error:)]) {
    return [delegate_ setAttributes:attributes ofItemAtPath:path error:error];
  }  
  *error = [UserFileSystem errorWithCode:ENODEV];
  return NO;
}

#pragma mark Extended Attributes

- (NSData *)valueOfExtendedAttribute:(NSString *)name forPath:(NSString *)path
                               error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(valueOfExtendedAttribute:forPath:error:)]) {
    return [delegate_ valueOfExtendedAttribute:name forPath:path error:error];
  }
  *error = [UserFileSystem errorWithCode:ENOTSUP];
  return nil;
}

- (BOOL)setExtendedAttribute:(NSString *)name 
                     forPath:(NSString *)path 
                       value:(NSData *)value
                       flags:(int) flags
                       error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(setExtendedAttribute:forPath:value:flags:error:)]) {
    return [delegate_ setExtendedAttribute:name 
                                   forPath:path 
                                     value:value
                                     flags:flags
                                     error:error];
  }  
  *error = [UserFileSystem errorWithCode:ENOTSUP];
  return NO;
}

- (NSArray *)extendedAttributesForPath:path error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(extendedAttributesForPath:error:)]) {
    return [delegate_ extendedAttributesForPath:path error:error];
  }
  *error = [UserFileSystem errorWithCode:ENOTSUP];
  return nil;
}

#pragma mark FUSE Operations

static int fusefm_statfs(const char* path, struct statvfs* stbuf) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int res = -ENOENT;
  memset(stbuf, 0, sizeof(struct statvfs));
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs fillStatvfsBuffer:stbuf 
                    forPath:[NSString stringWithUTF8String:path]
                      error:&error]) {
    res = 0;
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];
  return res;
}

static int fusefm_getattr(const char *path, struct stat *stbuf) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int res = -ENOENT;
  memset(stbuf, 0, sizeof(struct stat));
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs fillStatBuffer:stbuf 
                 forPath:[NSString stringWithUTF8String:path]
                   error:&error]) {
    res = 0;
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];
  return res;
}

static int fusefm_fgetattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
  // TODO: This is a quick hack to get fstat up and running.
  return fusefm_getattr(path, stbuf);
}

static int fusefm_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                          off_t offset, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int res = -ENOENT;

  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  NSArray *contents = 
  [fs contentsOfDirectoryAtPath:[NSString stringWithUTF8String:path] 
                          error:&error];
  if (contents) {
    res = 0;
    for (int i = 0, count = [contents count]; i < count; i++) {
      filler(buf, [[contents objectAtIndex:i] UTF8String], NULL, 0);
    }
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];
  return res;
}

static int fusefm_create(const char* path, mode_t mode, struct fuse_file_info* fi) {
  int res = -EACCES;
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  @try {
    NSError* error = nil;
    id object = nil;
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    [attribs setObject:[NSNumber numberWithLong:mode] forKey:NSFilePosixPermissions];
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs createFileAtPath:[NSString stringWithUTF8String:path]
                  attributes:attribs
                   outHandle:&object
                       error:&error]) {
      res = 0;
      if (object != nil) {
        fi->fh = (uint64_t)(int)[object retain];
      }
    } else {
      if (error != nil) {
        res = -[error code];
      }
    }
  }
  @catch (NSException * e) {
  }
  [pool release];
  return res;
}

static int fusefm_open(const char *path, struct fuse_file_info *fi) {
  int res = -ENOENT;  // TODO: Default to 0 (success) since a file-system does
                      // not necessarily need to implement open.
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @try {
    id object = nil;
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs openFileAtPath:[NSString stringWithUTF8String:path]
                      mode:fi->flags
                 outHandle:&object
                     error:&error]) {
      res = 0;
      if (object != nil) {
        fi->fh = (uint64_t)(int)[object retain];
      }
    } else {
      if (error != nil) {
        res = -[error code];
      }
    }
  }
  @catch (NSException * e) {
  }
  [pool release];
  return res;
}


static int fusefm_release(const char *path, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  id object = (id)(int)fi->fh;
  UserFileSystem* fs = [UserFileSystem currentFS];
  [fs releaseFileAtPath:[NSString stringWithUTF8String:path] handle:object];
  if (object) {
    [object release]; 
  }
  [pool release];
  return 0;
}

static int fusefm_truncate(const char* path, off_t offset) {
  int res = -ENOTSUP;
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs truncateFileAtPath:[NSString stringWithUTF8String:path]
                      offset:offset
                       error:&error]) {
    res = 0;
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  
  [pool release];
  return res;
}

static int fusefm_ftruncate(const char* path, off_t offset, struct fuse_file_info *fh) {
  return fusefm_truncate(path, offset);
}

static int fusefm_chown(const char* path, uid_t uid, gid_t gid) {
  int res = 0;  // Return success by default.
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
  [attribs setObject:[NSNumber numberWithLong:uid] forKey:NSFileOwnerAccountID];
  [attribs setObject:[NSNumber numberWithLong:gid] forKey:NSFileGroupOwnerAccountID];
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs setAttributes:attribs 
           ofItemAtPath:[NSString stringWithUTF8String:path]
                  error:&error]) {
    res = 0;
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];

  return res;
}

static int fusefm_chmod(const char* path, mode_t mode) {
  int res = 0;  // Return success by default.
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
  [attribs setObject:[NSNumber numberWithLong:mode] forKey:NSFilePosixPermissions];
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs setAttributes:attribs 
           ofItemAtPath:[NSString stringWithUTF8String:path]
                  error:&error]) {
    res = 0;
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];
  
  return res;
}

int fusefm_utimens(const char* path, const struct timespec tv[2]) {
  int res = 0;  // Return success by default.
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
  NSDate* modification = 
  [NSDate dateWithTimeIntervalSince1970:tv[1].tv_sec];
  
  [attribs setObject:modification forKey:NSFileModificationDate];
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs setAttributes:attribs 
           ofItemAtPath:[NSString stringWithUTF8String:path]
                  error:&error]) {
    res = 0;
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];
  
  return res;
}

static int fusefm_fsync(const char* path, int isdatasync,
                        struct fuse_file_info* fi) {
  return 0;
}

static int fusefm_write(const char* path, const char* buf, size_t size, 
                        off_t offset, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  int length = [fs writeFileAtPath:[NSString stringWithUTF8String:path]
                            handle:(id)(int)fi->fh
                            buffer:buf
                              size:size
                            offset:offset
                             error:&error];
  if ( error != nil) {
    length = -[error code];
  }

  [pool release];
  return length;
}

static int fusefm_read(const char *path, char *buf, size_t size, off_t offset,
                       struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  int length = [fs readFileAtPath:[NSString stringWithUTF8String:path]
                           handle:(id)(int)fi->fh
                           buffer:buf
                             size:size
                           offset:offset
                              error:&error];
  if ( error != nil) {
    length = -[error code];
  }
  
  [pool release];
  return length;
}

static int fusefm_readlink(const char *path, char *buf, size_t size)
{
  int res = -ENOENT;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString* linkPath = [NSString stringWithUTF8String:path];
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  NSString *pathContent = [fs destinationOfSymbolicLinkAtPath:linkPath
                                                        error:&error];
  if (pathContent != nil) {
    res = 0;
    [pathContent getFileSystemRepresentation:buf maxLength:size];
  } else {
    if (error != nil) {
      res = -[error code];
    }
  }
  [pool release];
  return 0;
}

static int fusefm_getxattr(const char *path, const char *name, char *value,
                           size_t size) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int res = -ENOATTR;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    NSData *data = [fs valueOfExtendedAttribute:[NSString stringWithUTF8String:name]
                                        forPath:[NSString stringWithUTF8String:path]
                                          error:&error];
    if (data != nil) {
      res = [data length];  // default to returning size of buffer.
      if (value) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:value length:size];
        res = size;  // bytes read
      }
    } else if (error != nil) {
      res = -[error code];
    }
  }
  @catch (NSException * e) {
    res = -ENOTSUP;
  }
  [pool release];
  return res;
}

static int fusefm_setxattr(const char *path, const char *name, const char *value,
                           size_t size, int flags) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int res = -EPERM;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs setExtendedAttribute:[NSString stringWithUTF8String:name]
                         forPath:[NSString stringWithUTF8String:path]
                           value:[NSData dataWithBytes:value length:size]
                           flags:flags
                           error:&error]) {
      res = 0;
    } else {
      if ( error != nil ) {
        res = -[error code];
      }
    }
  }
  @catch (NSException * e) {
    res = -ENOTSUP;
  }
  [pool release];
  return res;
}

static int fusefm_listxattr(const char *path, char *list, size_t size)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int res = -ENOTSUP;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    NSArray *attributeNames =
      [fs extendedAttributesForPath:[NSString stringWithUTF8String:path]
                              error:&error];
    if ( attributeNames != nil ) {
      char zero = 0;
      NSMutableData *data = [NSMutableData dataWithCapacity:size];  
      for (int i = 0, count = [attributeNames count]; i < count; i++) {
        [data appendData:[[attributeNames objectAtIndex:i] dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendBytes:&zero length:1];
      }
      res = [data length];  // default to returning size of buffer.
      if (list) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:list length:size];
      }
    } else if (error != nil) {
      res = -[error code];
    }
  }
  @catch (NSException * e) {
    res = -ENOTSUP;
  }

  [pool release];
  return res;
}

static int fusefm_rename(const char* path, const char* toPath) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  NSString* source = [NSString stringWithUTF8String:path];
  NSString* destination = [NSString stringWithUTF8String:toPath];
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs moveItemAtPath:source toPath:destination error:&error]) {
    ret = 0;  // Success!
  } else {
    if (error != nil) {
      ret = -[error code];
    }
  }
  [pool release];
  return ret;  
}

static int fusefm_mkdir(const char* path, mode_t mode) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  NSError* error = nil;
  // TODO: Create proper attributes dictionary from mode_t.
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs createDirectoryAtPath:[NSString stringWithUTF8String:path] 
                     attributes:nil
                          error:(NSError **)error]) {
    ret = 0;  // Success!
  } else {
    if (error != nil) {
      ret = -[error code];
    }
  }
  [pool release];
  return ret;
}

static int fusefm_unlink(const char* path) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs removeItemAtPath:[NSString stringWithUTF8String:path] 
                     error:&error]) {
    ret = 0;  // Success!
  } else {
    if (error != nil) {
      ret = -[error code];
    }
  }
  [pool release];
  return ret;
}

static int fusefm_rmdir(const char* path) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  
  NSError* error = nil;
  UserFileSystem* fs = [UserFileSystem currentFS];
  if ([fs removeItemAtPath:[NSString stringWithUTF8String:path] 
                     error:&error]) {
    ret = 0;  // Success!
  } else {
    if (error != nil) {
      ret = -[error code];
    }
  }
  [pool release];
  return ret;
}

static void *fusefm_init(struct fuse_conn_info *conn) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  UserFileSystem* fs = [UserFileSystem currentFS];
  [fs retain];
  [fs fuseInit];

  [pool release];
  return fs;
}

static void fusefm_destroy(void *private_data) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  UserFileSystem* fs = (UserFileSystem *)private_data;
  [fs fuseDestroy];
  [fs release];

  [pool release];
}

static struct fuse_operations fusefm_oper = {
  .init = fusefm_init,
  .destroy = fusefm_destroy,
  .statfs = fusefm_statfs,
  .getattr	= fusefm_getattr,
  .fgetattr = fusefm_fgetattr,
  .readdir	= fusefm_readdir,
  .open	= fusefm_open,
  .release	= fusefm_release,
  .read	= fusefm_read,
  .readlink	= fusefm_readlink,
  .write = fusefm_write,
  .create = fusefm_create,
  .getxattr	= fusefm_getxattr,
  .setxattr = fusefm_setxattr,
  .listxattr	= fusefm_listxattr,
  .mkdir = fusefm_mkdir,
  .unlink = fusefm_unlink,
  .rmdir = fusefm_rmdir,
  .rename = fusefm_rename,
  .truncate = fusefm_truncate,
  .ftruncate = fusefm_ftruncate,
  .chown = fusefm_chown,
  .chmod = fusefm_chmod,
  .utimens = fusefm_utimens,
  .fsync = fusefm_fsync,
};

// TODO: Better name for below mark
#pragma mark Internal Lifecycle?

- (void)mount:(NSDictionary *)args {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  [mountPath_ autorelease];
  mountPath_ = [[args objectForKey:@"mountPath"] retain];
  NSArray* options = [args objectForKey:@"options"];
  BOOL isThreadSafe = [[args objectForKey:@"isThreadSafe"] boolValue];
  BOOL shouldForeground = [[args objectForKey:@"shouldForeground"] boolValue];
  
  // Trigger initialization of NSFileManager. This is rather lame, but if we
  // don't call directoryContents before we mount our FUSE filesystem and 
  // the filesystem uses NSFileManager we may deadlock. It seems that the
  // NSFileManager class will do lazy init and will query all mounted
  // filesystems. This leads to deadlock when we re-enter our mounted fuse fs. 
  // Once initialized it seems to work fine.
  [[NSFileManager defaultManager] directoryContentsAtPath:@"/Volumes"];

  // Create mount path if necessary.
  NSFileManager *fileManager = [NSFileManager defaultManager];
  [fileManager createDirectoryAtPath:mountPath_ attributes:nil];

  NSMutableArray* arguments = 
    [NSMutableArray arrayWithObject:[[NSBundle mainBundle] executablePath]];
  if (isThreadSafe) {
    [arguments addObject:@"-s"];  // Force single-threaded mode.
  }
  if (shouldForeground) {
    [arguments addObject:@"-f"];  // Forground rather than daemonize.
  }
  for (int i = 0; i < [options count]; ++i) {
    NSString* option = [options objectAtIndex:i];
    if ([option length] > 0) {
      [arguments addObject:[NSString stringWithFormat:@"-o%@",option]];
    }
  }
  [arguments addObject:mountPath_];
  
  // Start Fuse Main
  int argc = [arguments count];
  const char *argv[argc];
  for (int i = 0, count = [arguments count]; i < count; i++) {
    NSString* argument = [arguments objectAtIndex:i];
    argv[i] = strdup([argument UTF8String]);  // We'll just leak this for now.
  }
  if ([delegate_ respondsToSelector:@selector(willMount)]) {
    [delegate_ willMount];
  }
  [pool release];
  fuse_main(argc, (char **)argv, &fusefm_oper, self);
}

@end