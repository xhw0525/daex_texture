flutter与原生混合开发中,关于资源图片的存储
####情况一:flutter于原生各存一份
优点:使用方便,flutter 与 原生 各自负责自己的加载;
缺点:占用体积大, APP包 和 运行时内存 都会存在2份图片资源

####情况二:只原生存一份,使用二进制文件传输给flutter
优点:APP包里面只有1份资源图片
缺点:运行时内容还是会有2份资源图片的 占用;

####情况三:只原生存一份,使用"外接纹理"传输给flutter
优点1:APP包里面只有1份资源图片, 内存中也只存在1份资源;
优点2:原生平台通过外接纹理共享内存给flutter;
缺点:目前这方面的文档还很少,用的人还不多;可能会踩坑

###简单介绍一下外接纹理的东西
长话短说:
1.就是iOS端把图片UIImage写进一块特定的"内存区域",
2.flutter端可以直接从那块"内存区域"读取,
3.然后绘画(或者叫渲染)到手机屏幕上

###此处应该有一张思维导图
(目前还没画, 后面有机会再补一张吧;)
直入正题,看代码 https://github.com/xhw0525/daex_texture
###dart代码:(关键代码)

BPage.dart
```
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BPage extends StatefulWidget {
  BPage({Key key}) : super(key: key);
  @override
  _BPageState createState() => _BPageState();
}

class _BPageState extends State<BPage> {
  MethodChannel _channel = MethodChannel('duia_texture_channel');//名称随意, 2端统一就好

  int daTextureId = -1; //系统返回的正常id会大于等于0, -1则可以认为 还未加载纹理

  @override
  void initState() {
    super.initState();

    newTexture();
  }

  @override
  void dispose() {
    super.dispose();
    if (daTextureId>=0){
      _channel.invokeMethod('dispose', {'textureId': daTextureId});

    }
  }

  void newTexture() async {
    daTextureId = await _channel.invokeMethod('create', {
      'img':'123.gif',//本地图片名
      'width': 200,
      'height': 300,
      'asGif':true,//是否是gif,也可以不这样处理, 平台端也可以自动判断
    });
    setState(() {
    });
  }

  Widget getTextureBody(BuildContext context) {
    return Container(
      // color: Colors.red,
      width: 300,
      height: 300,
      child: Texture(
        textureId: daTextureId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = daTextureId>=0 ? getTextureBody(context) : Text('loading...');

    return Scaffold(
      appBar: AppBar(
        title: Text("daex_texture"),
      ),
      body: Container(
        height: 500,
        width: 500,
        child: body,
      ),
    );
  }
}

```

###iOS(关键代码)
DuiaflutterextexturePlugin.m
```
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
```





