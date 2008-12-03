/*
 * main.c
 * ÇPROJECTNAMEÈ
 *
 * Created by ÇFULLUSERNAMEÈ on ÇDATEÈ.
 * Copyright ÇYEARÈ ÇORGANIZATIONNAMEÈ. All rights reserved.
 *
 * Compile on the command line as follows:
 * gcc -o "ÇPROJECTNAMEÈ" ÇPROJECTNAMEASIDENTIFIERÈ.c main.c -lfuse
 *     -D_FILE_OFFSET_BITS=64 -D__FreeBSD__=10 -DFUSE_USE_VERSION=26
 */
#include "fuse.h"

extern struct fuse_operations ÇPROJECTNAMEASIDENTIFIERÈ_operations;

int main(int argc, char* argv[], char* envp[], char** exec_path) {
  umask(0);
  return fuse_main(argc, argv, &ÇPROJECTNAMEASIDENTIFIERÈ_operations, NULL);
}
