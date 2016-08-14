//
//  GMAvailability.h
//  OSXFUSE
//

//  Copyright (c) 2016 Benjamin Fleischer.
//  All rights reserved.

#define GM_OSXFUSE_2_0 020000
#define GM_OSXFUSE_3_0 030000
#define GM_OSXFUSE_3_5 030500

#ifdef GM_VERSION_MIN_REQUIRED

    #define GM_AVAILABILITY_WEAK __attribute__((weak_import))

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_2
        #define GM_AVAILABILITY_INTERNAL__2_0 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__2_0
    #endif

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_3_0
        #define GM_AVAILABILITY_INTERNAL__3_0 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__3_0
    #endif

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_3_5
        #define GM_AVAILABILITY_INTERNAL__3_5 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__3_5
    #endif

    #define GM_AVAILABLE(_version) GM_AVAILABILITY_INTERNAL__##_version

#else /* !GM_VERSION_MIN_REQUIRED */

    #define GM_AVAILABLE(_version)

#endif /* !GM_VERSION_MIN_REQUIRED */
