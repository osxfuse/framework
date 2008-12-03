/*
 * ÇPROJECTNAMEASIDENTIFIERÈ.c
 * ÇPROJECTNAMEÈ
 *
 * Created by ÇFULLUSERNAMEÈ on ÇDATEÈ.
 * Copyright ÇYEARÈ ÇORGANIZATIONNAMEÈ. All rights reserved.
 *
 */

#include <fuse.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>

static int
ÇPROJECTNAMEASIDENTIFIERÈ_fgetattr(const char *path, struct stat *stbuf,
                  struct fuse_file_info *fi) {
  memset(stbuf, 0, sizeof(struct stat));
  
  if (strcmp(path, "/") == 0) { /* The root directory of our file system. */
    stbuf->st_mode = S_IFDIR | 0755;
    stbuf->st_nlink = 3;
    return 0;
  }
  return -ENOENT;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_getattr(const char *path, struct stat *stbuf) {
  return ÇPROJECTNAMEASIDENTIFIERÈ_fgetattr(path, stbuf, NULL);
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_readlink(const char *path, char *buf, size_t size) {
  return -ENOENT;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                 off_t offset, struct fuse_file_info *fi) {
  if (strcmp(path, "/") != 0) /* We only recognize the root directory. */
    return -ENOENT;
  
  filler(buf, ".", NULL, 0);           /* Current directory (.)  */
  filler(buf, "..", NULL, 0);          /* Parent directory (..)  */
  
  return 0;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_mknod(const char *path, mode_t mode, dev_t rdev) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_mkdir(const char *path, mode_t mode) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_unlink(const char *path) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_rmdir(const char *path) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_symlink(const char *from, const char *to) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_rename(const char *from, const char *to) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_exchange(const char *path1, const char *path2, unsigned long options) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_link(const char *from, const char *to) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_fsetattr_x(const char *path, struct setattr_x *attr,
                    struct fuse_file_info *fi) {
  return -ENOENT;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_setattr_x(const char *path, struct setattr_x *attr) {
  return -ENOENT;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_getxtimes(const char *path, struct timespec *bkuptime,
                   struct timespec *crtime) {
  return -ENOENT;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_open(const char *path, struct fuse_file_info *fi) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_read(const char *path, char *buf, size_t size, off_t offset,
              struct fuse_file_info *fi) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_write(const char *path, const char *buf, size_t size,
               off_t offset, struct fuse_file_info *fi) {
  return -ENOSYS;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_statfs(const char *path, struct statvfs *stbuf) {
  int res;

  // TODO: Return real statvfs values for your file system.
  res = statvfs("/", stbuf);
  if (res == -1) {
    return -errno;
  }
  return 0;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_flush(const char *path, struct fuse_file_info *fi) {
  return 0;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_release(const char *path, struct fuse_file_info *fi) {
  return 0;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_fsync(const char *path, int isdatasync, struct fuse_file_info *fi) {
  return 0;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_setxattr(const char *path, const char *name, const char *value,
                  size_t size, int flags, uint32_t position) {
  return -ENOTSUP;
 }

static int
ÇPROJECTNAMEASIDENTIFIERÈ_getxattr(const char *path, const char *name, char *value, size_t size,
                  uint32_t position) {
  return -ENOATTR;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_listxattr(const char *path, char *list, size_t size) {
  return 0;
}

static int
ÇPROJECTNAMEASIDENTIFIERÈ_removexattr(const char *path, const char *name) {
  return -ENOATTR;
}

void *
ÇPROJECTNAMEASIDENTIFIERÈ_init(struct fuse_conn_info *conn) {
  FUSE_ENABLE_XTIMES(conn);
  return NULL;
}

void
ÇPROJECTNAMEASIDENTIFIERÈ_destroy(void *userdata) {
  /* nothing */
}

struct fuse_operations ÇPROJECTNAMEASIDENTIFIERÈ_operations = {
  .init        = ÇPROJECTNAMEASIDENTIFIERÈ_init,
  .destroy     = ÇPROJECTNAMEASIDENTIFIERÈ_destroy,
  .getattr     = ÇPROJECTNAMEASIDENTIFIERÈ_getattr,
  .fgetattr    = ÇPROJECTNAMEASIDENTIFIERÈ_fgetattr,
/*  .access      = ÇPROJECTNAMEASIDENTIFIERÈ_access, */
  .readlink    = ÇPROJECTNAMEASIDENTIFIERÈ_readlink,
/*  .opendir     = ÇPROJECTNAMEASIDENTIFIERÈ_opendir, */
  .readdir     = ÇPROJECTNAMEASIDENTIFIERÈ_readdir,
/*  .releasedir  = ÇPROJECTNAMEASIDENTIFIERÈ_releasedir, */
  .mknod       = ÇPROJECTNAMEASIDENTIFIERÈ_mknod,
  .mkdir       = ÇPROJECTNAMEASIDENTIFIERÈ_mkdir,
  .symlink     = ÇPROJECTNAMEASIDENTIFIERÈ_symlink,
  .unlink      = ÇPROJECTNAMEASIDENTIFIERÈ_unlink,
  .rmdir       = ÇPROJECTNAMEASIDENTIFIERÈ_rmdir,
  .rename      = ÇPROJECTNAMEASIDENTIFIERÈ_rename,
  .link        = ÇPROJECTNAMEASIDENTIFIERÈ_link,
  .create      = ÇPROJECTNAMEASIDENTIFIERÈ_create,
  .open        = ÇPROJECTNAMEASIDENTIFIERÈ_open,
  .read        = ÇPROJECTNAMEASIDENTIFIERÈ_read,
  .write       = ÇPROJECTNAMEASIDENTIFIERÈ_write,
  .statfs      = ÇPROJECTNAMEASIDENTIFIERÈ_statfs,
  .flush       = ÇPROJECTNAMEASIDENTIFIERÈ_flush,
  .release     = ÇPROJECTNAMEASIDENTIFIERÈ_release,
  .fsync       = ÇPROJECTNAMEASIDENTIFIERÈ_fsync,
  .setxattr    = ÇPROJECTNAMEASIDENTIFIERÈ_setxattr,
  .getxattr    = ÇPROJECTNAMEASIDENTIFIERÈ_getxattr,
  .listxattr   = ÇPROJECTNAMEASIDENTIFIERÈ_listxattr,
  .removexattr = ÇPROJECTNAMEASIDENTIFIERÈ_removexattr,
  .exchange    = ÇPROJECTNAMEASIDENTIFIERÈ_exchange,
  .getxtimes   = ÇPROJECTNAMEASIDENTIFIERÈ_getxtimes,
  .setattr_x   = ÇPROJECTNAMEASIDENTIFIERÈ_setattr_x,
  .fsetattr_x  = ÇPROJECTNAMEASIDENTIFIERÈ_fsetattr_x,
};
