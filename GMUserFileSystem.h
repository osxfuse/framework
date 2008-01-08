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

@class GMUserFileSystemInternal;

@interface GMUserFileSystem : NSObject {
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

// Notifications
//
// The GMUserFileSystem will post lifecycle notifications to the defaultCenter.
// Since the underlying GMUserFileSystem implementation is multi-threaded, you 
// should assume that notifications will not be posted on the main thread. The
// object will always be the GMUserFileSystem* and the userInfo will always
// contain at least the following:
//   @"mountPath" -> NSString* that is the mount path

// Notification sent when the mountAtPath operation fails. The userInfo will
// contain an @"error" key with an NSError*.
extern NSString* const kGMUserFileSystemMountFailed;

// Notification sent after the filesystem is successfully mounted.
extern NSString* const kGMUserFileSystemDidMount;

// Notification sent after the filesystem is successfully unmounted.
extern NSString* const kGMUserFileSystemDidUnmount;

#pragma mark -

#pragma mark File Delegate Protocol

// The openFileAtPath: and createFileAtPath: operations have fileDelegate as an
// out-parameter. Any GMUserFileSystemFileDelegate method that the fileDelegate 
// implements will be called instead of the corresponding method on the 
// GMUserFileSystem's delegate.

@interface NSObject (GMUserFileSystemFileDelegate)

// bsd-equivalent: read
- (int)readToBuffer:(char *)buffer 
               size:(size_t)size 
             offset:(off_t)offset 
              error:(NSError **)error;

// bsd-equivalent: write
- (int)writeFromBuffer:(const char *)buffer 
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

// bsd-equivalent: ftruncate
- (BOOL)truncateToOffset:(off_t)offset 
                   error:(NSError **)error;

@end

#pragma mark GMUserFileSystem Delegate Protocols

// The GMUserFileSystem's delegate can implement any of the below protocols.
// In most cases you can selectively choose which methods of a protocol to 
// implement.

@interface NSObject (GMUserFileSystemLifecycle)

- (void)willMount;
- (void)willUnmount;

@end

@interface NSObject (GMUserFileSystemResourceForks)
// Implementing any GMUserFileSystemResourceForks method turns on automatic 
// handling of FinderInfo and ResourceForks. In 10.5 and later these are 
// provided via extended attributes while in 10.4 we use "._" files.

// The Finder flags to use for the given path. Include kHasCustomIcon if you
// want to display a custom icon for a file or directory. If you do not
// implement this then iconDataForPath will be called instead to probe for the 
// existence of a custom icon.
- (UInt16)finderFlagsAtPath:(NSString *)path;

// The raw .icns file data to use as the custom icon for the file/directory.
// Return nil if the path does not have a custom icon.
- (NSData *)iconDataAtPath:(NSString *)path;

// The url for the .webloc file at path. This is only called for .webloc files.
- (NSURL *)URLOfWeblocAtPath:(NSString *)path;

@end

@interface NSObject (GMUserFileSystemOperations)
// These are the core methods that your filesystem needs to implement. Unless
// otherwise noted, they typically should behave like the NSFileManager 
// equivalent. However, the error codes that they return should correspond to
// the bsd-equivalent call and be in the NSPOSIXErrorDomain.
//
// For a read-only filesystem, you can typically pick-and-choose which methods
// to implement.  For example, a minimal read-only filesystem might implement:
//
// - (NSArray *)contentsOfDirectoryAtPath:(NSString *)path 
//                                  error:(NSError **)error;
// - (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
//                                    error:(NSError **)error;
// - (NSData *)contentsAtPath:(NSString *)path;
//
// For a writeable filesystem, the Finder can be quite picky unless the majority
// of these methods are implemented. However, you can safely skip hard-links, 
// symbolic links, and extended attributes.

#pragma mark Directory Contents

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Getting and Setting Attributes

// Returns a dictionary of attributes at the given path. It is required to 
// return at least the NSFileType attribute. You may omit the NSFileSize
// attribute if contentsAtPath: is implemented, although this is less efficient.
//
// bsd-equivalent: stat
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
                                   error:(NSError **)error;

// bsd-equivalent: statvfs
- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error;

// bsd-equivalent: chown, chmod, utimes
- (BOOL)setAttributes:(NSDictionary *)attributes 
         ofItemAtPath:(NSString *)path
                error:(NSError **)error;

#pragma mark File Contents

// If contentsAtPath is implemented then you can skip open/release/read.
// Return nil if the file does not exist at the given path.
- (NSData *)contentsAtPath:(NSString *)path;

// bsd-equivalent: open
- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
          fileDelegate:(id *)fileDelegate
                 error:(NSError **)error;

// bsd-equivalent: close
- (void)releaseFileAtPath:(NSString *)path fileDelegate:(id)fileDelegate;

// This is only called if the fileDelegate is nil or does not implement the 
// readToBuffer:size:offset:error: method.
//
// bsd-equivalent: read
- (int)readFileAtPath:(NSString *)path 
         fileDelegate:(id)fileDelegate
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error;

// This is only called if the fileDelegate is nil or does not implement the 
// writeFromBuffer:size:offset:error: method.
//
// bsd-equivalent: write
- (int)writeFileAtPath:(NSString *)path 
          fileDelegate:(id)fileDelegate 
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

// This is only called if the fileDelegate is nil or does not implement the 
// truncateToOffset:error: method.
//
// bsd-equivalent: truncate
- (BOOL)truncateFileAtPath:(NSString *)path 
                    offset:(off_t)offset 
                     error:(NSError **)error;

#pragma mark Creating an Item

// bsd-equivalent: mkdir
- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error;

// bsd-equivalent: creat
- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
            fileDelegate:(id *)fileDelegate
                   error:(NSError **)error;

#pragma mark Moving an Item

// bsd-equivalent: rename
- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error;

#pragma mark Removing an Item

// bsd-equivalent: rmdir, unlink
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Linking an Item

// bsd-equivalent: link
- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError **)error;

#pragma mark Symbolic Links

// bsd-equivalent: symlink
- (BOOL)createSymbolicLinkAtPath:(NSString *)path 
             withDestinationPath:(NSString *)otherPath
                           error:(NSError **)error;

// bsd-equivalent: readlink
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error;

#pragma mark Extended Attributes

// bsd-equivalent: listxattr
- (NSArray *)extendedAttributesOfItemAtPath:path 
                                      error:(NSError **)error;

// bsd-equivalent: getxattr
- (NSData *)valueOfExtendedAttribute:(NSString *)name 
                        ofItemAtPath:(NSString *)path
                               error:(NSError **)error;

// bsd-equivalent: setxattr
- (BOOL)setExtendedAttribute:(NSString *)name
                ofItemAtPath:(NSString *)path
                       value:(NSData *)value
                       flags:(int)flags
                       error:(NSError **)error;

// bsd-equivalent: removexattr
- (BOOL)removeExtendedAttribute:(NSString *)name
                   ofItemAtPath:(NSString *)path
                          error:(NSError **)error;

@end
