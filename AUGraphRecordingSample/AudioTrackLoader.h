//
//  AudioTrackLoader.h
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioTrackLoader : NSOperation

- (id)initWithFileURL:(NSURL*)url targetAudioDescription:(AudioStreamBasicDescription)audioDescription;

@property (nonatomic, copy) void (^audioReceiverBlock)(AudioBufferList *audio, UInt32 lengthInFrames);
@property (nonatomic, readonly) AudioBufferList *bufferList;

@property (nonatomic, readonly) UInt32 lengthInFrames;
@property (nonatomic, strong, readonly) NSError *error;

@end
