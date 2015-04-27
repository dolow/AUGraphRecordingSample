//
//  ViewController.m
//  AUGraphRecordingSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 kuwabara yuki. All rights reserved.
//

#import "ViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "AudioController.h"
#import "AudioRecorder.h"
#import "AudioTrack.h"


@interface ViewController ()
{
    NSString* _fileOutputPath;
}
@property (nonatomic, strong) AudioController* audioController;
@property (nonatomic, strong) AudioRecorder*   recorder;
@property (nonatomic, strong) AudioTrack*      track;

@property (nonatomic, strong) AVAudioPlayer* player;

@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *playButton;

@end

@implementation ViewController

- (NSString*)fileOutPutPath
{
    if (_fileOutputPath == nil) {
        NSArray *documentsFolders = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _fileOutputPath = [documentsFolders[0] stringByAppendingPathComponent:@"Recording.aiff"];
    }
    
    return _fileOutputPath;
}

- (id)init
{
    if ( !(self = [super init]) ) return nil;
    
    _fileOutputPath = nil;
    
    AudioStreamBasicDescription description = [AudioController defaultAudioDescriptionLinearPCM16bit];
    _audioController = [[AudioController alloc] initWithAudioDescription:description inputEnabled:YES];
    
    _track = [AudioTrack audioTrackWithURL:[[NSBundle mainBundle] URLForResource:@"drum" withExtension:@"mp3"]
                            mainAudioDescription:description
                                           error:NULL];
    
    _track.volume = 1.0;
    _track.muted  = YES;
    _track.loop   = YES;
    
    // Create a group for loop1, loop2 and oscillator
    [_audioController addTrack:_track];
    
    return self;
}

-(void)dealloc
{
    [_audioController removeObserver:self forKeyPath:@"numberOfInputChannels"];
    [_audioController clearTracks];
}

- (void)record:(id)sender
{
    if (_recorder != nil) {
        [_recorder finishRecording];
        [_audioController removeRecorder:_recorder];
        
        _recorder = nil;
        _recordButton.selected = NO;
    }
    else {
        _recorder = [[AudioRecorder alloc] initWithAudioDescription:_audioController.audioDescription];
        
        NSError *error = nil;
        bool result = [_recorder beginRecordingToFileAtPath:[self fileOutPutPath] fileType:kAudioFileAIFFType error:&error];
        if (!result) {
            NSLog(@"Couldn't start recording: %@", [error localizedDescription]);
            _recorder = nil;
            return;
        }
        
        [_audioController setRecorder:_recorder];
        
        _recordButton.selected = YES;
    }
}

- (void)play:(id)sender
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self fileOutPutPath]]) return;
    
    if ([_player isPlaying]) {
        [_player stop];
        _playButton.selected = false;
    }
    else {
        NSError* e;
        
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[self fileOutPutPath]] error:&e];
        if (e) NSLog(@"%@", e.description);
        
        [_player setDelegate:self];
        [_player prepareToPlay];
        [_player play];
        
        _playButton.selected = true;
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    _playButton.selected = false;
}

- (void)trackMuteSwitchChanged:(UISwitch*)sender { _track.muted = !sender.isOn; }


-(void)viewDidLoad
{
    [super viewDidLoad];
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 20)];
    headerView.backgroundColor = [UIColor groupTableViewBackgroundColor];
    
    self.tableView.tableHeaderView = headerView;
    
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 80)];
    self.recordButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_recordButton setTitle:@"Record" forState:UIControlStateNormal];
    [_recordButton setTitle:@"Stop" forState:UIControlStateSelected];
    [_recordButton addTarget:self action:@selector(record:) forControlEvents:UIControlEventTouchUpInside];
    _recordButton.frame = CGRectMake(20, 10, ((footerView.bounds.size.width-50) / 2), footerView.bounds.size.height - 20);
    _recordButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
    
    self.playButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_playButton setTitle:@"Play" forState:UIControlStateNormal];
    [_playButton setTitle:@"Stop" forState:UIControlStateSelected];
    [_playButton addTarget:self action:@selector(play:) forControlEvents:UIControlEventTouchUpInside];
    _playButton.frame = CGRectMake(CGRectGetMaxX(_recordButton.frame)+10, 10, ((footerView.bounds.size.width-50) / 2), footerView.bounds.size.height - 20);
    _playButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
    
    [footerView addSubview:_recordButton];
    [footerView addSubview:_playButton];
    self.tableView.tableFooterView = footerView;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [[cell viewWithTag:1] removeFromSuperview];
    
    switch (indexPath.section) {
        case 0: {
            cell.accessoryView = [[UISwitch alloc] initWithFrame:CGRectZero];
            
            switch (indexPath.row) {
                case 0: {
                    cell.textLabel.text = @"Drums";
                    ((UISwitch*)cell.accessoryView).on = !_track.muted;
                    [((UISwitch*)cell.accessoryView) addTarget:self action:@selector(trackMuteSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                    break;
                }
            }
            break;
        }
    }
    
    return cell;
}

@end
