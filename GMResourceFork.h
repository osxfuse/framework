//
//  GMResourceFork.h
//  OSXFUSE
//

//  Copyright (c) 2016 Benjamin Fleischer.
//  All rights reserved.

//  OSXFUSE.framework is based on MacFUSE.framework. MacFUSE.framework is
//  covered under the following BSD-style license:
//
//  Copyright (c) 2007 Google Inc.
//  All rights reserved.
//
//  Redistribution  and  use  in  source  and  binary  forms,  with  or  without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the  above  copyright  notice,
//     this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//  3. Neither the name of Google Inc. nor the names of its contributors may  be
//     used to endorse or promote products derived from  this  software  without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS  IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT  LIMITED  TO,  THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A  PARTICULAR  PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT  OWNER  OR  CONTRIBUTORS  BE
//  LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,   OR
//  CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT  LIMITED  TO,  PROCUREMENT  OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,  OR  PROFITS;  OR  BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY  THEORY  OF  LIABILITY,  WHETHER  IN
//  CONTRACT, STRICT LIABILITY, OR  TORT  (INCLUDING  NEGLIGENCE  OR  OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  OF  THE
//  POSSIBILITY OF SUCH DAMAGE.

/*!
 * @header GMResourceFork
 *
 * A utility class to construct raw resource fork data.
 * 
 * In OS 10.4, the ResourceFork for a file may be present in an AppleDouble (._) 
 * file that is associated with the file. In 10.5+, the ResourceFork is present 
 * in the com.apple.ResourceFork extended attribute on a file.
 */

#import <Foundation/Foundation.h>

#import <OSXFUSE/GMAvailability.h>

#define GM_EXPORT __attribute__((visibility("default")))

@class GMResource;

/*!
 * @class
 * @discussion This class can be used to construct raw NSData for a resource 
 * fork. For more information about resource forks, see the CarbonCore/Finder.h 
 * header file.
 */
GM_EXPORT @interface GMResourceFork : NSObject {
 @private
  NSMutableDictionary* resourcesByType_;
}

/*! @abstract Returns an autoreleased GMResourceFork */
+ (GMResourceFork *)resourceFork GM_AVAILABLE(2_0);

/*! 
 * @abstract Adds a resource to the resource fork by specifying components.
 * @discussion See CarbonCore/Finder.h for some common resource identifiers.
 * @param resType The four-char code for the resource, e.g. 'icns'
 * @param resID The ID of the resource, e.g. 256 for webloc 'url' contents
 * @param name The name of the resource; may be nil (retained)
 * @param data The raw data for the resource (retained)
 */
- (void)addResourceWithType:(ResType)resType
                      resID:(ResID)resID
                       name:(NSString *)name
                       data:(NSData *)data GM_AVAILABLE(2_0);

/*! 
 * @abstract Adds a resource to the resource fork.
 * @discussion See CarbonCore/Finder.h for some common resource identifiers.
 * @param resource The resource to add.
 */
- (void)addResource:(GMResource *)resource GM_AVAILABLE(2_0);

/*! 
 * @abstract Constucts the raw data for the resource fork.
 * @result NSData for the resource fork containing all added resources.
 */
- (NSData *)data GM_AVAILABLE(2_0);

@end

/*!
 * @class
 * @discussion This class represents a single resource in a resource fork.
 */
GM_EXPORT @interface GMResource : NSObject {
 @private
  ResType resType_;  // FourCharCode, i.e. 'icns'
  ResID resID_;    // SInt16, i.e. 256 for webloc 'url ' contents.
  NSString* name_;  // Retained: The name of the resource.
  NSData* data_;  // Retained: The raw data for the resource.
}

/*! 
 * @abstract Returns an autoreleased resource by specifying components.
 * @discussion See CarbonCore/Finder.h for some common resource identifiers.
 * @param resType The four-char code for the resource, e.g. 'icns'
 * @param resID The ID of the resource, e.g. 256 for webloc 'url' contents
 * @param name The name of the resource; may be nil (retained)
 * @param data The raw data for the resource (retained)
 */
+ (GMResource *)resourceWithType:(ResType)resType
                           resID:(ResID)resID
                            name:(NSString *)name  // May be nil
                            data:(NSData *)data GM_AVAILABLE(2_0);

/*! 
 * @abstract Initializes a resource by specifying components.
 * @discussion See CarbonCore/Finder.h for some common resource identifiers.
 * @param resType The four-char code for the resource, e.g. 'icns'
 * @param resID The ID of the resource, e.g. 256 for webloc 'url' contents
 * @param name The name of the resource; may be nil (retained)
 * @param data The raw data for the resource (retained)
 */
- (id)initWithType:(ResType)resType
             resID:(ResID)resID 
              name:(NSString *)name  // May be nil
              data:(NSData *)data GM_AVAILABLE(2_0);

/*! @abstract The resource ID */
- (ResID)resID GM_AVAILABLE(2_0);

/*! @abstract The four-char code resource type */
- (ResType)resType GM_AVAILABLE(2_0);

/*! @abstract The resource name or nil if none */
- (NSString *)name GM_AVAILABLE(2_0);

/*! @abstract The resource data */
- (NSData *)data GM_AVAILABLE(2_0);

@end

#undef GM_EXPORT
