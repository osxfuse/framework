//
//  UserFileSystem.h
//
//  Created by ted on 12/29/07.
//  Based on FUSEFileSystem originally by alcor.
//  Copyright 2007 Google. All rights reserved.
//
#import <Foundation/Foundation.h>

// TODO: There must be a neat-o obj-c way to hide the member vars. Maybe should
// have a UserFileSystemImpl in the .m file and have the init method of
// UserFileSystem actually return a UserFileSystemImpl?

@interface UserFileSystem : NSObject {
  NSString* mountPath_;
  int status_;  // Actually internal UserFileSystemStatus enum value.
  BOOL isThreadSafe_;
  id delegate_;
}

- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe;
- (void)dealloc;

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
//
// In order to create the most minimal read-only filesystem possible then your
// delegate should implement the following four UserFileSystmOperations methods:
//
// - (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;
// - (NSArray *)contentsOfDirectoryAtPath:(NSString *)path 
//                                  error:(NSError **)error;
// - (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
//                                    error:(NSError **)error;
// - (NSData *)contentsAtPath:(NSString *)path;

@interface NSObject (UserFileSystemLifecycle)

- (void)willMount;
- (void)willUnmount;

@end

@interface NSObject (UserFileSystemResourceForks)

// The Finder flags to use for the given path.
- (UInt16)finderFlagsForPath:(NSString *)path;

// The raw .icns file data to use as the custom icon for the file/directory.
- (NSData *)iconDataForPath:(NSString *)path;

// The url for the .webloc file at path. This is only called for .webloc files.
- (NSURL *)URLContentOfWeblocAtPath:(NSString *)path;

@end

@interface NSObject (UserFileSystemOperations)

#pragma mark Moving an Item

- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error;

#pragma mark Removing an Item

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error;

- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
               outHandle:(id *)outHandle
                   error:(NSError **)error;

#pragma mark Linking an Item

- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError **)error;

#pragma mark Symbolic Links

- (BOOL)createSymbolicLinkAtPath:(NSString *)path 
             withDestinationPath:(NSString *)otherPath
                           error:(NSError **)error;
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error;

#pragma mark File Contents

// If contentsAtPath is implemented then you can skip open/release/read.
- (NSData *)contentsAtPath:(NSString *)path;

- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
             outHandle:(id *)outHandle
                 error:(NSError **)error;

- (void)releaseFileAtPath:(NSString *)path handle:(id)handle;

- (int)readFileAtPath:(NSString *)path 
               handle:(id)handle
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error;

- (int)writeFileAtPath:(NSString *)path 
                handle:(id)handle 
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(off_t)offset
                 error:(NSError **)error;

- (BOOL)truncateFileAtPath:(NSString *)path 
                    offset:(off_t)offset 
                     error:(NSError **)error;

#pragma mark Directory Contents

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Getting and Setting Attributes

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
                                   error:(NSError **)error;

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error;

- (BOOL)setAttributes:(NSDictionary *)attributes 
         ofItemAtPath:(NSString *)path
                error:(NSError **)error;

#pragma mark Extended Attributes

- (NSArray *)extendedAttributesForPath:path 
                                 error:(NSError **)error;

- (NSData *)valueOfExtendedAttribute:(NSString *)name 
                             forPath:(NSString *)path
                               error:(NSError **)error;

- (BOOL)setExtendedAttribute:(NSString *)name
                     forPath:(NSString *)path
                       value:(NSData *)value
                       flags:(int)flags
                       error:(NSError **)error;

@end
