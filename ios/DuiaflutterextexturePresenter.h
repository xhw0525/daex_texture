//
//  DuiaflutterextexturePresenter.h
//  Pods
//
//  Created by xhw on 2020/5/15.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>


@interface DuiaflutterextexturePresenter : NSObject <FlutterTexture>


@property(copy,nonatomic) void(^updateBlock) (void);

- (instancetype)initWithImageStr:(NSString*)imageStr size:(CGSize)size asGif:(Boolean)asGif;

-(void)dispose;
@end


