//
//  AudioTrack.h
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioTrack : NSObject

+ (id)audioTrackWithURL:(NSURL*)url mainAudioDescription:(AudioStreamBasicDescription)audioDescription error:(NSError**)error;

- (AURenderCallback)auRenderCallback;

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, readwrite) BOOL loop;
@property (nonatomic, readwrite) AudioTimeStamp timestamp;
@property (nonatomic, readwrite) int   bus;
@property (nonatomic, readwrite) float volume;
@property (nonatomic, readwrite) BOOL playing;
@property (nonatomic, readwrite) BOOL muted;

@end
