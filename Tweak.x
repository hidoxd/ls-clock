#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <substrate.h>

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

// Функция декодирования GIF-файла в анимированный UIImage
static UIImage *AnimatedGIFFromFilePath(NSString *filePath) {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (!source) return nil;

    size_t count = CGImageSourceGetCount(source);
    if (count <= 1) {
        UIImage *singleImage = [UIImage imageWithContentsOfFile:filePath];
        CFRelease(source);
        return singleImage;
    }

    NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval totalDuration = 0.0;

    for (size_t i = 0; i < count; i++) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (imageRef) {
            [images addObject:[UIImage imageWithCGImage:imageRef]];
            CGImageRelease(imageRef);
        }

        // Вычисляем длительность отображения кадров
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        if (properties) {
            CFDictionaryRef gifProperties = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
            if (gifProperties) {
                NSNumber *delay = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFUnclampedDelayTime);
                if (!delay || delay.floatValue <= 0) {
                    delay = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFDelayTime);
                }
                totalDuration += delay.doubleValue;
            }
            CFRelease(properties);
        }
    }
    CFRelease(source);

    if (totalDuration == 0) totalDuration = (1.0 / 10.0) * count; // Запасной интервал

    return [UIImage animatedImageWithImages:images duration:totalDuration];
}

// Кэш для анимированных цифр
static NSMutableDictionary<NSString *, UIImage *> *digitImageCache = nil;

static void LoadDigitImagesIfNeeded() {
    if (digitImageCache) return;
    digitImageCache = [NSMutableDictionary new];
    
    NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");
    
    for (int i = 0; i <= 9; i++) {
        // Ищем .gif файлы цифр (0.gif, 1.gif ... 9.gif)
        NSString *fileName = [NSString stringWithFormat:@"%d.gif", i];
        NSString *fullPath = [basePath stringByAppendingPathComponent:fileName];
        
        UIImage *animatedGIF = AnimatedGIFFromFilePath(fullPath);
        if (animatedGIF) {
            digitImageCache[@(i).stringValue] = animatedGIF;
        }
    }
}
