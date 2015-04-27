//
//  AppDelegate.m
//  AUGraphRecordingSample
//
//  Created by kuwabara yuki on 2015/04/27.
//  Copyright (c) 2015年 kuwabara yuki. All rights reserved.
//

#import "AppDelegate.h"

#import "ViewController.h"

@implementation AppDelegate

@synthesize window         = _window;
@synthesize viewController = _viewController;


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    
    // Create and display view controller
    self.viewController = [[ViewController alloc] init];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
