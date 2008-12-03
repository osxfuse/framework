//
//  ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem.m
//  ÇPROJECTNAMEÈ
//
//  Created by ÇFULLUSERNAMEÈ on ÇDATEÈ.
//  Copyright ÇYEARÈ ÇORGANIZATIONNAMEÈ. All rights reserved.
//
#import <sys/xattr.h>
#import <sys/stat.h>
#import "ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem.h"
#import <MacFUSE/MacFUSE.h>

// Category on NSError to  simplify creating an NSError based on posix errno.
@interface NSError (POSIX)
+ (NSError *)errorWithPOSIXCode:(int)code;
@end
@implementation NSError (POSIX)
+ (NSError *)errorWithPOSIXCode:(int) code {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}
@end

// NOTE: It is fine to remove the below sections that are marked as 'Optional'.

// The core set of file system operations. This class will serve as the delegate
// for GMUserFileSystemFilesystem. For more details, see the section on 
// GMUserFileSystemOperations found in the documentation at:
// http://macfuse.googlecode.com/svn/trunk/core/sdk-objc/Documentation/index.html
@implementation ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem

#pragma mark Directory Contents

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
  *error = [NSError errorWithPOSIXCode:ENOENT];
  return nil;
}

#pragma mark Getting Attributes

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path
                                userData:(id)userData
                                   error:(NSError **)error {
  *error = [NSError errorWithPOSIXCode:ENOENT];
  return nil;
}

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error {
  return [NSDictionary dictionary];  // Default file system attributes.
}

#pragma mark File Contents

// TODO: There are two ways to support reading of file data. With the contentsAtPath
// method you must return the full contents of the file with each invocation. For
// a more complex (or efficient) file system, consider supporting the openFileAtPath:,
// releaseFileAtPath:, and readFileAtPath: delegate methods.
#define SIMPLE_FILE_CONTENTS 1
#if SIMPLE_FILE_CONTENTS

- (NSData *)contentsAtPath:(NSString *)path {
  return nil;  // Equivalent to ENOENT
}

#else

- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError **)error {
  *error = [NSError errorWithPOSIXCode:ENOENT];
  return NO;
}

- (void)releaseFileAtPath:(NSString *)path userData:(id)userData {
}

- (int)readFileAtPath:(NSString *)path 
             userData:(id)userData
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(off_t)offset
                error:(NSError **)error {
  return 0;  // We've reached end of file.
}

#endif  // #if SIMPLE_FILE_CONTENTS

#pragma mark Symbolic Links (Optional)

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error {
  *error = [NSError errorWithPOSIXCode:ENOENT];
  return NO;
}

#pragma mark Extended Attributes (Optional)

- (NSArray *)extendedAttributesOfItemAtPath:(NSString *)path error:(NSError **)error {
  return [NSArray array];  // No extended attributes.
}

- (NSData *)valueOfExtendedAttribute:(NSString *)name 
                        ofItemAtPath:(NSString *)path
                            position:(off_t)position
                               error:(NSError **)error {
  *error = [NSError errorWithPOSIXCode:ENOATTR];
  return nil;
}

#pragma mark FinderInfo and ResourceFork (Optional)

- (NSDictionary *)finderAttributesAtPath:(NSString *)path 
                                   error:(NSError **)error {
  return [NSDictionary dictionary];
}

- (NSDictionary *)resourceAttributesAtPath:(NSString *)path
                                     error:(NSError **)error {
  return [NSDictionary dictionary];
}

@end
