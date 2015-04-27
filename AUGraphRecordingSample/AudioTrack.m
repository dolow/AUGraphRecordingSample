//
//  AudioTrack.m
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import "AudioTrack.h"
#import "AudioTrackLoader.h"
#import <libkern/OSAtomic.h>

@implementation AudioTrack
{
    AudioBufferList*            _audioBuffer;
    UInt32                      _lengthInFrames;
    AudioStreamBasicDescription _audioDescription;
    volatile int32_t            _playhead;
}

@synthesize timestamp = _timestamp, bus = _bus, url = _url, loop=_loop, volume=_volume, playing=_playing, muted=_muted;
@dynamic duration, currentTime;

+ (id)audioTrackWithURL:(NSURL*)url mainAudioDescription:(AudioStreamBasicDescription)audioDescription error:(NSError**)error
{
    AudioTrack *player = [[self alloc] init];
    player->_volume = 1.0;
    player->_playing = YES;
    player->_audioDescription = audioDescription;
    player->_url = url;
    
    AudioTrackLoader *operation = [[AudioTrackLoader alloc] initWithFileURL:url targetAudioDescription:player->_audioDescription];
    [operation start];
    
    if (operation.error) {
        if (error)
            *error = operation.error;
        
        return nil;
    }
    
    player->_audioBuffer    = operation.bufferList;
    player->_lengthInFrames = operation.lengthInFrames;
    
    return player;
}

- (void)dealloc
{
    if (_audioBuffer) {
        for (int i = 0; i < _audioBuffer->mNumberBuffers; i++) {
            free(_audioBuffer->mBuffers[i].mData);
        }
        free(_audioBuffer);
    }
}

static OSStatus renderCallback(void* ref, AudioUnitRenderActionFlags *flag, const AudioTimeStamp *timestamp, UInt32 bus, UInt32 frames, AudioBufferList *buffer)
{
    AudioTrack* this = (__bridge AudioTrack*)ref;
    
    // set buffer memory buffer
    for (int i = 0; i < buffer->mNumberBuffers; i++)
        memset(buffer->mBuffers[i].mData, 0, buffer->mBuffers[i].mDataByteSize);
    
    if (!this->_playing)
        return noErr;
    
    int32_t playhead = this->_playhead;
    
    // set buffer pointers working
    char* audioRef[buffer->mNumberBuffers];
    for (int i = 0; i < buffer->mNumberBuffers; i++)
        audioRef[i] = buffer->mBuffers[i].mData;
    
    int bytesPerFrame   = this->_audioDescription.mBytesPerFrame;
    int remainingFrames = frames;
    
    // Copy audio in contiguous chunks, wrapping around if we're looping
    while (remainingFrames > 0) {
        // The number of frames left before the end of the audio
        int framesToCopy = MIN(remainingFrames, this->_lengthInFrames - playhead);
        
        for (int i = 0; i < buffer->mNumberBuffers; i++) {
            // head offset of original buffer
            const void* copySource = ((char*)this->_audioBuffer->mBuffers[i].mData) + playhead * bytesPerFrame;
            size_t      copyLength = framesToCopy * bytesPerFrame;
            memcpy(audioRef[i], copySource, copyLength);
            
            // Advance the output buffers
            audioRef[i] += copyLength;
        }
        
        // advance playhead
        remainingFrames -= framesToCopy;
        playhead        += framesToCopy;
        
        if (playhead >= this->_lengthInFrames) {
            // Reached the end of the audio - either loop, or stop
            if (this->_loop) {
                playhead = 0;
            }
            else {
                // Notify main thread that playback has finished
                this->_playing = NO;
                break;
            }
        }
    }
    
    this->_playhead = playhead;
    this->_timestamp.mSampleTime += frames;
    
    return noErr;
}

- (AURenderCallback)auRenderCallback
{
    return &renderCallback;
}

@end
