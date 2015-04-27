//
//  AudioRecorder.m
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/21.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import "AudioRecorder.h"

@implementation AudioRecorder
{
    AudioStreamBasicDescription _description;
    
    NSString*       _path;
    ExtAudioFileRef _audioFile;
}

static OSStatus renderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    if (inRefCon       == NULL) return noErr;
    if (ioData         == nil)  return noErr;
    if (inNumberFrames <= 0)    return noErr;
    if (*ioActionFlags & kAudioUnitRenderAction_PreRender) return noErr;
    
    OSStatus status = noErr;
    
    AudioRecorder* this = (__bridge AudioRecorder*)inRefCon;
    
    if (!this->isRecording) return noErr;
    
    status = ExtAudioFileWriteAsync(this->_audioFile, inNumberFrames, ioData);
    if (status != noErr) NSLog(@"E:AEAudioFileWriterAddAudio %d", status);
    
    return status;
}

- (AudioRecorder*)initWithAudioDescription:(AudioStreamBasicDescription)description
{
    if (!(self = [super init]))
        return nil;
    
    _description = description;
    isRecording  = false;
    
    return self;
}

- (BOOL)beginRecordingToFileAtPath:(NSString*)path fileType:(AudioFileTypeID)fileType error:(NSError**)error
{
    isRecording = true;
    currentTime = 0.0;
    _audioFile  = NULL;
    _path       = path;
    
    NSFileManager* manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:_path]) {
        NSError* e;
        [manager removeItemAtPath:_path error:&e];
        if (e != nil)
            NSLog(@"%@", e.description);
    }
    
    OSStatus status;
    
    AudioStreamBasicDescription audioDescription = _description;
    audioDescription.mFormatFlags = (fileType == kAudioFileAIFFType ? kLinearPCMFormatFlagIsBigEndian : 0) | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    audioDescription.mFormatID         = kAudioFormatLinearPCM;
    audioDescription.mBitsPerChannel   = 16;
    audioDescription.mChannelsPerFrame = _description.mChannelsPerFrame;
    audioDescription.mBytesPerPacket   =
    audioDescription.mBytesPerFrame    = _description.mChannelsPerFrame * (audioDescription.mBitsPerChannel / 8);
    audioDescription.mFramesPerPacket  = 1;
    
    ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], fileType, &audioDescription,
                                       NULL, kAudioFileFlags_EraseFile, &_audioFile);
    
    status = ExtAudioFileSetProperty(_audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &_description);
    if (status != noErr)
        ExtAudioFileDispose(_audioFile);
    
    ExtAudioFileWriteAsync(_audioFile, 0, NULL);
    
    return true;
}

- (void)finishRecording
{
    if (!isRecording) return;
    
    isRecording = false;
    
    ExtAudioFileDispose(_audioFile);
}

- (AURenderCallback)renderCallback
{
    return renderCallback;
}

@end
