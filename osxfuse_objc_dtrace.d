/*
 * Copyright (C) 2006-2008 Google. All Rights Reserved.
 * Amit Singh <singh@>
 */

/*
 * Keep the probes defined here in sync with the dummy ones in GMDTrace.h
 */

provider osxfuse_objc {
    probe delegate__entry(char*);
    probe delegate__return(int);
};

#pragma D attributes Evolving/Evolving/Common provider osxfuse_objc provider
#pragma D attributes Evolving/Evolving/Common provider osxfuse_objc module
#pragma D attributes Evolving/Evolving/Common provider osxfuse_objc function
#pragma D attributes Evolving/Evolving/Common provider osxfuse_objc name
#pragma D attributes Evolving/Evolving/Common provider osxfuse_objc args
