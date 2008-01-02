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
#include <sys/ioctl.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

#import <Foundation/Foundation.h>
#import "GMAppleDouble.h"
#import "GMFinderInfo.h"
#import "GMResourceFork.h"
#import "NSData+BufferOffset.h"

#define EXPORT __attribute__((visibility("default")))

// Notifications
EXPORT NSString* const kUserFileSystemMountFailed = @"kUserFileSystemMountFailed";
EXPORT NSString* const kUserFileSystemDidMount = @"kUserFileSystemDidMount";
EXPORT NSString* const kUserFileSystemDidUnmount = @"kUserFileSystemDidUnmount";

typedef enum {
  UserFileSystem_NOT_MOUNTED,   // Not mounted.
  UserFileSystem_MOUNTING,      // In the process of mounting.
  UserFileSystem_INITIALIZING,  // Almost done mounting.
  UserFileSystem_MOUNTED,       // Confirmed to be mounted.
  UserFileSystem_UNMOUNTING,    // In the process of unmounting.
  UserFileSystem_FAILURE,       // Failed state; probably a mount failure.
} UserFileSystemStatus;

@interface UserFileSystem (UserFileSystemPrivate)

+ (UserFileSystem *)currentFS;

- (void)mount:(NSDictionary *)args;
- (void)waitUntilMounted;

- (UInt16)finderFlagsAtPath:(NSString *)path;
- (BOOL)hasCustomIconAtPath:(NSString *)path;
- (BOOL)isDirectoryIconAtPath:(NSString *)path dirPath:(NSString **)dirPath;
- (BOOL)isAppleDoubleAtPath:(NSString *)path realPath:(NSString **)realPath;
- (NSData *)resourceForkContentsAtPath:(NSString *)path;
- (NSData *)appleDoubleContentsAtPath:(NSString *)path;

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
    status_ = UserFileSystem_NOT_MOUNTED;
    isThreadSafe_ = isThreadSafe;
    delegate_ = delegate;
    
    // Version 10.4 requires ._ to appear in directory listings.
    // TODO: Switch to fuse_os_version_major() at some point.
    shouldListDoubleFiles_ = YES;
    struct utsname u;
    size_t len = sizeof(u.release);
    if (sysctlbyname("kern.osrelease", u.release, &len, NULL, 0) == 0) {
      char* c = strchr(u.release, '.');
      if (c) {
        *c = '\0';
        long version = strtol(u.release, NULL, 10);
        if (errno != EINVAL && errno != ERANGE && version >= 9) {
          shouldListDoubleFiles_ = NO;  // We are Leopard or above.
        }
      }
    }
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

- (void)unmount {
  if (status_ == UserFileSystem_MOUNTED) {
    NSArray* args = [NSArray arrayWithObjects:@"-v", mountPath_, nil];
    NSTask* unmountTask = [NSTask launchedTaskWithLaunchPath:@"/sbin/umount" 
                                                   arguments:args];
    [unmountTask waitUntilExit];
  }
}

+ (NSError *)errorWithCode:(int)code {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

+ (UserFileSystem *)currentFS {
  struct fuse_context* context = fuse_get_context();
  assert(context);
  return (UserFileSystem *)context->private_data;
}

#define FUSEDEVIOCGETHANDSHAKECOMPLETE _IOR('F', 2, u_int32_t)
extern int fuse_chan_fd_np();
static const int kMaxWaitForMountTries = 50;
static const int kWaitForMountUSleepInterval = 100000;  // 100 ms
- (void)waitUntilMounted {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  for (int i = 0; i < kMaxWaitForMountTries; ++i) {
    UInt32 handShakeComplete = 0;
    int ret = ioctl(fuse_chan_fd_np(), 
                    FUSEDEVIOCGETHANDSHAKECOMPLETE, 
                    &handShakeComplete);
    if (ret == 0 && handShakeComplete) {
      status_ = UserFileSystem_MOUNTED;
      
      // Successfully mounted, so post notification.
      NSDictionary* userInfo = 
        [NSDictionary dictionaryWithObjectsAndKeys:
         mountPath_, @"mountPath",
         nil, nil];
      NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
      [center postNotificationName:kUserFileSystemDidMount object:self
                          userInfo:userInfo];
      [pool release];
      return;
    }
    usleep(kWaitForMountUSleepInterval);
  }
  
  // Tried for a long time and no luck :-(
  // TODO: Unmount and report failure?
  [pool release];
}

- (void)fuseInit {
  status_ = UserFileSystem_INITIALIZING;
  
  // The mount point won't actually show up until this winds its way
  // back through the kernel after this routine returns. In order to post
  // the kUserFileSystemDidMount notification we start a new thread that will
  // poll until it is mounted.
  [NSThread detachNewThreadSelector:@selector(waitUntilMounted) 
                           toTarget:self 
                         withObject:nil];
}

- (void)fuseDestroy {
  if ([delegate_ respondsToSelector:@selector(willUnmount)]) {
    [delegate_ willUnmount];
  }
  status_ = UserFileSystem_UNMOUNTING;

  NSDictionary* userInfo = 
    [NSDictionary dictionaryWithObjectsAndKeys:
     mountPath_, @"mountPath",
     nil, nil];
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center postNotificationName:kUserFileSystemDidUnmount object:self
                      userInfo:userInfo];
}

#pragma mark Finder Info, Resource Forks and HFS headers

- (UInt16)finderFlagsAtPath:(NSString *)path {
  UInt16 flags = 0;

  // If a directory icon, we'll make invisible and update the path to parent.
  if ([self isDirectoryIconAtPath:path dirPath:&path]) {
    flags |= kIsInvisible;
  }

  if ([delegate_ respondsToSelector:@selector(finderFlagsAtPath:)]) {
    flags |= [delegate_ finderFlagsAtPath:path];
  } else if ([delegate_ respondsToSelector:@selector(iconDataAtPath:)] &&
             [delegate_ iconDataAtPath:path] != nil) {
    flags |= kHasCustomIcon;
  }
  return flags;
}

- (BOOL)hasCustomIconAtPath:(NSString *)path {
  UInt16 flags = [self finderFlagsAtPath:path];
  return (flags & kHasCustomIcon) == kHasCustomIcon;
}

- (BOOL)isDirectoryIconAtPath:(NSString *)path dirPath:(NSString **)dirPath {
  NSString* name = [path lastPathComponent];
  if ([name isEqualToString:@"Icon\r"]) {
    if (dirPath) {
      *dirPath = [path stringByDeletingLastPathComponent];
    }
    return YES;
  }
  return NO;
}

- (BOOL)isAppleDoubleAtPath:(NSString *)path realPath:(NSString **)realPath {
  NSString* name = [path lastPathComponent];
  if ([name hasPrefix:@"._"]) {
    if (realPath) {
      name = [name substringFromIndex:2];
      *realPath = [path stringByDeletingLastPathComponent];
      *realPath = [*realPath stringByAppendingPathComponent:name];
    }
    return YES;
  }
  return NO;  
}

- (NSData *)resourceForkContentsAtPath:(NSString *)path {
  NSURL* url = nil;
  if ([path hasSuffix:@".webloc"] &&
       [delegate_ respondsToSelector:@selector(URLContentOfWeblocAtPath:)]) {
    url = [delegate_ URLContentOfWeblocAtPath:path];
  }
  NSData* imageData = nil;
  if ([delegate_ respondsToSelector:@selector(iconDataAtPath:)]) {
    imageData = [delegate_ iconDataAtPath:path];
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

// Returns the AppleDouble file contents, if any, for the given path. You should
// call this with the realPath out-param from a call to isAppleDoubleAtPath:.
//
// On 10.5 and (hopefully) above, the Finder will end up using the extended
// attributes and so we won't need to serve ._ files. 
- (NSData *)appleDoubleContentsAtPath:(NSString *)path {
  UInt16 flags = [self finderFlagsAtPath:path];
 
  // We treat the ._ for a directory and it's ._Icon\r file the same. This means
  // that we'll put extra resource-fork information in directory's ._ file even 
  // though it isn't needed. It's worth it given that it only affects 10.4.
  [self isDirectoryIconAtPath:path dirPath:&path];

  NSData* resourceForkData = [self resourceForkContentsAtPath:path];
  if (flags != 0 || resourceForkData != nil) {
    GMAppleDouble* doubleFile = [GMAppleDouble appleDouble];
    NSData* finderInfo = [GMFinderInfo finderInfoWithFinderFlags:flags];
    [doubleFile addEntryWithID:DoubleEntryFinderInfo data:finderInfo];
    if (resourceForkData) {
      [doubleFile addEntryWithID:DoubleEntryResourceFork 
                            data:resourceForkData];
    }
    return [doubleFile data];
  }
  return nil;
}

#pragma mark Internal Stat Operations

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
  // First see if it is an Icon\r or AppleDouble file that we handle.
  if ([self isDirectoryIconAtPath:path dirPath:nil]) {
    *outHandle = [NSData data];
    return YES;
  }
  NSString* realPath;
  if ([self isAppleDoubleAtPath:path realPath:&realPath]) {
    *outHandle = [self appleDoubleContentsAtPath:realPath];
    return (*outHandle != nil);
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
  NSArray* contents = nil;
  if ([delegate_ respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)]) {
    contents = [delegate_ contentsOfDirectoryAtPath:path error:error];
  } else if ([path isEqualToString:@"/"]) {
    contents = [NSArray array];  // Give them an empty root directory for free.
  }
  if (contents != nil && shouldListDoubleFiles_) {
    // Note: Tiger (10.4) requires that the ._ file are explicitly listed in 
    // the directory contents.
    NSMutableArray *fullContents = [NSMutableArray arrayWithArray:contents];
    for (int i = 0; i < [contents count]; ++i) {
      NSString* name = [contents objectAtIndex:i];
      NSString* pathPlusName = [path stringByAppendingPathComponent:name];
      if ([self hasCustomIconAtPath:pathPlusName]) {
        [fullContents addObject:[NSString stringWithFormat:@"._%@",name]];
      }
    }
    if ([self hasCustomIconAtPath:path]) {
      [fullContents addObject:@"Icon\r"];
      [fullContents addObject:@"._Icon\r"];
    }
    contents = fullContents;
  }
  return contents;
}

#pragma mark Getting and Setting Attributes

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
                                   error:(NSError **)error {
  NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
  [attributes setObject:[NSNumber numberWithLong:0555]
                 forKey:NSFilePosixPermissions];
  [attributes setObject:[NSNumber numberWithLong:1]
                 forKey:NSFileReferenceCount];    // 1 means "don't know"
  
  BOOL isDirectoryIcon = [self isDirectoryIconAtPath:path dirPath:&path];
  BOOL isAppleDouble = [self isAppleDoubleAtPath:path realPath:&path];
  assert(!(isDirectoryIcon && isAppleDouble));
  
  // We give them two chances to tell us whether or not the file exists. One is
  // via attributesOfItemAtPath and the other is fileExistsAtPath:isDirectory:.
  BOOL needFileExists = NO;
  
  // The delegate can override any of the above defaults by implementing the
  // attributesOfItemAtPath: selector and returning a custom dictionary.
  if ([delegate_ respondsToSelector:@selector(attributesOfItemAtPath:error:)]) {
    *error = nil;
    NSDictionary* customAttribs = 
      [delegate_ attributesOfItemAtPath:path error:error];
    if (!customAttribs) {
      if (!(*error)) {
        *error = [UserFileSystem errorWithCode:ENOENT];
      }
      return nil;
    }
    [attributes addEntriesFromDictionary:customAttribs];
  } else {
    needFileExists = YES;  // attributesOfItemAtPath: not implemented.
  }

  // If this is a directory Icon\r then it is an empty file and we're done.
  if (isDirectoryIcon) {
    if ([self hasCustomIconAtPath:path]) {
      [attributes setObject:NSFileTypeRegular forKey:NSFileType];
      [attributes setObject:[NSNumber numberWithLongLong:0] forKey:NSFileSize];
      return attributes;
    }
    *error = [UserFileSystem errorWithCode:ENOENT];
    return nil;
  }
  
  // If this is a ._ then we'll need to compute its size and we're done.
  if (isAppleDouble) {
    NSData* data = [self appleDoubleContentsAtPath:path];
    if (data != nil) {
      [attributes setObject:NSFileTypeRegular forKey:NSFileType];
      [attributes setObject:[NSNumber numberWithLongLong:[data length]]
                     forKey:NSFileSize];
      return attributes;
    }
    *error = [UserFileSystem errorWithCode:ENOENT];
    return nil;
  }
  
  // If they don't supply an NSFileType we'll try fileExistsAtPath:isDirectory:.
  if (![attributes objectForKey:NSFileType]) {
    needFileExists = YES;
  }
  if (needFileExists) {
    if ([delegate_ respondsToSelector:@selector(fileExistsAtPath:isDirectory:)]) {
      BOOL isDirectory;
      if (![delegate_ fileExistsAtPath:path isDirectory:&isDirectory]) {
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
  
  // If they don't supply a file size, we'll try to compute it for them.
  if (![attributes objectForKey:NSFileSize]) {
    if ([delegate_ respondsToSelector:@selector(contentsForPath:)]) {
      NSData* data = [delegate_ contentsAtPath:path];
      [attributes setObject:[NSNumber numberWithLong:[data length]]
                     forKey:NSFileSize];
    }
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

- (NSArray *)extendedAttributesOfItemAtPath:path error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(extendedAttributesOfItemAtPath:error:)]) {
    return [delegate_ extendedAttributesOfItemAtPath:path error:error];
  }
  *error = [UserFileSystem errorWithCode:ENOTSUP];
  return nil;
}

- (NSData *)valueOfExtendedAttribute:(NSString *)name 
                        ofItemAtPath:(NSString *)path
                               error:(NSError **)error {
  NSData* data = nil;
  if ([delegate_ respondsToSelector:@selector(valueOfExtendedAttribute:ofItemAtPath:error:)]) {
    data = [delegate_ valueOfExtendedAttribute:name ofItemAtPath:path error:error];
  }
  if (data == nil) {
    if ([name isEqualToString:@"com.apple.FinderInfo"]) {
      int flags = [self finderFlagsAtPath:path];
      data = [GMFinderInfo finderInfoWithFinderFlags:flags];
    } else if ([name isEqualToString:@"com.apple.ResourceFork"]) {
      [self isDirectoryIconAtPath:path dirPath:&path];
      data = [self resourceForkContentsAtPath:path];
      if (data == nil) {
        *error = [UserFileSystem errorWithCode:ENOATTR];
        return nil;
      }
    }    
  }
  if (data == nil) {
    *error = [UserFileSystem errorWithCode:ENOTSUP];
  }
  return data;
}

- (BOOL)setExtendedAttribute:(NSString *)name 
                ofItemAtPath:(NSString *)path 
                       value:(NSData *)value
                       flags:(int) flags
                       error:(NSError **)error {
  if ([delegate_ respondsToSelector:@selector(setExtendedAttribute:ofItemAtPath:value:flags:error:)]) {
    return [delegate_ setExtendedAttribute:name 
                              ofItemAtPath:path 
                                     value:value
                                     flags:flags
                                     error:error];
  }  
  *error = [UserFileSystem errorWithCode:ENOTSUP];
  return NO;
}

#pragma mark FUSE Operations

#define MAYBE_USE_ERROR(var, error)                                       \
  if ((error) != nil &&                                                   \
      [[(error) domain] isEqualToString:NSPOSIXErrorDomain]) {            \
    int code = [(error) code];                                            \
    if (code != 0) {                                                      \
      (var) = -code;                                                      \
    }                                                                     \
  }

static int fusefm_statfs(const char* path, struct statvfs* stbuf) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(stbuf, 0, sizeof(struct statvfs));
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs fillStatvfsBuffer:stbuf 
                      forPath:[NSString stringWithUTF8String:path]
                        error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_getattr(const char *path, struct stat *stbuf) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(stbuf, 0, sizeof(struct stat));
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs fillStatBuffer:stbuf 
                   forPath:[NSString stringWithUTF8String:path]
                     error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_fgetattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
  // TODO: This is a quick hack to get fstat up and running.
  return fusefm_getattr(path, stbuf);
}

static int fusefm_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                          off_t offset, struct fuse_file_info *fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    NSArray *contents = 
    [fs contentsOfDirectoryAtPath:[NSString stringWithUTF8String:path] 
                            error:&error];
    if (contents) {
      ret = 0;
      filler(buf, ".", NULL, 0);
      filler(buf, "..", NULL, 0);
      for (int i = 0, count = [contents count]; i < count; i++) {
        filler(buf, [[contents objectAtIndex:i] UTF8String], NULL, 0);
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_create(const char* path, mode_t mode, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  
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
      ret = 0;
      if (object != nil) {
        fi->fh = (uint64_t)(int)[object retain];
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_open(const char *path, struct fuse_file_info *fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;  // TODO: Default to 0 (success) since a file-system does
                      // not necessarily need to implement open?

  @try {
    id object = nil;
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs openFileAtPath:[NSString stringWithUTF8String:path]
                      mode:fi->flags
                 outHandle:&object
                     error:&error]) {
      ret = 0;
      if (object != nil) {
        fi->fh = (uint64_t)(int)[object retain];
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}


static int fusefm_release(const char *path, struct fuse_file_info *fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  @try {
    id object = (id)(int)fi->fh;
    UserFileSystem* fs = [UserFileSystem currentFS];
    [fs releaseFileAtPath:[NSString stringWithUTF8String:path] handle:object];
    if (object) {
      [object release]; 
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return 0;
}

static int fusefm_truncate(const char* path, off_t offset) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOTSUP;
  
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs truncateFileAtPath:[NSString stringWithUTF8String:path]
                        offset:offset
                         error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  
  [pool release];
  return ret;
}

static int fusefm_ftruncate(const char* path, off_t offset, struct fuse_file_info *fh) {
  return fusefm_truncate(path, offset);
}

static int fusefm_chown(const char* path, uid_t uid, gid_t gid) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // NOTE: Return success by default.
  
  @try {
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    [attribs setObject:[NSNumber numberWithLong:uid] 
                forKey:NSFileOwnerAccountID];
    [attribs setObject:[NSNumber numberWithLong:gid] 
                forKey:NSFileGroupOwnerAccountID];
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs setAttributes:attribs 
             ofItemAtPath:[NSString stringWithUTF8String:path]
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_chmod(const char* path, mode_t mode) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // NOTE: Return success by default.

  @try {
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    [attribs setObject:[NSNumber numberWithLong:mode] 
                forKey:NSFilePosixPermissions];
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs setAttributes:attribs 
             ofItemAtPath:[NSString stringWithUTF8String:path]
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_utimens(const char* path, const struct timespec tv[2]) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // NOTE: Return success by default.
  @try {
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    NSDate* modification = [NSDate dateWithTimeIntervalSince1970:tv[1].tv_sec];
    [attribs setObject:modification forKey:NSFileModificationDate];
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs setAttributes:attribs 
             ofItemAtPath:[NSString stringWithUTF8String:path]
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_fsync(const char* path, int isdatasync,
                        struct fuse_file_info* fi) {
  // TODO: Support fsync?
  return 0;
}

static int fusefm_write(const char* path, const char* buf, size_t size, 
                        off_t offset, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EIO;
  
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    ret = [fs writeFileAtPath:[NSString stringWithUTF8String:path]
                       handle:(id)(int)fi->fh
                       buffer:buf
                         size:size
                       offset:offset
                        error:&error];
    MAYBE_USE_ERROR(ret, error);
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_read(const char *path, char *buf, size_t size, off_t offset,
                       struct fuse_file_info *fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EIO;

  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    ret = [fs readFileAtPath:[NSString stringWithUTF8String:path]
                      handle:(id)(int)fi->fh
                      buffer:buf
                        size:size
                      offset:offset
                       error:&error];
    MAYBE_USE_ERROR(ret, error);
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_readlink(const char *path, char *buf, size_t size)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSString* linkPath = [NSString stringWithUTF8String:path];
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    NSString *pathContent = [fs destinationOfSymbolicLinkAtPath:linkPath
                                                          error:&error];
    if (pathContent != nil) {
      ret = 0;
      [pathContent getFileSystemRepresentation:buf maxLength:size];
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_getxattr(const char *path, const char *name, char *value,
                           size_t size) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOATTR;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    NSData *data = [fs valueOfExtendedAttribute:[NSString stringWithUTF8String:name]
                                   ofItemAtPath:[NSString stringWithUTF8String:path]
                                          error:&error];
    if (data != nil) {
      ret = [data length];  // default to returning size of buffer.
      if (value) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:value length:size];
        ret = size;  // bytes read
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) {
  }
  [pool release];
  return ret;
}

static int fusefm_setxattr(const char *path, const char *name, const char *value,
                           size_t size, int flags) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EPERM;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs setExtendedAttribute:[NSString stringWithUTF8String:name]
                    ofItemAtPath:[NSString stringWithUTF8String:path]
                           value:[NSData dataWithBytes:value length:size]
                           flags:flags
                           error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_listxattr(const char *path, char *list, size_t size)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOTSUP;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    NSArray* attributeNames =
      [fs extendedAttributesOfItemAtPath:[NSString stringWithUTF8String:path]
                                   error:&error];
    if (attributeNames != nil) {
      char zero = 0;
      NSMutableData* data = [NSMutableData dataWithCapacity:size];  
      for (int i = 0, count = [attributeNames count]; i < count; i++) {
        [data appendData:[[attributeNames objectAtIndex:i] dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendBytes:&zero length:1];
      }
      ret = [data length];  // default to returning size of buffer.
      if (list) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:list length:size];
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_rename(const char* path, const char* toPath) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSString* source = [NSString stringWithUTF8String:path];
    NSString* destination = [NSString stringWithUTF8String:toPath];
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs moveItemAtPath:source toPath:destination error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;  
}

static int fusefm_mkdir(const char* path, mode_t mode) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
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
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_unlink(const char* path) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs removeItemAtPath:[NSString stringWithUTF8String:path] 
                       error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static int fusefm_rmdir(const char* path) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError* error = nil;
    UserFileSystem* fs = [UserFileSystem currentFS];
    if ([fs removeItemAtPath:[NSString stringWithUTF8String:path] 
                       error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (NSException* e) { }
  [pool release];
  return ret;
}

static void* fusefm_init(struct fuse_conn_info* conn) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  UserFileSystem* fs = [UserFileSystem currentFS];
  [fs retain];
  @try {
    [fs fuseInit];
  }
  @catch (NSException* e) { }

  [pool release];
  return fs;
}

static void fusefm_destroy(void* private_data) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  UserFileSystem* fs = (UserFileSystem *)private_data;
  @try {
    [fs fuseDestroy];
  }
  @catch (NSException* e) { }
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

#pragma mark Internal Mount

- (void)mount:(NSDictionary *)args {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  assert(status_ == UserFileSystem_NOT_MOUNTED);

  [mountPath_ autorelease];
  mountPath_ = [[args objectForKey:@"mountPath"] retain];
  NSArray* options = [args objectForKey:@"options"];
  BOOL isThreadSafe = [[args objectForKey:@"isThreadSafe"] boolValue];
  BOOL shouldForeground = [[args objectForKey:@"shouldForeground"] boolValue];

  // Create mount path if necessary.
  NSFileManager* fileManager = [NSFileManager defaultManager];
  [fileManager createDirectoryAtPath:mountPath_ attributes:nil];

  // Trigger initialization of NSFileManager. This is rather lame, but if we
  // don't call directoryContents before we mount our FUSE filesystem and 
  // the filesystem uses NSFileManager we may deadlock. It seems that the
  // NSFileManager class will do lazy init and will query all mounted
  // filesystems. This leads to deadlock when we re-enter our mounted fuse fs. 
  // Once initialized it seems to work fine.
  [fileManager directoryContentsAtPath:@"/Volumes"];

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
  const char* argv[argc];
  for (int i = 0, count = [arguments count]; i < count; i++) {
    NSString* argument = [arguments objectAtIndex:i];
    argv[i] = strdup([argument UTF8String]);  // We'll just leak this for now.
  }
  if ([delegate_ respondsToSelector:@selector(willMount)]) {
    [delegate_ willMount];
  }
  status_ = UserFileSystem_MOUNTING;
  [pool release];
  int ret = fuse_main(argc, (char **)argv, &fusefm_oper, self);

  pool = [[NSAutoreleasePool alloc] init];

  if (ret != 0 || status_ == UserFileSystem_MOUNTING) {
    // If we returned successfully from fuse_main while we still think we are 
    // mounting then an error must have occured during mount.
    status_ = UserFileSystem_FAILURE;

    NSError* error = [NSError errorWithDomain:@"UserFileSystemErrorDomain"
                                         code:(ret == 0) ? -1 : ret
                                     userInfo:nil];
    
    NSDictionary* userInfo = 
    [NSDictionary dictionaryWithObjectsAndKeys:
     mountPath_, @"mountPath",
     error, @"error",
     nil, nil];
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:kUserFileSystemMountFailed object:self
                        userInfo:userInfo];
  } else {
    status_ = UserFileSystem_NOT_MOUNTED;
  }

  [pool release];
}

@end
