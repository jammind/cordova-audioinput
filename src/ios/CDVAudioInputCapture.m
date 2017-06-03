/********* CDVAudioInputCapture.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import "XMNAudioRecorder.h"
#import <Foundation/Foundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <AVFoundation/AVFoundation.h>
#import <Cordova/CDVPlugin.h>
#import "CDVFile.h"
#import "HWWeakTimer.h"


@interface CDVAudioInputCapture : CDVPlugin <XMNAudioRecorderDelegate> {
}

@property (strong) NSString* callbackId;
@property (strong, nonatomic) XMNAudioRecorder *recorder;
@property (strong, nonatomic) NSString *filename;
@property (strong, nonatomic) NSString *filepath;
@property (weak, nonatomic) NSTimer *timer;
@property (assign,nonatomic) BOOL doNotSaveFile;

- (void)start:(CDVInvokedUrlCommand*)command;
- (void)stop:(CDVInvokedUrlCommand*)command;
- (void)startRecording:(CDVInvokedUrlCommand*)command;

@end

@implementation NSBundle (PluginExtensions)
    
+ (NSBundle*) pluginBundle:(CDVPlugin*)plugin {
    NSBundle* bundle = [NSBundle bundleWithPath: [[NSBundle mainBundle] pathForResource:NSStringFromClass([plugin class]) ofType: @"bundle"]];
    return bundle;
}
@end
#define PluginLocalizedString(plugin, key, comment) [[NSBundle pluginBundle:(plugin)] localizedStringForKey:(key) value:nil table:nil]

@implementation CDVAudioInputCapture

- (void)pluginInitialize {
    NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];

    [listener addObserver:self
                 selector:@selector(didEnterBackground)
                     name:UIApplicationDidEnterBackgroundNotification
                   object:nil];

    [listener addObserver:self
                 selector:@selector(willEnterForeground)
                     name:UIApplicationWillEnterForegroundNotification
                   object:nil];
}


- (void)start:(CDVInvokedUrlCommand*)command {
    self.callbackId = command.callbackId;
    [self startRecording:command];
}


- (void)startRecording:(CDVInvokedUrlCommand*)command {
    self.filename = [command.arguments objectAtIndex:5];
    self.filepath = [command.arguments objectAtIndex:6];

    self.doNotSaveFile = NO;
    
    NSDate *startTime = [NSDate date];
    NSDate *lastTime = [[NSUserDefaults standardUserDefaults] valueForKey:@"startTime"];
    if (!lastTime) {
        lastTime = [NSDate distantPast];
    }
    NSTimeInterval timeInterval = [startTime timeIntervalSinceDate:lastTime];
    if (timeInterval > 0.5) {
        [[NSUserDefaults standardUserDefaults] setValue:startTime forKey:@"startTime"];
    } else {
        return;
    }

    //如果js端传过来的filename或filepath为空，则用默认的路径，并去掉cordova默认路径当中的file://
    //filename后面需要加上mp3的后缀
    if (![self.filepath isEqual:[NSNull null]]
        &&
        ![self.filename isEqual:[NSNull null]]) {
        
        NSRange fileStr = [self.filepath rangeOfString:@"file://"];
        if (fileStr.length) {
            if (fileStr.location == 0) {
                self.filepath = [self.filepath stringByReplacingOccurrencesOfString:@"file://" withString:@""];
            }
        }
        
        NSRange externsion = [self.filename rangeOfString:@".mp3"];
        if (externsion.length == 0) {
            self.filename = [self.filename stringByAppendingString:@".mp3"];
        }

        if (!self.recorder) {
            self.recorder = [[XMNAudioRecorder alloc] initWithFilePath:self.filepath];
        }
        [self setupRecorder];
        [self sendStartRecording];
        [self.commandDelegate runInBackground:^{
            [self.recorder startRecordingWithFileName:self.filename];
        }];
    
    } else if ([self.filepath isEqual:[NSNull null]]    //filepath为空
               &&
               ![self.filename isEqual:[NSNull null]]) {
        
        NSRange externsion = [self.filename rangeOfString:@".mp3"];
        if (externsion.length == 0) {
            self.filename = [self.filename stringByAppendingString:@".mp3"];
        }
        if (!self.recorder) {
            self.recorder = [[XMNAudioRecorder alloc] init];
        }
        [self setupRecorder];
        [self sendStartRecording];
        [self.commandDelegate runInBackground:^{
            [self.recorder startRecordingWithFileName:self.filename];
        }];

    } else if (![self.filepath isEqual:[NSNull null]]   //filename为空
               &&
               [self.filename isEqual:[NSNull null]]) {

        NSRange fileStr = [self.filepath rangeOfString:@"file://"];
        if (fileStr.length) {
            if (fileStr.location == 0) {
                self.filepath = [self.filepath stringByReplacingOccurrencesOfString:@"file://" withString:@""];
            }
        }
        
        if (!self.recorder) {
            self.recorder = [[XMNAudioRecorder alloc] initWithFilePath:self.filepath];
        }
        [self setupRecorder];
        [self sendStartRecording];
        [self.commandDelegate runInBackground:^{
            [self.recorder startRecording];
        }];

    } else {
        self.filepath = @"";
        self.filename = @"";
        self.doNotSaveFile = YES;
        if (!self.recorder) {
            self.recorder = [[XMNAudioRecorder alloc] init];
        }
        [self setupRecorder];
        [self sendStartRecording];
        [self.commandDelegate runInBackground:^{
            [self.recorder startRecording];
        }];
    }

}
    
- (void)setupRecorder {
    self.recorder.encoderType = XMNAudioEncoderTypeMP3;
    self.recorder.sampleRate = 44100;
    self.recorder.delegate = self;
    self.recorder.maxSeconds = 30.0;
}

- (void)sendStartRecording {

    _timer = [HWWeakTimer scheduledTimerWithTimeInterval:0.2f block:^(id userInfo) {
        NSLog(@"HWWeakTimer = %f", [self.recorder updateVolumn]);
        
        // -120表示完全安静，0表示最大输入值,1表示还没有开始
//        NSInteger imageIndex = 0;
//        
//        if (_avgPower >= -45 && _avgPower < -35)
//            imageIndex = 1;
//        else if (_avgPower >= -35 && _avgPower < -25)
//            imageIndex = 2;
//        else if (_avgPower >= -25 && _avgPower < -15)
//            imageIndex = 3;
//        else if (_avgPower >= -15)
//            imageIndex = 4;

        CGFloat volumn = [self.recorder updateVolumn];
        
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDouble:volumn];
        [result setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
    } userInfo:@"Fire" repeats:YES];
    [_timer fire];
}

- (void)stop:(CDVInvokedUrlCommand*)command {
    self.callbackId = command.callbackId;
    [self.commandDelegate runInBackground:^{
        [_timer invalidate];
        if (self.doNotSaveFile) {
            [self.recorder stopRecordingAndDeleteFile];
        } else {
            [self stopRecordIngImp];
            [self.recorder stopRecording];
        }
    }];
}

- (void)stopRecordIngImp {
    if (self.callbackId) {
        NSString* filePath = @"";
        //如果js端传过来的filename或filepath为空，则用默认的路径，并去掉cordova默认路径当中的file://
        if (self.filepath.length > 0
            &&
            self.filename.length > 0) {
            filePath = [self.filepath stringByAppendingString:self.filename];
            NSRange fileStr = [filePath rangeOfString:@"file://"];
            if (fileStr.length) {
                if (fileStr.location == 0) {
                    filePath = [filePath stringByReplacingOccurrencesOfString:@"file://" withString:@""];
                }
            }
        } else {
            filePath = [self.recorder stopRecordingWithFileName];
        }
        NSDictionary* fileDict = [self getMediaDictionaryFromPath:filePath ofType:@"audio/mp3"];
        NSArray* fileArray = [NSArray arrayWithObject:fileDict];
        
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:fileArray];
        [result setKeepCallbackAsBool:NO];
        [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
    }
}

- (NSDictionary*)getMediaDictionaryFromPath:(NSString*)fullPath ofType:(NSString*)type {
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSMutableDictionary* fileDict = [NSMutableDictionary dictionaryWithCapacity:5];
    
    CDVFile *fs = [self.commandDelegate getCommandInstance:@"File"];
    
    // Get canonical version of localPath
    NSURL *fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", fullPath]];
    NSURL *resolvedFileURL = [fileURL URLByResolvingSymlinksInPath];
    NSString *path = [resolvedFileURL path];
    
    CDVFilesystemURL *url = [fs fileSystemURLforLocalPath:path];
    
    [fileDict setObject:[fullPath lastPathComponent] forKey:@"name"];
    [fileDict setObject:fullPath forKey:@"fullPath"];
    if (url) {
        [fileDict setObject:[url absoluteURL] forKey:@"localURL"];
    }
    // determine type
    if (!type) {
        id command = [self.commandDelegate getCommandInstance:@"File"];
        if ([command isKindOfClass:[CDVFile class]]) {
            CDVFile* cdvFile = (CDVFile*)command;
            NSString* mimeType = [cdvFile getMimeTypeFromPath:fullPath];
            [fileDict setObject:(mimeType != nil ? (NSObject*)mimeType : [NSNull null]) forKey:@"type"];
        }
    }
    NSDictionary* fileAttrs = [fileMgr attributesOfItemAtPath:fullPath error:nil];
    [fileDict setObject:[NSNumber numberWithUnsignedLongLong:[fileAttrs fileSize]] forKey:@"size"];
    NSDate* modDate = [fileAttrs fileModificationDate];
    NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970] * 1000];
    [fileDict setObject:msDate forKey:@"lastModifiedDate"];
    
    return fileDict;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];

    [self stop:nil];
}

- (void)onReset {
    [self stop:nil];
}

- (void)didEnterBackground {
    [self.recorder stopRecording];
}

- (void)willEnterForeground {
//    [self.recorder startRecording];
}

#pragma mark - XMNAudioRecorderDelegate
/** 录音成功后回调 */
- (void)didRecordFinishWithRecorder:(XMNAudioRecorder * _Nonnull)recorder {
    
    [self.commandDelegate runInBackground:^{
        if (self.callbackId) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:0.0f];
            [result setKeepCallbackAsBool:NO];
            [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
        }
        
        self.callbackId = nil;
    }];
}
/** 录音失败后的回调 */
- (void)recorder:(XMNAudioRecorder * _Nonnull )recorder didRecordError:(NSError * _Nullable)error {
    [self.commandDelegate runInBackground:^{
        @try {
            if (self.callbackId) {
                NSDictionary* errorData = [NSDictionary dictionaryWithObject:[NSString stringWithString:error.description] forKey:@"error"];
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:errorData];
                [result setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
            }
        }
        @catch (NSException *exception) {
            if (self.callbackId) {
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                            messageAsString:@"Exception in didEncounterError"];
                [result setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
            }
        }
    }];

}

@end
