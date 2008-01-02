//
//  UserFileSystem.h
//
//  Created by ted on 12/29/07.
//  Based on FUSEFileSystem originally by alcor.
//  Copyright 2007 Google. All rights reserved.
//
#import <Foundation/Foundation.h>

@interface UserFileSystem : NSObject {
  NSString* mountPath_;
  int status_;  // Internal UserFileSystemStatus enum value.
  BOOL isThreadSafe_;  // Is the delegate thread-safe?
  BOOL shouldListDoubleFiles_;  // Should directory listings contain ._ files?
  id delegate_;
}

- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe;

- (void)setDelegate:(id)delegate;
- (id)delegate;

// Mount the filesystem at the given path. The set of available options can
// be found at:  http://code.google.com/p/macfuse/wiki/OPTIONS
// For example, to turn on debug output add @"debug" to the options NSArray.
// If the mount fails, a kUserFileSystemMountFailed notification will be posted
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
// If the mount fails, a kUserFileSystemMountFailed notification will be posted 
// to the default notification center. See Notifications below.
- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options
   shouldForeground:(BOOL)shouldForeground     // Recommend: YES
    detachNewThread:(BOOL)detachNewThread;     // Recommend: YES

// Unmount the filesystem.
- (void)unmount;

// Convenience method to creates an autoreleased NSError in the 
// NSPOSIXErrorDomain. Filesystem errors returned by the delegate must be
// standard posix errno values.
+ (NSError *)errorWithCode:(int)code;

@end

#pragma mark Notifications

// Notifications
//
// The UserFileSystem will post lifecycle notifications to the defaultCenter.
// Since the underlying UserFileSystem implementation is multi-threaded, you 
// should assume that notifications will not be posted on the main thread. The
// object will always be the UserFileSystem* and the userInfo will always
// contain at least the following:
//   @"mountPath" -> NSString* that is the mount path

// Notification sent when the mountAtPath operation fails. The userInfo will
// contain an @"error" key with an NSError*.
extern NSString* const kUserFileSystemMountFailed;

// Notification sent after the filesystem is successfully mounted.
extern NSString* const kUserFileSystemDidMount;

// Notification sent after the filesystem is successfully unmounted.
extern NSString* const kUserFileSystemDidUnmount;

#pragma mark -

#pragma mark FileSystemHandle Delegate Protocols

// For UserFileSystemOperations that return a Handle, the handle may implement
// all or part of the UserFileSystemhandleOperations protocol.

@interface NSObject (UserFileSystemHandleOperations)

- (int)readToBuffer:(char *)buffer 
               size:(size_t)size 
             offset:(off_t)offset 
              error:(NSError **)error;

- (int)writeFromBuffer:(const char *)buffer 
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

@end

#pragma mark Delegate Protocols

// The UserFileSystem's delegate can implement any of the below protocols.
// In most cases you can selectively choose which methods of a protocol to 
// implement.

@interface NSObject (UserFileSystemLifecycle)

- (void)willMount;
- (void)willUnmount;

@end

@interface NSObject (UserFileSystemResourceForks)
// Implementing any UserFileSystemResourceForks method turns on automatic 
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
- (NSURL *)URLContentOfWeblocAtPath:(NSString *)path;

@end

@interface NSObject (UserFileSystemOperations)
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
// of these methods are implemented. You can safely skip hard-links, symbolic 
// links, and extended attributes.

#pragma mark Moving an Item

// bsd-equivalent: rename
- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error;

#pragma mark Removing an Item

// bsd-equivalent: rmdir, unlink
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Creating an Item

// bsd-equivalent: mkdir
- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error;

// bsd-equivalent: creat
- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
               outHandle:(id *)outHandle
                   error:(NSError **)error;

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

#pragma mark File Contents

// If contentsAtPath is implemented then you can skip open/release/read.
// Return nil if the file does not exist at the given path.
- (NSData *)contentsAtPath:(NSString *)path;

// bsd-equivalent: open
- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
             outHandle:(id *)outHandle
                 error:(NSError **)error;

// bsd-equivalent: close
- (void)releaseFileAtPath:(NSString *)path handle:(id)handle;

// bsd-equivalent: read
- (int)readFileAtPath:(NSString *)path 
               handle:(id)handle
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error;

// bsd-equivalent: write
- (int)writeFileAtPath:(NSString *)path 
                handle:(id)handle 
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

// bsd-equivalent: truncate
- (BOOL)truncateFileAtPath:(NSString *)path 
                    offset:(off_t)offset 
                     error:(NSError **)error;

#pragma mark Directory Contents

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Getting and Setting Attributes

// TODO: I'd like to remove fileExistsAtPath. Considering it...
// You may implement fileExistsAtPath:isDirectory: and contentsAtPath: instead
// of attributesOfItemAtPath:. If attributesOfItemAtPath: does not set
// NSFileType then this method is required.
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;

// Returns a dictionary of attributes at the given path. It is required to 
// return at least the NSFileType attribute. You may omit the NSFileSize
// attribute if contentsAtPath: is implemented, although this is less efficient.
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

@end
