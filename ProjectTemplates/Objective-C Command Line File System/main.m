//
//  main.m
//  ÇPROJECTNAMEÈ
//
//  Created by ÇFULLUSERNAMEÈ on ÇDATEÈ.
//  Copyright ÇYEARÈ ÇORGANIZATIONNAMEÈ. All rights reserved.
//
// Compile on the command line as follows:
//  gcc -o "ÇPROJECTNAMEÈ" ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem.m main.m 
//      -framework MacFUSE -framework Foundation
//
#import <sys/stat.h>
#import <Foundation/Foundation.h>
#import <MacFUSE/GMUserFileSystem.h>
#import "ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem.h"

int main(int argc, char* argv[], char* envp[], char** exec_path) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
  NSString* mountPath = [args stringForKey:@"mountPath"];
  NSString* iconPath = [args stringForKey:@"volicon"];
  if (!mountPath || [mountPath isEqualToString:@""]) {
    printf("\nUsage: %s -mountPath <path> [-volicon <path>]\n", argv[0]);
    printf("  -mountPath: Mount point to use.\n");
    printf("Ex: %s -mountPath /Volumes/ÇPROJECTNAMEÈ\n\n", argv[0]);
    return 0;
  }
  if (!iconPath) {
    // We check for a volume icon embedded as our resource fork.
    char program_path[PATH_MAX] = { 0 };
    if (realpath(*exec_path, program_path)) {
      iconPath = [NSString stringWithFormat:@"%s/..namedfork/rsrc", program_path];
      struct stat stat_buf;
      memset(&stat_buf, 0, sizeof(stat_buf));
      if (stat([iconPath UTF8String], &stat_buf) != 0 || stat_buf.st_size <= 0) {
        iconPath = nil;  // We found an exec path, but the resource fork is empty.
      }
    }
  }
  
  ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem* fs = 
  [[ÇPROJECTNAMEASIDENTIFIERÈ_Filesystem alloc] init];
  GMUserFileSystem* userFS = [[GMUserFileSystem alloc] initWithDelegate:fs 
                                                           isThreadSafe:NO];
  
  NSMutableArray* options = [NSMutableArray array];
  if (iconPath != nil) {
    NSString* volArg = [NSString stringWithFormat:@"volicon=%@", iconPath];
    [options addObject:volArg];
  }
  [options addObject:@"volname=ÇPROJECTNAMEÈ"];
  // [options addObject:@"rdonly"];  <-- Uncomment to mount read-only.
  
  [userFS mountAtPath:mountPath 
          withOptions:options 
     shouldForeground:YES 
      detachNewThread:NO];
  
  [userFS release];
  [fs release];
  
  [pool release];
  return 0;
}
