//
//  AudioController.h
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "AudioTrack.h"
#import "AudioRecorder.h"

static inline bool checkStatus(OSStatus result, const char* description)
{
    if (result != noErr) {
        NSLog(@"%s:%d: %s result %d", __FILE__, __LINE__, description, (int)result);
        return false;
    }
    return true;
}

@interface AudioController : NSObject

+ (AudioStreamBasicDescription)defaultAudioDescriptionLinearPCM16bit;

- (id)initWithAudioDescription:(AudioStreamBasicDescription)audioDescription inputEnabled:(BOOL)enableInput;

- (void)stop;

- (int)addTrack:(AudioTrack*)track;
- (void)removeTrack:(int)bus;
- (void)clearTracks;

- (void)setRecorder:(AudioRecorder*)recorder;
- (void)removeRecorder:(AudioRecorder*)recorder;

//- (void)addMicRecorder:(Rec*)recorder;
//- (void)removeMicRecorder:(Rec*)recorder;

@property (nonatomic, readonly) BOOL running;

@property (nonatomic, readonly) AudioStreamBasicDescription audioDescription;

@property (nonatomic, readonly) AudioUnit audioUnit;
@property (nonatomic, readonly) AUGraph audioGraph;

@end
