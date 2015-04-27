//
//  AudioRecorder.h
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/21.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AudioRecorder : NSObject
{
    bool   isRecording;
    double currentTime;
}

- (AudioRecorder*)initWithAudioDescription:(AudioStreamBasicDescription)description;
- (BOOL)beginRecordingToFileAtPath:(NSString*)path fileType:(AudioFileTypeID)fileType error:(NSError**)error;

- (void)finishRecording;

- (AURenderCallback)renderCallback;

@end
