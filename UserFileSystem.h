//
//  UserFileSystem.h
//
//  Created by ted on 12/29/07.
//  Based on FUSEFileSystem originally by alcor.
//  Copyright 2007 Google. All rights reserved.
//

// In order to create the most minimal read-only filesystem possible then your
// delegate must implement at least the following four methods (declared below):
//
// - (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;
// - (NSArray *)contentsOfDirectoryAtPath:(NSString *)path 
//                                  error:(NSError **)error;
// - (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
//    error:(NSError **)error;
// - (NSData *)contentsAtPath:(NSString *)path;

#import <Foundation/Foundation.h>

@interface UserFileSystem : NSObject {
  NSString* mountPath_;
  BOOL isMounted_;
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
- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options;

// Advanced mount call. A command-line daemon might want to set foreground to NO
// and not detach a new thread. Otherwise it is typically better to call the
// simpler mountAtPath which will use the default values.
- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options
   shouldForeground:(BOOL)shouldForeground     // Recommend: YES
    detachNewThread:(BOOL)detachNewThread;     // Recommend: YES

// Unmount the filesystem.
- (void)umount;

// Convenience method to creates an autoreleased NSError in the 
// NSPOSIXErrorDomain. Filesystem errors returned by the delegate must be
// standard posix errno values.
+ (NSError *)errorWithCode:(int)code;

@end

@interface NSObject (UserFileSystemLifecycle)

- (void)willMount;
- (void)didMount;

- (void)willUmount;
- (void)didUmount;

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

