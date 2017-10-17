//
//  ImageManager.m
//  SDLStreamingVideoExample
//
//  Created by Nicole on 10/12/17.
//  Copyright © 2017 Livio. All rights reserved.
//

#import "ImageManager.h"

@implementation ImageManager

+ (NSArray<SDLArtwork *> *)allImages {
    return @[[self.class sdlex_starImage]];
}

+ (NSString *)starImageName {
    return @"StarSoftButtonIcon";
}

+ (SDLImage *)starImage {
    SDLImage* image = [[SDLImage alloc] init];
    image.imageType = SDLImageTypeDynamic;
    image.value = [self.class starImageName];
    return image;
}

#pragma mark - Individual Images

+ (SDLArtwork *)sdlex_starImage {
    return [SDLArtwork artworkWithImage:[UIImage imageNamed:@"star_black_icon"] name:[self.class starImageName] asImageFormat:SDLArtworkImageFormatPNG];
}

#pragma mark - UIImage
+ (UIImage *)rectangleWithColor:(UIColor *)color width:(CGFloat)width height:(CGFloat)height {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0.0);

    CGRect rectangle = CGRectMake(0, 0, width, height);
    [color setFill];
    UIRectFill(rectangle);

    UIImage *rectangleImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return rectangleImage;
}

@end
