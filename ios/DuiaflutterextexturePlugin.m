#import "DuiaflutterextexturePlugin.h"
#import "DuiaflutterextexturePresenter.h"

@interface DuiaflutterextexturePlugin()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, DuiaflutterextexturePresenter *> *renders;
@property (nonatomic, strong) NSObject<FlutterTextureRegistry> *textures;
@end

@implementation DuiaflutterextexturePlugin
- (instancetype)initWithTextures:(NSObject<FlutterTextureRegistry> *)textures {
    self = [super init];
    if (self) {
        _renders = [[NSMutableDictionary alloc] init];
        _textures = textures;
    }
    return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"duia_texture_channel"
            binaryMessenger:[registrar messenger]];
  DuiaflutterextexturePlugin* instance = [[DuiaflutterextexturePlugin alloc] initWithTextures:[registrar textures]];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"create" isEqualToString:call.method]) {
      NSString *imageStr = call.arguments[@"img"];
      Boolean asGif = [call.arguments[@"asGif"] boolValue];
      CGFloat width = [call.arguments[@"width"] floatValue]*[UIScreen mainScreen].scale;
      CGFloat height = [call.arguments[@"height"] floatValue]*[UIScreen mainScreen].scale;

      CGSize size = CGSizeMake(width, height);
      
      DuiaflutterextexturePresenter *render = [[DuiaflutterextexturePresenter alloc] initWithImageStr:imageStr size:size asGif:asGif];
      int64_t textureId = [self.textures registerTexture:render];

      render.updateBlock = ^{
          [self.textures textureFrameAvailable:textureId];
      };
      

      [_renders setObject:render forKey:@(textureId)];
      
      result(@(textureId));
  }else if ([@"dispose" isEqualToString:call.method]) {
      if (call.arguments[@"textureId"]!=nil && ![call.arguments[@"textureId"] isKindOfClass:[NSNull class]]) {
          DuiaflutterextexturePresenter *render = [_renders objectForKey:call.arguments[@"textureId"]];
          [_renders removeObjectForKey:call.arguments[@"textureId"]];
          [render dispose];
          NSNumber*numb =  call.arguments[@"textureId"];
          if (numb) {
              [self.textures unregisterTexture:numb.longLongValue];
          }
      }
      
  }else {
      result(FlutterMethodNotImplemented);
  }
}

-(void)refreshTextureWithTextureId:(int64_t)textureId{
    
}
@end
