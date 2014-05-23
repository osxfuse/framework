/*
 * Copyright (C) 2006-2008 Google. All Rights Reserved.
 * Amit Singh <singh@>
 */

#ifndef _GMDTRACE_H_
#define _GMDTRACE_H_

#ifdef  __cplusplus
extern "C" {
#endif

#include <AvailabilityMacros.h>

#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4

/* Leopard+ */

#include <sys/sdt.h>
#include <macfuse_objc_dtrace.h>

#else

/* Tiger- */

#define MACFUSE_OBJC_DELEGATE_ENTRY(arg0)
#define MACFUSE_OBJC_DELEGATE_RETURN(arg0)

#define MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()  0
#define MACFUSE_OBJC_DELEGATE_RETURN_ENABLED() 0

#endif /* Leopard+/Tiger */

#ifdef  __cplusplus
}
#endif

#endif /* _GMDTRACE_H_ */
