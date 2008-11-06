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
//  GMUserFileSystem.h
//
//  Created by ted on 12/29/07.
//  Based on FUSEFileSystem originally by alcor.
//
#import <Foundation/Foundation.h>

// See "64-bit Class and Instance Variable Access Control"
#define GM_EXPORT __attribute__((visibility("default")))

@class GMUserFileSystemInternal;

GM_EXPORT @interface GMUserFileSystem : NSObject {
 @private
  GMUserFileSystemInternal* internal_;
}

- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe;

- (void)setDelegate:(id)delegate;
- (id)delegate;

// Mount the filesystem at the given path. The set of available options can
// be found at:  http://code.google.com/p/macfuse/wiki/OPTIONS
// For example, to turn on debug output add @"debug" to the options NSArray.
// If the mount fails, a kGMUserFileSystemMountFailed notification will be posted
// to the default notification center. See Notifications below.
- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options;

// Advanced mount call. You can use this to mount from a command-line program
// as follows:
//  For an app, use: shouldForeground=YES, detachNewThread=YES
//  For a daemon: shouldForeground=NO, detachNewThread=NO
//  For debug output: shouldForeground=YES, detachNewThread=NO
//  For a daemon+runloop:  shouldForeground=NO, detachNewThread=YES
//    - NOTE: I've never tried daemon+runloop; maybe it doesn't make sense?
// If the mount fails, a kGMUserFileSystemMountFailed notification will be posted 
// to the default notification center. See Notifications below.
- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options
   shouldForeground:(BOOL)shouldForeground     // Recommend: YES
    detachNewThread:(BOOL)detachNewThread;     // Recommend: YES

// Unmount the filesystem.
- (void)unmount;

@end

#pragma mark Notifications

// The GMUserFileSystem will post lifecycle notifications to the defaultCenter.
// Since the underlying GMUserFileSystem implementation is multi-threaded, you 
// should assume that notifications will not be posted on the main thread. The
// object will always be the GMUserFileSystem* and the userInfo will always
// contain at least the following:
//   kGMUserFileSystemMountPathkey -> NSString* that is the mount path

// Error domain for GMUserFileSystem specific errors.
extern NSString* const kGMUserFileSystemErrorDomain;

// Key in notification dictionary for mount path (@"mountPath" for legacy)
extern NSString* const kGMUserFileSystemMountPathKey;

// Key in notification dictionary for an error (@"error" for legacy reasons)
extern NSString* const kGMUserFileSystemErrorKey;

// Notification sent when the mountAtPath operation fails. The userInfo will
// contain an kGMUserFileSystemErrorKey with an NSError*.
extern NSString* const kGMUserFileSystemMountFailed;

// Notification sent after the filesystem is successfully mounted.
extern NSString* const kGMUserFileSystemDidMount;

// Notification sent after the filesystem is successfully unmounted.
extern NSString* const kGMUserFileSystemDidUnmount;

#pragma mark -

#pragma mark GMUserFileSystem Delegate Protocols

// The GMUserFileSystem's delegate can implement any of the below protocols.
// In most cases you can selectively choose which methods of a protocol to 
// implement.

@interface NSObject (GMUserFileSystemLifecycle)

- (void)willMount;
- (void)willUnmount;

@end

@interface NSObject (GMUserFileSystemOperations)
// These are the core methods that your filesystem needs to implement. Unless
// otherwise noted, they typically should behave like the NSFileManager 
// equivalent. However, the error codes that they return should correspond to
// the BSD-equivalent call and be in the NSPOSIXErrorDomain.
//
// For a read-only filesystem, you can typically pick-and-choose which methods
// to implement.  For example, a minimal read-only filesystem might implement:
//
// - (NSArray *)contentsOfDirectoryAtPath:(NSString *)path 
//                                  error:(NSError **)error;
// - (NSDictionary *)attributesOfItemAtPath:(NSString *)path
//                                 userData:(id)userData
//                                    error:(NSError **)error;
// - (NSData *)contentsAtPath:(NSString *)path;
//
// For a writeable filesystem, the Finder can be quite picky unless the majority
// of these methods are implemented. However, you can safely skip hard-links, 
// symbolic links, and extended attributes.

#pragma mark Directory Contents

// BSD-equivalent: readdir(3)
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Getting and Setting Attributes

// Returns a dictionary of attributes at the given path. It is required to 
// return at least the NSFileType attribute. You may omit the NSFileSize
// attribute if contentsAtPath: is implemented, although this is less efficient.
// The following keys are currently supported (unknown keys are ignored):
//   NSFileType [Required]
//   NSFileSize [Recommended]
//   NSFileModificationDate
//   NSFileReferenceCount
//   NSFilePosixPermissions
//   NSFileOwnerAccountID
//   NSFileGroupOwnerAccountID
//   NSFileCreationDate                 (if supports extended dates)
//   kGMUserFileSystemFileBackupDateKey (if supports extended dates)
//   kGMUserFileSystemFileChangeDateKey
//   kGMUserFileSystemFileFlagsKey [NSNumber uint32_t for stat st_flags field]
//
// If this is the fstat variant and userData was supplied in openFileAtPath: or 
// createFileAtPath: then it will be passed back in this call.
//
// BSD-equivalent: stat(2), fstat(2)
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path
                                userData:(id)userData
                                   error:(NSError **)error;

// The following keys are currently supported (unknown keys are ignored):
//   NSFileSystemSize
//   NSFileSystemFreeSize
//   NSFileSystemNodes
//   NSFileSystemFreeNodes
//   kGMUserFileSystemVolumeSupportsExtendedDatesKey [NSNumber boolean]
//
// BSD-equivalent: statvfs(3)
- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error;

// The following keys may be present (you must ignore unknown keys):
//   NSFileSize
//   NSFileOwnerAccountID
//   NSFileGroupOwnerAccountID
//   NSFileModificationDate
//   NSFilePosixPermissions
//   NSFileCreationDate                  (if supports extended dates)
//   kGMUserFileSystemFileBackupDateKey  (if supports extended dates)
//   kGMUserFileSystemFileChangeDateKey
//   kGMUserFileSystemFileAccessDateKey
//   kGMUserFileSystemFileFlagsKey [NSNumber uint32_t for stat st_flags field]
//
// If this is the f-variant and userData was supplied in openFileAtPath: or 
// createFileAtPath: then it will be passed back in this call.
//
// BSD-equivalent: truncate(2), chown(2), chmod(2), utimes(2), chflags(2)
//                 ftruncate(2), fchown(2), fchmod(2), futimes(2), fchflags(2)
- (BOOL)setAttributes:(NSDictionary *)attributes 
         ofItemAtPath:(NSString *)path
             userData:(id)userData
                error:(NSError **)error;

#pragma mark File Contents

// If contentsAtPath is implemented then you can skip open/release/read.
// Return nil if the file does not exist at the given path.
- (NSData *)contentsAtPath:(NSString *)path;

// BSD-equivalent: open(2)
- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError **)error;

// BSD-equivalent: close(2)
- (void)releaseFileAtPath:(NSString *)path userData:(id)userData;

// BSD-equivalent: pread(2)
- (int)readFileAtPath:(NSString *)path 
             userData:(id)userData
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error;

// BSD-equivalent: pwrite(2)
- (int)writeFileAtPath:(NSString *)path 
              userData:(id)userData
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

// Called to atomically exchange file data between path1 and path2.
//
// BSD-equivalent: exchangedata(2)
- (BOOL)exchangeDataOfItemAtPath:(NSString *)path1
                  withItemAtPath:(NSString *)path2
                           error:(NSError **)error;

#pragma mark Creating an Item

// BSD-equivalent: mkdir(2)
- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error;

// BSD-equivalent: creat(2)
- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
                userData:(id *)userData
                   error:(NSError **)error;

#pragma mark Moving an Item

// BSD-equivalent: rename(2)
- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error;

#pragma mark Removing an Item

// Remove the directory at the given path. This should not recursively remove
// subdirectories. If not implemented, then removeItemAtPath will be called.
// 
// BSD-equivalent: rmdir(2)
- (BOOL)removeDirectoryAtPath:(NSString *)path error:(NSError **)error;

// Remove the item at the given path. This should not recursively remove
// subdirectories. If removeDirectoryAtPath is implemented, then that will
// be called instead of this selector if the item is a directory.
//
// BSD-equivalent: rmdir(2), unlink(2)
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Linking an Item

// BSD-equivalent: link(2)
- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError **)error;

#pragma mark Symbolic Links

// BSD-equivalent: symlink(2)
- (BOOL)createSymbolicLinkAtPath:(NSString *)path 
             withDestinationPath:(NSString *)otherPath
                           error:(NSError **)error;

// BSD-equivalent: readlink(2)
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error;

#pragma mark Extended Attributes

// BSD-equivalent: listxattr(2)
- (NSArray *)extendedAttributesOfItemAtPath:path
                                      error:(NSError **)error;

// BSD-equivalent: getxattr(2)
- (NSData *)valueOfExtendedAttribute:(NSString *)name
                        ofItemAtPath:(NSString *)path
                            position:(off_t)position
                               error:(NSError **)error;

// BSD-equivalent: setxattr(2)
- (BOOL)setExtendedAttribute:(NSString *)name
                ofItemAtPath:(NSString *)path
                       value:(NSData *)value
                    position:(off_t)position
                     options:(int)options
                       error:(NSError **)error;

// BSD-equivalent: removexattr(2)
- (BOOL)removeExtendedAttribute:(NSString *)name
                   ofItemAtPath:(NSString *)path
                          error:(NSError **)error;

@end

@interface NSObject (GMUserFileSystemResourceForks)
// Implementing any GMUserFileSystemResourceForks method turns on automatic 
// handling of FinderInfo and ResourceForks. In 10.5 and later these are 
// provided via extended attributes while in 10.4 we use "._" files. Typically,
// it only makes sense to use these for a read-only file system.

// Returns a dictionary of FinderInfo attributes at the given path. Return nil
// or a dictionary with no relevant keys if there is no FinderInfo data. If a 
// custom icon is desired, then use Finder flags with the kHasCustomIcon bit set 
// (preferred) and/or the kGMUserFileSystemCustonIconDataKey, and don't forget
// to implement resourceAttributesAtPath:error: below. The following keys 
// are currently supported (unknown keys are ignored):
//   NSFileHFSTypeCode
//   NSFileHFSCreatorCode
//   kGMUserFileSystemFinderFlagsKey (NSNumber Uint16 Finder flags)
//   kGMUserFileSystemFinderExtendedFlagsKey (NSNumber Uint16)
//   kGMUserFileSystemCustomIconDataKey [Raw .icns file NSData]
//   TODO: kGMUserFileSystemLabelNumberKey   (NSNumber)
//
// BSD-equivalent: getxattr(2)
- (NSDictionary *)finderAttributesAtPath:(NSString *)path 
                                   error:(NSError **)error;

// Returns a dictionary of ResourceFork attributes at the given path. Return nil
// or a dictionary with no relevant keys if there is no resource fork data.
// The following keys are currently supported (unknown keys are ignored):
//   kGMUserFileSystemCustomIconDataKey [Raw .icns file NSData]
//   kGMUserFileSystemWeblocURLkey [NSURL, only valid for .webloc files]
//
// BSD-equivalent: getxattr(2)
- (NSDictionary *)resourceAttributesAtPath:(NSString *)path
                                     error:(NSError **)error;

@end

#pragma mark Additional Item Attribute Keys

// For st_flags (see man 2 stat). Value is an NSNumber* with uint32 value.
extern NSString* const kGMUserFileSystemFileFlagsKey;

// For st_atimespec (see man 2 stat). Last file access time.
extern NSString* const kGMUserFileSystemFileAccessDateKey;

// For st_ctimespec (see man 2 stat). Last file status change time.
extern NSString* const kGMUserFileSystemFileChangeDateKey;

// For file backup date.
extern NSString* const kGMUserFileSystemFileBackupDateKey;

#pragma mark Additional Volume Attribute Keys

// Boolean NSNumber for whether the volume supports extended dates such as
// creation date and backup date.
extern NSString* const kGMUserFileSystemVolumeSupportsExtendedDatesKey;

#pragma mark Additional Finder and Resource Fork keys

// For FinderInfo flags (i.e. kHasCustomIcon). See CarbonCore/Finder.h.
extern NSString* const kGMUserFileSystemFinderFlagsKey;

// For FinderInfo extended flags (i.e. kExtendedFlagHasCustomBadge).
extern NSString* const kGMUserFileSystemFinderExtendedFlagsKey;

// For ResourceFork custom icon. NSData for raw .icns file.
extern NSString* const kGMUserFileSystemCustomIconDataKey;

// For ResourceFork webloc NSURL.
extern NSString* const kGMUserFileSystemWeblocURLKey;

#undef GM_EXPORT
