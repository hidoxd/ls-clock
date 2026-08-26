#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <substrate.h>
#import "Tweak.h"
#import <Foundation/Foundation.h>

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

static NSDictionary<NSString *, UIImage *> *sDigitCache = nil;

static UIImage *LoadImageAtPath(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

    if ([path.pathExtension.lowercaseString isEqualToString:@"gif"]) {
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!source) return nil;

        size_t count = CGImageSourceGetCount(source);
        if (count <= 1) {
            CFRelease(source);
            return [UIImage imageWithContentsOfFile:path];
        }

        NSMutableArray<UIImage *> *images = [NSMutableArray array];
        NSTimeInterval duration = 0;

        for (size_t i = 0; i < count; i++) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (image) {
                [images addObject:[UIImage imageWithCGImage:image]];
                CFRelease(image);
            }

            CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
            if (properties) {
                CFDictionaryRef gifProperties = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
                if (gifProperties) {
                    NSNumber *delayTime = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFUnclampedDelayTime);
                    if (!delayTime || [delayTime floatValue] == 0) {
                        delayTime = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFDelayTime);
                    }
                    duration += [delayTime doubleValue];
                }
                CFRelease(properties);
            }
        }

        CFRelease(source);
        return [UIImage animatedImageWithImages:images duration:duration > 0 ? duration : 0.1 * count];
    }

    return [UIImage imageWithContentsOfFile:path];
}

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:3.0];
        NSLog(@"[LSClock] Твик успешно инициализирован без блокировки SpringBoard.");
    });
}
