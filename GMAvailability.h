//
//  GMAvailability.h
//  OSXFUSE
//

//  Copyright (c) 2016 Benjamin Fleischer.
//  All rights reserved.

#define GM_OSXFUSE_2 020000
#define GM_OSXFUSE_3 030000

#ifdef GM_VERSION_MIN_REQUIRED

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_2
        #define GM_AVAILABILITY_INTERNAL__OSXFUSE_2 __attribute__((weak_import))
    #else
        #define GM_AVAILABILITY_INTERNAL__OSXFUSE_2
    #endif

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_3
        #define GM_AVAILABILITY_INTERNAL__OSXFUSE_3 __attribute__((weak_import))
    #else
        #define GM_AVAILABILITY_INTERNAL__OSXFUSE_3
    #endif

    #define GM_AVAILABLE_STARTING(_version) GM_AVAILABILITY_INTERNAL__##_version

    #define GM_AVAILABLE_OSXFUSE_2_AND_LATER GM_AVAILABLE_STARTING(OSXFUSE_2)
    #define GM_AVAILABLE_OSXFUSE_3_AND_LATER GM_AVAILABLE_STARTING(OSXFUSE_3)

#else /* !GM_VERSION_MIN_REQUIRED */

    #define GM_AVAILABLE_OSXFUSE_2_AND_LATER
    #define GM_AVAILABLE_OSXFUSE_3_AND_LATER

#endif /* !GM_VERSION_MIN_REQUIRED */
