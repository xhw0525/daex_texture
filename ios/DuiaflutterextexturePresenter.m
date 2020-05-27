//
//  DuiaflutterextexturePresenter.m
//  Pods
//
//  Created by xhw on 2020/5/15.
//

#import "DuiaflutterextexturePresenter.h"
#import <Foundation/Foundation.h>
//#import <OpenGLES/EAGL.h>
//#import <OpenGLES/ES2/gl.h>
//#import <OpenGLES/ES2/glext.h>
//#import <CoreVideo/CVPixelBuffer.h>
#import <UIKit/UIKit.h>
#import <SDWebImage/SDWebImageDownloader.h>
#import <SDWebImage/SDWebImageManager.h>


static uint32_t bitmapInfoWithPixelFormatType(OSType inputPixelFormat, bool hasAlpha){
    
    if (inputPixelFormat == kCVPixelFormatType_32BGRA) {
        uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
        if (!hasAlpha) {
            bitmapInfo = kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host;
        }
        return bitmapInfo;
    }else if (inputPixelFormat == kCVPixelFormatType_32ARGB) {
        uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Big;
        return bitmapInfo;
    }else{
        NSLog(@"不支持此格式");
        return 0;
    }
}

// alpha的判断
BOOL CGImageRefContainsAlpha(CGImageRef imageRef) {
    if (!imageRef) {
        return NO;
    }
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageRef);
    BOOL hasAlpha = !(alphaInfo == kCGImageAlphaNone ||
                      alphaInfo == kCGImageAlphaNoneSkipFirst ||
                      alphaInfo == kCGImageAlphaNoneSkipLast);
    return hasAlpha;
}
@interface DuiaflutterextexturePresenter()
@property (nonatomic) CVPixelBufferRef target;

@property (nonatomic,assign) CGSize size;
@property (nonatomic,assign) CGSize imageSize;//图片实际大小 px
@property(nonatomic,assign)Boolean useExSize;//是否使用外部设置的大小

@property(nonatomic,assign)Boolean iscopy;

//gif
@property (nonatomic, assign) Boolean asGif;//是否是gif
//下方是展示gif图相关的
@property (nonatomic, strong) CADisplayLink * displayLink;
@property (nonatomic, strong) NSMutableArray<NSDictionary*> *images;
@property (nonatomic, assign) int now_index;//当前展示的第几帧
@property (nonatomic, assign) CGFloat can_show_duration;//下一帧要展示的时间差


@end



@implementation DuiaflutterextexturePresenter


- (instancetype)initWithImageStr:(NSString*)imageStr size:(CGSize)size asGif:(Boolean)asGif {
    self = [super init];
    if (self){
        self.size = size;
        self.asGif = asGif;
        self.useExSize = YES;//默认使用外部传入的大小
        
        if ([imageStr hasPrefix:@"http://"]||[imageStr hasPrefix:@"https://"]) {
            [self loadImageWithStrFromWeb:imageStr];
        } else {
            [self loadImageWithStrForLocal:imageStr];
        }
    }
    return self;
}



-(void)dealloc{
    
}
- (CVPixelBufferRef)copyPixelBuffer {
    //copyPixelBuffer方法执行后 释放纹理id的时候会自动释放_target
    //如果没有走copyPixelBuffer方法时 则需要手动释放_target
    _iscopy = YES;
    //    CVPixelBufferRetain(_target);//运行发现 这里不用加;
    return _target;
}

-(void)dispose{
    self.displayLink.paused = YES;
    [self.displayLink invalidate];
    self.displayLink = nil;
    if (!_iscopy) {
        CVPixelBufferRelease(_target);
    }
}




// 此方法能还原真实的图片
- (CVPixelBufferRef)CVPixelBufferRefFromUiImage:(UIImage *)img size:(CGSize)size {
    if (!img) {
        return nil;
    }
    CGImageRef image = [img CGImage];
    
    //    CGSize size = CGSizeMake(5000, 5000);
//    CGFloat frameWidth = CGImageGetWidth(image);
//    CGFloat frameHeight = CGImageGetHeight(image);
    CGFloat frameWidth = size.width;
    CGFloat frameHeight = size.height;
    
    //兼容外部 不传大小
    if (frameWidth<=0 || frameHeight<=0) {
        if (img!=nil) {
            frameWidth = CGImageGetWidth(image);
            frameHeight = CGImageGetHeight(image);
        }else{
            frameWidth  = 1;
            frameHeight  = 1;
        }
    }else if (!self.useExSize && img!=nil) {//使用图片大小
        frameWidth = CGImageGetWidth(image);
        frameHeight = CGImageGetHeight(image);
    }
    
    
    BOOL hasAlpha = CGImageRefContainsAlpha(image);
    CFDictionaryRef empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             empty, kCVPixelBufferIOSurfacePropertiesKey,
                             nil];
    
    //    NSDictionary *options = @{
    //        (NSString *)kCVPixelBufferCGImageCompatibilityKey:@YES,
    //        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES,
    //        (NSString *)kCVPixelBufferIOSurfacePropertiesKey:[NSDictionary dictionary]
    //    };
    
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef) options, &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    uint32_t bitmapInfo = bitmapInfoWithPixelFormatType(kCVPixelFormatType_32BGRA, (bool)hasAlpha);
    CGContextRef context = CGBitmapContextCreate(pxdata, frameWidth, frameHeight, 8, CVPixelBufferGetBytesPerRow(pxbuffer), rgbColorSpace, bitmapInfo);
    //    CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, CVPixelBufferGetBytesPerRow(pxbuffer), rgbColorSpace, (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    
    CGContextConcatCTM(context, CGAffineTransformIdentity);
    CGContextDrawImage(context, CGRectMake(0, 0, frameWidth, frameHeight), image);
    
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}



#pragma mark - image
-(void)loadImageWithStrForLocal:(NSString*)imageStr{
    if (self.asGif) {
        self.images = [NSMutableArray array];
        [self sd_GIFImagesWithLocalNamed:imageStr];
    } else {
        UIImage *iamge = [UIImage imageNamed:imageStr];
        self.target = [self CVPixelBufferRefFromUiImage:iamge size:self.size];
    }
}
-(void)loadImageWithStrFromWeb:(NSString*)imageStr{
    __weak typeof(DuiaflutterextexturePresenter*) weakSelf = self;
    [[SDWebImageDownloader sharedDownloader] downloadImageWithURL:[NSURL URLWithString:imageStr] completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, BOOL finished) {
        if (weakSelf.asGif) {
            for (UIImage * uiImage in image.images) {
                NSDictionary *dic = @{
                    @"duration":@(image.duration*1.0/image.images.count),
                    @"image":uiImage
                };
                [weakSelf.images addObject:dic];
            }
            [weakSelf startGifDisplay];
        } else {
            weakSelf.target = [weakSelf CVPixelBufferRefFromUiImage:image size:weakSelf.size];
            if (weakSelf.updateBlock) {
                weakSelf.updateBlock();
            }
        }
        
    }];
   
}


-(void)updategif:(CADisplayLink*)displayLink{
    //    NSLog(@"123--->%f",displayLink.duration);
    if (self.images.count==0) {
        self.displayLink.paused = YES;
        [self.displayLink invalidate];
        self.displayLink = nil;
        return;
    }
    self.can_show_duration -=displayLink.duration;
    if (self.can_show_duration<=0) {
        NSDictionary*dic = [self.images objectAtIndex:self.now_index];
        
        if (_target &&!_iscopy) {
            CVPixelBufferRelease(_target);
        }
        self.target = [self CVPixelBufferRefFromUiImage:[dic objectForKey:@"image"] size:self.size];
        _iscopy = NO;
        self.updateBlock();
        
        self.now_index += 1;
        if (self.now_index>=self.images.count) {
            self.now_index = 0;
            //            self.displayLink.paused = YES;
            //            [self.displayLink invalidate];
            //            self.displayLink = nil;
        }
        self.can_show_duration = ((NSNumber*)[dic objectForKey:@"duration"]).floatValue;
    }
    
    
}
- (void)startGifDisplay {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updategif:)];
    //    self.displayLink.paused = YES;
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)sd_GifImagesWithLocalData:(NSData *)data {
    if (!data) {
        return;
    }
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    
    size_t count = CGImageSourceGetCount(source);
    
    UIImage *animatedImage;
    
    if (count <= 1) {
        animatedImage = [[UIImage alloc] initWithData:data];
    }
    else {
        //        CVPixelBufferRef targets[count];
        for (size_t i = 0; i < count; i++) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (!image) {
                continue;
            }
            
            UIImage *uiImage = [UIImage imageWithCGImage:image scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
            
            NSDictionary *dic = @{
                @"duration":@([self sd_frameDurationAtIndex:i source:source]),
                @"image":uiImage
            };
            [_images addObject:dic];
            
            CGImageRelease(image);
        }
        
    }
    
    CFRelease(source);
    [self startGifDisplay];
}

- (float)sd_frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source {
    float frameDuration = 0.1f;
    CFDictionaryRef cfFrameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil);
    NSDictionary *frameProperties = (__bridge NSDictionary *)cfFrameProperties;
    NSDictionary *gifProperties = frameProperties[(NSString *)kCGImagePropertyGIFDictionary];
    
    NSNumber *delayTimeUnclampedProp = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    if (delayTimeUnclampedProp) {
        frameDuration = [delayTimeUnclampedProp floatValue];
    }
    else {
        
        NSNumber *delayTimeProp = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
        if (delayTimeProp) {
            frameDuration = [delayTimeProp floatValue];
        }
    }
    
    if (frameDuration < 0.011f) {
        frameDuration = 0.100f;
    }
    
    CFRelease(cfFrameProperties);
    return frameDuration;
}

- (void)sd_GIFImagesWithLocalNamed:(NSString *)name {
    if ([name hasSuffix:@".gif"]) {
        name = [name  stringByReplacingCharactersInRange:NSMakeRange(name.length-4, 4) withString:@""];
    }
    CGFloat scale = [UIScreen mainScreen].scale;
    
    if (scale > 1.0f) {
        NSData *data = nil;
        if (scale>2.0f) {
            NSString *retinaPath = [[NSBundle mainBundle] pathForResource:[name stringByAppendingString:@"@3x"] ofType:@"gif"];
            data = [NSData dataWithContentsOfFile:retinaPath];
        }
        if (!data){
            NSString *retinaPath = [[NSBundle mainBundle] pathForResource:[name stringByAppendingString:@"@2x"] ofType:@"gif"];
            data = [NSData dataWithContentsOfFile:retinaPath];
        }
        
        if (!data) {
            NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"gif"];
            data = [NSData dataWithContentsOfFile:path];
        }
        
        if (data) {
            [self sd_GifImagesWithLocalData:data];
        }
        
    }
    else {
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"gif"];
        
        NSData *data = [NSData dataWithContentsOfFile:path];
        
        if (data) {
            [self sd_GifImagesWithLocalData:data];
        }
        
    }
}
@end
