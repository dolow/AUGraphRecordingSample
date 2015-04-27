//
//  AudioTrackLoader.m
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import "AudioTrackLoader.h"

static inline bool checkStatus(OSStatus result, const char* description)
{
    if (result != noErr) {
        NSLog(@"%s:%d: %s result %d", __FILE__, __LINE__, description, (int)result);
        return false;
    }
    return true;
}

static const int kMaxAudioFileReadSize = 16384;

@interface AudioTrackLoader ()
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) AudioStreamBasicDescription targetAudioDescription;
@property (nonatomic, readwrite) AudioBufferList *bufferList;
@property (nonatomic, readwrite) UInt32 lengthInFrames;
@property (nonatomic, strong, readwrite) NSError *error;
@end

@implementation AudioTrackLoader

static inline AudioBufferList *allocateAndInitAudioBufferList(AudioStreamBasicDescription audioFormat, int frameCount)
{
    int numberOfBuffers = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? audioFormat.mChannelsPerFrame : 1;
    int channelsPerBuffer = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? 1 : audioFormat.mChannelsPerFrame;
    int bytesPerBuffer = audioFormat.mBytesPerFrame * frameCount;
    
    AudioBufferList *audio = malloc(sizeof(AudioBufferList) + (numberOfBuffers-1)*sizeof(AudioBuffer));
    if ( !audio ) {
        return NULL;
    }
    audio->mNumberBuffers = numberOfBuffers;
    for ( int i=0; i<numberOfBuffers; i++ ) {
        if ( bytesPerBuffer > 0 ) {
            audio->mBuffers[i].mData = calloc(bytesPerBuffer, 1);
            if ( !audio->mBuffers[i].mData ) {
                for ( int j=0; j<i; j++ ) free(audio->mBuffers[j].mData);
                free(audio);
                return NULL;
            }
        } else {
            audio->mBuffers[i].mData = NULL;
        }
        audio->mBuffers[i].mDataByteSize = bytesPerBuffer;
        audio->mBuffers[i].mNumberChannels = channelsPerBuffer;
    }
    return audio;
}


@synthesize url = _url, targetAudioDescription = _targetAudioDescription, bufferList = _bufferList, lengthInFrames = _lengthInFrames, error = _error;

-(id)initWithFileURL:(NSURL *)url targetAudioDescription:(AudioStreamBasicDescription)audioDescription
{
    if (!(self = [super init])) return nil;
    
    self.url = url;
    self.targetAudioDescription = audioDescription;
    
    return self;
}


-(void)main {
    ExtAudioFileRef audioFile;
    OSStatus status;
    
    // Open file
    status = ExtAudioFileOpenURL((__bridge CFURLRef)_url, &audioFile);
    if (!checkStatus(status, "ExtAudioFileOpenURL")) {
        self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                     userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Couldn't open the audio file", @"")}];
        return;
    }
    
    // Get file data format
    AudioStreamBasicDescription fileAudioDescription;
    UInt32 size = sizeof(fileAudioDescription);
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &size, &fileAudioDescription);
    if (!checkStatus(status, "ExtAudioFileGetProperty(kExtAudioFileProperty_FileDataFormat)")) {
        ExtAudioFileDispose(audioFile);
        self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                     userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Couldn't read the audio file", @"")}];
        return;
    }
    
    // Apply client format
    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(_targetAudioDescription), &_targetAudioDescription);
    if (!checkStatus(status, "ExtAudioFileSetProperty(kExtAudioFileProperty_ClientDataFormat)")) {
        ExtAudioFileDispose(audioFile);
        int fourCC = CFSwapInt32HostToBig(status);
        self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"Couldn't convert the audio file (error %d/%4.4s)", @""), status, (char*)&fourCC]}];
        return;
    }
    
    // Determine length in frames (in original file's sample rate)
    UInt64 fileLengthInFrames;
    size = sizeof(fileLengthInFrames);
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &size, &fileLengthInFrames);
    if (!checkStatus(status, "ExtAudioFileGetProperty(kExtAudioFileProperty_FileLengthFrames)")) {
        ExtAudioFileDispose(audioFile);
        self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                     userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Couldn't read the audio file", @"")}];
        return;
    }
    
    // Calculate the true length in frames, given the original and target sample rates
    fileLengthInFrames = ceil(fileLengthInFrames * (_targetAudioDescription.mSampleRate / fileAudioDescription.mSampleRate));
    
    // Prepare buffers
    int channelsPerBuffer = (_targetAudioDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : _targetAudioDescription.mChannelsPerFrame;
    AudioBufferList *bufferList = allocateAndInitAudioBufferList(_targetAudioDescription, (UInt32)fileLengthInFrames);
    if (!bufferList) {
        ExtAudioFileDispose(audioFile);
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM
                                     userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Not enough memory to open file", @"")}];
        return;
    }
    
    AudioBufferList *scratchBufferList = allocateAndInitAudioBufferList(_targetAudioDescription, 0);
    
    // Perform read in multiple small chunks (otherwise ExtAudioFileRead crashes when performing sample rate conversion)
    UInt64 readFrames = 0;
    while (readFrames < fileLengthInFrames && ![self isCancelled]) {
        for ( int i=0; i<scratchBufferList->mNumberBuffers; i++ ) {
            scratchBufferList->mBuffers[i].mNumberChannels = channelsPerBuffer;
            scratchBufferList->mBuffers[i].mData = (char*)bufferList->mBuffers[i].mData + readFrames*_targetAudioDescription.mBytesPerFrame;
            scratchBufferList->mBuffers[i].mDataByteSize = (UInt32)MIN(kMaxAudioFileReadSize, (fileLengthInFrames-readFrames) * _targetAudioDescription.mBytesPerFrame);
        }
        
        // Perform read
        UInt32 numberOfPackets = (UInt32)(scratchBufferList->mBuffers[0].mDataByteSize / _targetAudioDescription.mBytesPerFrame);
        status = ExtAudioFileRead(audioFile, &numberOfPackets, scratchBufferList);
        
        if ( status != noErr ) {
            ExtAudioFileDispose(audioFile);
            int fourCC = CFSwapInt32HostToBig(status);
            self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"Couldn't read the audio file (error %d/%4.4s)", @""), status, (char*)&fourCC]}];
            return;
        }
        
        if (numberOfPackets == 0)
            break;
        
        readFrames += numberOfPackets;
    }
    
    free(scratchBufferList);
    
    // Clean up
    ExtAudioFileDispose(audioFile);
    
    if ([self isCancelled]) {
        if (bufferList) {
            for (int i = 0; i < bufferList->mNumberBuffers; i++) {
                free(bufferList->mBuffers[i].mData);
            }
            free(bufferList);
            bufferList = NULL;
        }
    }
    else {
        _bufferList = bufferList;
        _lengthInFrames = (UInt32)fileLengthInFrames;
    }
}

@end
