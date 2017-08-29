//
//  ProxyManager.m
//  SDLStreamingVideoExample
//
//  Created by Nicole on 8/4/17.
//  Copyright © 2017 Livio. All rights reserved.
//

#import "SmartDeviceLink.h"
#import "ProxyManager.h"
#import "VideoManager.h"

NSString *const SDLAppName = @"SDLVideo";
NSString *const SDLAppId = @"2776";
NSString *const SDLIPAddress = @"192.168.1.236";
UInt16 const SDLPort = (UInt16)2776;

BOOL const ShouldRestartOnDisconnect = NO;

typedef NS_ENUM(NSUInteger, SDLHMIFirstState) {
    SDLHMIFirstStateNone,
    SDLHMIFirstStateNonNone,
    SDLHMIFirstStateFull
};

typedef NS_ENUM(NSUInteger, SDLHMIInitialShowState) {
    SDLHMIInitialShowStateNone,
    SDLHMIInitialShowStateDataAvailable,
    SDLHMIInitialShowStateShown
};


NS_ASSUME_NONNULL_BEGIN

@interface ProxyManager () <SDLManagerDelegate>

// Describes the first time the HMI state goes non-none and full.
@property (assign, nonatomic) SDLHMIFirstState firstTimeState;
@property (assign, nonatomic) SDLHMIInitialShowState initialShowState;
@property (nonatomic, nullable) id videoPeriodicTimer;

@end


@implementation ProxyManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static ProxyManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[ProxyManager alloc] init];
    });

    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _state = ProxyStateStopped;
    _firstTimeState = SDLHMIFirstStateNone;
    _initialShowState = SDLHMIInitialShowStateNone;

    return self;
}

- (void)startIAP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];

    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration defaultConfigurationWithAppName:SDLAppName appId:SDLAppId]];

    // Assume this is production and disable logging
    lifecycleConfig.logFlags = SDLLogOutputNone;

    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfig lockScreen:[SDLLockScreenConfiguration enabledConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startTCP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];

    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration debugConfigurationWithAppName:SDLAppName appId:SDLAppId ipAddress:SDLIPAddress port:SDLPort]];
    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfig lockScreen:[SDLLockScreenConfiguration enabledConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startManager {
    __weak typeof (self) weakSelf = self;
    [self.sdlManager startWithReadyHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSLog(@"SDL errored starting up: %@", error);
            [weakSelf sdlex_updateProxyState:ProxyStateStopped];
            return;
        }

        NSLog(@"SDL Connected");
        [weakSelf sdlex_updateProxyState:ProxyStateConnected];
    }];
}

- (void)reset {
    [self sdlex_updateProxyState:ProxyStateStopped];
    [self.sdlManager stop];
    // Remove reference
    self.sdlManager = nil;
}

#pragma mark - Helpers

+ (SDLLifecycleConfiguration *)sdlex_setLifecycleConfigurationPropertiesOnConfiguration:(SDLLifecycleConfiguration *)config {

    config.shortAppName = @"Video";
    config.voiceRecognitionCommandNames = @[@"S D L Video"];
    config.ttsName = [SDLTTSChunk textChunksFromString:config.shortAppName];
    config.appType = [SDLAppHMIType NAVIGATION];

    return config;
}

/**
 KVO for the proxy state. The proxy can change between being connected, stopped, and searching for connection.

 @param newState The new proxy state
 */
- (void)sdlex_updateProxyState:(ProxyState)newState {
    if (self.state != newState) {
        [self willChangeValueForKey:@"state"];
        _state = newState;
        [self didChangeValueForKey:@"state"];
    }
}

#pragma mark - SDLManagerDelegate

- (void)managerDidDisconnect {
    // Reset our state
    self.firstTimeState = SDLHMIFirstStateNone;
    self.initialShowState = SDLHMIInitialShowStateNone;
    self.videoPeriodicTimer = nil;
    [VideoManager.sharedManager reset];
    [self sdlex_updateProxyState:ProxyStateStopped];
    if (ShouldRestartOnDisconnect) {
        [self startManager];
    }
}

- (void)hmiLevel:(SDLHMILevel *)oldLevel didChangeToLevel:(SDLHMILevel *)newLevel {
    if (![newLevel isEqualToEnum:[SDLHMILevel NONE]] && (self.firstTimeState == SDLHMIFirstStateNone)) {
        // This is our first time in a non-NONE state
        self.firstTimeState = SDLHMIFirstStateNonNone;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sdlex_stopStreamingVideo) name:UIApplicationWillResignActiveNotification object:nil];
    }

    if ([newLevel isEqualToEnum:[SDLHMILevel FULL]] && (self.firstTimeState != SDLHMIFirstStateFull)) {
        // This is our first time in a FULL state
        self.firstTimeState = SDLHMIFirstStateFull;
    }

    if ([newLevel isEqualToEnum:[SDLHMILevel FULL]] || [newLevel isEqualToEnum:[SDLHMILevel LIMITED]]) {
        // We're always going to try to show the initial state, because if we've already shown it, it won't be shown, and we need to guard against some possible weird states
        [self sdlex_setupStreamingVideo];
    }else{
        [self sdlex_stopStreamingVideo];
    }
}

#pragma mark - Streaming Video

/**
 *  Sets up the buffer to send the video to SDL Core.
 */
- (void)sdlex_setupStreamingVideo {
    if (self.videoPeriodicTimer != nil) { return; }

    if (VideoManager.sharedManager.player == nil) {
        // Video player is not yet setup
        [self registerForNotificationWhenVideoStartsPlaying];
    } else if (VideoManager.sharedManager.player.rate == 1.0) {
        // Video is already playing, setup the buffer to send video to SDL Core
        [self sdlex_startStreamingVideo];
    } else {
        // Video player is setup but nothing is playing yet
        [self registerForNotificationWhenVideoStartsPlaying];
    }
}

/**
 *  Registers for a callback when the video player starts playing
 */
- (void)registerForNotificationWhenVideoStartsPlaying {
    // Video is not yet playing. Register to get a notification when video starts playing
    VideoManager.sharedManager.videoStreamingStartedHandler = ^{
        [self sdlex_startStreamingVideo];
    };
}

/**
 *  Registers for a callback from the video player on each new video frame. When the notification is received, an image is created from the current video frame and sent to the SDL Core.
 */
- (void)sdlex_startStreamingVideo {
    if (self.videoPeriodicTimer != nil) { return; }

    [self.sdlManager.streamManager startVideoSessionWithStartBlock:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            if (error) {
                NSLog(@"Error starting video session. %@", error.localizedDescription);
            }
        }
    }];

    __weak typeof(self) weakSelf = self;
    self.videoPeriodicTimer = [VideoManager.sharedManager.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            // Due to an iOS limitation of VideoToolbox's encoder and openGL, video streaming can not happen in the background
            NSLog(@"Video streaming can not occur in background");
            self.videoPeriodicTimer = nil;
            return;
        }
        // Grab an image of the current video frame and send it to SDL Core
        CVPixelBufferRef buffer = [VideoManager.sharedManager getPixelBuffer];
        [weakSelf sdlex_sendVideo:buffer];
        [VideoManager.sharedManager releasePixelBuffer:buffer];
    }];
}

/**
 *  Stops registering for a callback from the video player on each new video frame.
 */
- (void)sdlex_stopStreamingVideo {
    if (self.videoPeriodicTimer == nil) { return; }
    [VideoManager.sharedManager.player removeTimeObserver:self.videoPeriodicTimer];
    self.videoPeriodicTimer = nil;
}

/**
 *  Send the video to SDL Core

 @param imageBuffer  The image(s) to send to SDL Core
 */
- (void)sdlex_sendVideo:(CVPixelBufferRef)imageBuffer {
    if (imageBuffer == nil || [self.sdlManager.hmiLevel isEqualToEnum:[SDLHMILevel NONE]] || [self.sdlManager.hmiLevel isEqualToEnum:[SDLHMILevel BACKGROUND]]) {
        // Video can only be sent when HMI level is full or limited
        return;
    }

    Boolean success = [self.sdlManager.streamManager sendVideoData:imageBuffer];
    NSLog(@"Video was sent %@", success ? @"successfully" : @"unsuccessfully");
}

@end

NS_ASSUME_NONNULL_END
