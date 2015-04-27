//
//  AudioController.m
//  TheEngineSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AudioController.h"

static const int    kMaximumChannelsPerGroup = 100;
static const UInt32 kMaxFramesPerSlice       = 4096;

static void * kChannelPropertyChanged = &kChannelPropertyChanged;

@implementation AudioController
{
    AUGraph   _audioGraph;
    
    AUNode    _ioNode;
    AudioUnit _ioAudioUnit;
    
    AUNode    _mixerNode;
    AudioUnit _mixerAudioUnit;
    
    AUNode    _converterNode;
    AudioUnit _converterUnit;
    
    int           _trackCount;
    AudioTrack* _tracks[kMaximumChannelsPerGroup];
}

@dynamic running;

+ (AudioStreamBasicDescription)defaultAudioDescriptionLinearPCM16bit
{
    AudioStreamBasicDescription audioDescription;
    memset(&audioDescription, 0, sizeof(audioDescription));
    audioDescription.mFormatID         = kAudioFormatLinearPCM;
    audioDescription.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsNonInterleaved;
    audioDescription.mChannelsPerFrame = 2;
    audioDescription.mBytesPerPacket   = sizeof(SInt16);
    audioDescription.mFramesPerPacket  = 1;
    audioDescription.mBytesPerFrame    = sizeof(SInt16);
    audioDescription.mBitsPerChannel   = 8 * sizeof(SInt16);
    audioDescription.mSampleRate       = 44100.0;
    return audioDescription;
}

- (id)initWithAudioDescription:(AudioStreamBasicDescription)audioDescription inputEnabled:(BOOL)enableInput
{
    if (!(self = [super init])) return nil;
    
    NSAssert(audioDescription.mFormatID == kAudioFormatLinearPCM, @"Only linear PCM supported");
    
    _audioDescription = audioDescription;
    
    [self initAudioSession];
    
    [self createAUGraph];
    
    [self initMixer];
    
    // initialize the AUGraph
    AUGraphInitialize(_audioGraph);
    AUGraphStart(_audioGraph);

    return self;
}

- (void)initAudioSession
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    NSError *error = nil;
    if (![audioSession setPreferredSampleRate:_audioDescription.mSampleRate error:&error])
        NSLog(@"TAAE: Couldn't set preferred sample rate: %@", error);
    
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [audioSession setActive:YES error:nil];
    
    if ([audioSession respondsToSelector:@selector(requestRecordPermission:)])
        [audioSession requestRecordPermission:^(BOOL granted) {}];
}

- (void)createAUGraph
{
    do {
        // Create a new AUGraph
        OSStatus result = NewAUGraph(&_audioGraph);
        if (!checkStatus(result, "NewAUGraph"))
            break;
        
        // Input/output unit description
        AudioComponentDescription ioComponentDescription = {
            .componentType = kAudioUnitType_Output,
            .componentSubType = kAudioUnitSubType_RemoteIO,
            .componentManufacturer = kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0
        };
        
        // Create a node in the graph that is an AudioUnit, using the supplied AudioComponentDescription to find and open that unit
        result = AUGraphAddNode(_audioGraph, &ioComponentDescription, &_ioNode);
        if (!checkStatus(result, "AUGraphAddNode io"))
            break;
        
        // Open the graph - AudioUnits are open but not initialized (no resource allocation occurs here)
        result = AUGraphOpen(_audioGraph);
        if (!checkStatus(result, "AUGraphOpen"))
            break;
        
        // Get reference to IO audio unit
        result = AUGraphNodeInfo(_audioGraph, _ioNode, NULL, &_ioAudioUnit);
        if (!checkStatus(result, "AUGraphNodeInfo"))
            break;
        
            // Enable input
        UInt32 enableInputFlag = 1;
        AudioUnitSetProperty(_ioAudioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableInputFlag, sizeof(enableInputFlag));
        
        AudioStreamBasicDescription audioDescription = _audioDescription;
        
        UInt32 size = sizeof(audioDescription);
        AudioUnitGetProperty(_ioAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, &size);
    } while(0);
}

- (void)initMixer
{
    // Load existing interactions
    UInt32 numInteractions = kMaximumChannelsPerGroup*2;
    AUNodeInteraction interactions[numInteractions];
    checkStatus(AUGraphGetNodeInteractions(_audioGraph, _ioNode, &numInteractions, interactions), "AUGraphGetNodeInteractions");
    
    // Find the existing upstream connection
    AUNodeInteraction upstreamInteraction;
    
    int targetBus = 0;
    
    // Create mixer node if necessary
    AudioComponentDescription mixerComponentDescription = {
        .componentType = kAudioUnitType_Mixer,
        .componentSubType = kAudioUnitSubType_MultiChannelMixer,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    // Add mixer node to graph
    checkStatus(AUGraphAddNode(_audioGraph, &mixerComponentDescription, &_mixerNode), "AUGraphAddNode mixer");
    checkStatus(AUGraphNodeInfo(_audioGraph, _mixerNode, NULL, &_mixerAudioUnit), "AUGraphNodeInfo");
    
    // Set the mixer unit to handle up to 4096 frames per slice to keep rendering during screen lock
    AudioUnitSetProperty(_mixerAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &kMaxFramesPerSlice, sizeof(kMaxFramesPerSlice));
    
    // Set bus count
    UInt32 busCount = 1;
    checkStatus(AudioUnitSetProperty(_mixerAudioUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &busCount, sizeof(busCount)), "AudioUnitSetProperty(kAudioUnitProperty_ElementCount)");
    
    AudioStreamBasicDescription mixerDescription = _audioDescription;
    
    // Assign the output format if necessary
    OSStatus result = AudioUnitSetProperty(_mixerAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &mixerDescription, sizeof(mixerDescription));
    
    if (!_converterNode && result == kAudioUnitErr_FormatNotSupported) {
        AudioStreamBasicDescription converterDescription = _audioDescription;
        
        AudioComponentDescription converterComponentDescription;
        memset(&converterComponentDescription, 0, sizeof(converterComponentDescription));
        converterComponentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
        converterComponentDescription.componentType         = kAudioUnitType_FormatConverter;
        converterComponentDescription.componentSubType      = kAudioUnitSubType_AUConverter;
        
        if (!checkStatus(AUGraphAddNode(_audioGraph, &converterComponentDescription, &_converterNode), "AUGraphAddNode") ||
            !checkStatus(AUGraphNodeInfo(_audioGraph, _converterNode, NULL, &_converterUnit), "AUGraphNodeInfo")) {
            AUGraphRemoveNode(_audioGraph, _converterNode);
            _converterNode = 0;
            _converterUnit = NULL;
        }
        
        // Set the audio unit to handle up to 4096 frames per slice to keep rendering during screen lock
        checkStatus(AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &kMaxFramesPerSlice, sizeof(kMaxFramesPerSlice)),
                    "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice)");
        
        checkStatus(AUGraphConnectNodeInput(_audioGraph, _mixerNode, 0, _converterNode, 0), "AUGraphConnectNodeInput");
        
        if (_converterNode) {
            // Set the audio converter stream format
            checkStatus(AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &converterDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)");
            checkStatus(AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &_audioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)");
        }
    }
    
    AUNode sourceNode = _converterNode ? _converterNode : _mixerNode;
    
    // Connect output of mixer/converter directly to the upstream node
    checkStatus(AUGraphConnectNodeInput(_audioGraph, sourceNode, 0, _ioNode, targetBus), "AUGraphConnectNodeInput");
    upstreamInteraction.nodeInteractionType = kAUNodeInteraction_Connection;
    
    // Set the master volume
    checkStatus(AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, 1.0, 0), "AudioUnitSetParameter(kMultiChannelMixerParam_Volume)");
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self stop];
    checkStatus(AUGraphClose(_audioGraph), "AUGraphClose");
    checkStatus(DisposeAUGraph(_audioGraph), "DisposeAUGraph");
    
    _audioGraph = NULL;
    _ioAudioUnit = NULL;
}

- (void)stop
{
    checkStatus(AUGraphStop(_audioGraph), "AUGraphStop");
    
    if (self.running)
        checkStatus(AudioOutputUnitStop(_ioAudioUnit), "AudioOutputUnitStop");
    
    NSError *error = nil;
    if (![((AVAudioSession*)[AVAudioSession sharedInstance]) setActive:NO error:&error])
        NSLog(@"TAAE: Couldn't deactivate audio session: %@", error);
}


- (int)addTrack:(AudioTrack*)track
{
    [(NSObject*)track addObserver:self forKeyPath:@"muted" options:0 context:kChannelPropertyChanged];
    
    track.bus = _trackCount;
    _tracks[_trackCount++] = track;
    
    // make output with preloaded audio buffer list
    AURenderCallback callback = [track auRenderCallback];
    AURenderCallbackStruct rcbs = { .inputProc = callback, .inputProcRefCon = (__bridge void *)(track) };
    checkStatus(AUGraphSetNodeInputCallback(_audioGraph, _mixerNode, track.bus, &rcbs), "AUGraphSetNodeInputCallback");
    
    // volume
    checkStatus(AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, track.bus, 1.0f, 0),
                "AudioUnitSetParameter(kMultiChannelMixerParam_Volume)");
    // pan
    checkStatus(AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Pan, kAudioUnitScope_Input, track.bus, 0, 0),
                "AudioUnitSetParameter(kMultiChannelMixerParam_Pan)");
    // disenable output
    checkStatus(AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, track.bus, 0, 0),
                "AudioUnitSetParameter(kMultiChannelMixerParam_Enable)");
    // audio description
    checkStatus(AudioUnitSetProperty(_mixerAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, track.bus, &_audioDescription, sizeof(_audioDescription)),
                "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)");
    
    checkStatus([self updateGraph], "Update graph");
    
    return track.bus;
}

- (void)removeTrack:(int)bus
{
    AudioTrack* removingChannel = nil;
    
    for (int index = 0; index < _trackCount; index++) {
        if (!_tracks[index]) continue;
        if (_tracks[index].bus != bus) continue;
        
        AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, index, 0, 0);
    }
    
    for (int index = 0; index < _trackCount; index++) {
        if (!_tracks[index]) continue;
        if (_tracks[index].bus != bus) continue;
        
        removingChannel = _tracks[index];
        
        // Shuffle the later elements backwards one space
        for (int j = index; j < _trackCount - 1; j++)
            _tracks[j] = _tracks[j + 1];
        
        _tracks[_trackCount-1] = NULL;
        _trackCount--;
    }
    
    checkStatus([self updateGraph], "Update graph");
    
    // Release channel resources
    if (removingChannel)
        [(NSObject*)removingChannel removeObserver:self forKeyPath:@"muted"];
}
- (void)clearTracks
{
    for (int index = 0; index < _trackCount; index++) {
        if (!_tracks[index]) continue;
        AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, index, 0, 0);
    }
    
    for (int index = 0; index < _trackCount; index++) {
        if (!_tracks[index]) continue;
        [(NSObject*)_tracks[index] removeObserver:self forKeyPath:@"muted"];
        _tracks[index] = NULL;
    }
    
    _trackCount = 0;
    
    checkStatus([self updateGraph], "Update graph");
}

- (void)setRecorder:(AudioRecorder*)recorder
{
    checkStatus(AudioUnitAddRenderNotify(_converterUnit, recorder.renderCallback, (__bridge void *)recorder), "AudioUnitAddRenderNotify");
}

- (void)removeRecorder:(AudioRecorder*)recorder
{
    checkStatus(AudioUnitRemoveRenderNotify(_converterUnit, recorder.renderCallback, (__bridge void*)recorder), "AudioUnitRemoveRenderNotify");
}

- (BOOL)running
{
    Boolean topAudioUnitIsRunning;
    UInt32 size = sizeof(topAudioUnitIsRunning);
    if (checkStatus(AudioUnitGetProperty(_ioAudioUnit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &topAudioUnitIsRunning, &size), "kAudioOutputUnitProperty_IsRunning")) {
        return topAudioUnitIsRunning;
    }
    
    return NO;
}

- (OSStatus)updateGraph
{
    if (self.running) {
        // Retry a few times (as sometimes the graph will be in the wrong state to update)
        OSStatus err = noErr;
        for ( int retry=0; retry<6; retry++ ) {
            err = AUGraphUpdate(_audioGraph, NULL);
            if (err != kAUGraphErr_CannotDoInCurrentContext) break;
            [NSThread sleepForTimeInterval:0.01];
        }
        
        return err;
    }
    return noErr;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kChannelPropertyChanged) {
        if (![keyPath isEqualToString:@"muted"]) return;
        if (!_mixerAudioUnit) return;
        
        AudioTrack* channel = (AudioTrack*)object;
        
        AudioUnitParameterValue value = channel.playing && !channel.muted;
        AudioUnitSetParameter(_mixerAudioUnit, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, channel.bus, value, 0);
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


@end
