#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Speech/Speech.h>
#import <stdlib.h>
#import <string.h>

@interface NativeDesktopSpeechRecognizer : NSObject {
@public
    NSLock *_lock;
    NSMutableArray *_events;
    SFSpeechRecognizer *_recognizer;
    SFSpeechAudioBufferRecognitionRequest *_request;
    SFSpeechRecognitionTask *_task;
    AVAudioEngine *_engine;
    BOOL _listening;
    BOOL _ended;
    NSUInteger _generation;
}
- (void)enqueueType:(NSInteger)type
               text:(NSString *)text
              final:(BOOL)final
         confidence:(double)confidence;
- (void)finish;
- (void)stopAudio;
@end

@implementation NativeDesktopSpeechRecognizer
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _events = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)enqueueType:(NSInteger)type
               text:(NSString *)text
              final:(BOOL)final
         confidence:(double)confidence {
    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:type], @"type",
        [NSNumber numberWithBool:final], @"final",
        [NSNumber numberWithDouble:confidence], @"confidence",
        nil];
    if (text) {
        [event setObject:text forKey:@"text"];
    }
    [_lock lock];
    [_events addObject:event];
    [_lock unlock];
}

- (void)stopAudio {
    if (_engine) {
        [_engine stop];
        [[_engine inputNode] removeTapOnBus:0];
    }
}

- (void)finish {
    [_lock lock];
    BOOL shouldFinish = !_ended;
    if (shouldFinish) {
        _ended = YES;
        _listening = NO;
        [_events addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:3], @"type",
            [NSNumber numberWithBool:YES], @"final",
            [NSNumber numberWithDouble:-1.0], @"confidence",
            nil]];
    }
    [_lock unlock];
}

- (void)dealloc {
    [self stopAudio];
    [_task cancel];
    [_task release];
    [_request release];
    [_recognizer release];
    [_engine release];
    [_events release];
    [_lock release];
    [super dealloc];
}
@end

static NSString *native_desktop_string(const char *value) {
    if (!value) return nil;
    return [NSString stringWithUTF8String:value];
}

static void native_desktop_set_error(char **error_out, NSString *message) {
    if (error_out) {
        *error_out = message ? strdup([message UTF8String]) : NULL;
    }
}

static void native_desktop_wait(BOOL *done) {
    while (!*done) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

char *native_desktop_recognition_languages(void) {
    @autoreleasepool {
        NSMutableArray *identifiers = [NSMutableArray array];
        for (NSLocale *locale in [SFSpeechRecognizer supportedLocales]) {
            NSString *identifier = [[locale localeIdentifier]
                stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
            if (identifier) [identifiers addObject:identifier];
        }
        [identifiers sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        return strdup([[identifiers componentsJoinedByString:@"\n"] UTF8String]);
    }
}

int native_desktop_recognition_available(const char *language) {
    @autoreleasepool {
        NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:
            native_desktop_string(language) ?: @"en-US"] autorelease];
        SFSpeechRecognizer *recognizer = [[[SFSpeechRecognizer alloc] initWithLocale:locale] autorelease];
        return recognizer && recognizer.available ? 1 : 0;
    }
}

int native_desktop_recognition_permission(void) {
    SFSpeechRecognizerAuthorizationStatus speech = [SFSpeechRecognizer authorizationStatus];
    AVAuthorizationStatus microphone =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (speech == SFSpeechRecognizerAuthorizationStatusAuthorized &&
        microphone == AVAuthorizationStatusAuthorized) {
        return 2;
    }
    if (speech == SFSpeechRecognizerAuthorizationStatusDenied ||
        speech == SFSpeechRecognizerAuthorizationStatusRestricted ||
        microphone == AVAuthorizationStatusDenied ||
        microphone == AVAuthorizationStatusRestricted) {
        return 1;
    }
    return 0;
}

int native_desktop_recognition_request_permission(void) {
    @autoreleasepool {
        if ([SFSpeechRecognizer authorizationStatus] ==
            SFSpeechRecognizerAuthorizationStatusNotDetermined) {
            __block BOOL done = NO;
            [SFSpeechRecognizer requestAuthorization:
                ^(SFSpeechRecognizerAuthorizationStatus status) { done = YES; }];
            native_desktop_wait(&done);
        }

        if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] ==
            AVAuthorizationStatusNotDetermined) {
            __block BOOL done = NO;
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                    completionHandler:^(BOOL granted) { done = YES; }];
            native_desktop_wait(&done);
        }
        return native_desktop_recognition_permission();
    }
}

void *native_desktop_recognition_create(void) {
    return [[NativeDesktopSpeechRecognizer alloc] init];
}

int native_desktop_recognition_start(void *opaque, const char *language,
                                     int interim, char **error_out) {
    @autoreleasepool {
        if (error_out) *error_out = NULL;
        NativeDesktopSpeechRecognizer *state =
            (NativeDesktopSpeechRecognizer *)opaque;
        if (!state) {
            native_desktop_set_error(error_out, @"Speech recognizer is closed");
            return 0;
        }
        if (native_desktop_recognition_permission() != 2) {
            native_desktop_set_error(error_out,
                @"Speech recognition and microphone permission are required");
            return 0;
        }

        [state stopAudio];
        [state->_lock lock];
        state->_generation += 1;
        NSUInteger generation = state->_generation;
        [state->_lock unlock];
        [state->_task cancel];
        [state->_task release];
        [state->_request release];
        [state->_recognizer release];
        [state->_engine release];
        state->_task = nil;
        state->_request = nil;
        state->_recognizer = nil;
        state->_engine = nil;

        [state->_lock lock];
        [state->_events removeAllObjects];
        state->_ended = NO;
        state->_listening = NO;
        [state->_lock unlock];

        NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:
            native_desktop_string(language) ?: @"en-US"] autorelease];
        state->_recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
        if (!state->_recognizer || !state->_recognizer.available) {
            native_desktop_set_error(error_out,
                @"The requested macOS speech recognizer is unavailable");
            return 0;
        }

        state->_request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
        state->_request.shouldReportPartialResults = interim ? YES : NO;
        if ([state->_request respondsToSelector:@selector(setRequiresOnDeviceRecognition:)]) {
            state->_request.requiresOnDeviceRecognition = NO;
        }
        state->_engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *input = [state->_engine inputNode];
        AVAudioFormat *format = [input outputFormatForBus:0];
        if (!input || format.channelCount == 0) {
            native_desktop_set_error(error_out, @"No microphone input is available");
            return 0;
        }

        AVAudioNodeTapBlock tapBlock = ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            [state->_request appendAudioPCMBuffer:buffer];
        };
        BOOL tapInstalled = NO;
        NSError *tapError = nil;
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
        if (@available(macOS 27.0, *)) {
            tapInstalled = [input installTapOnBus:0 bufferSize:1024 format:format
                                            error:&tapError block:tapBlock];
        } else
#endif
        {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [input installTapOnBus:0 bufferSize:1024 format:format block:tapBlock];
#pragma clang diagnostic pop
            tapInstalled = YES;
        }
        if (!tapInstalled) {
            native_desktop_set_error(error_out,
                [tapError localizedDescription] ?: @"Could not install the microphone tap");
            return 0;
        }
        [state->_engine prepare];
        NSError *engineError = nil;
        if (![state->_engine startAndReturnError:&engineError]) {
            [input removeTapOnBus:0];
            native_desktop_set_error(error_out,
                [engineError localizedDescription] ?: @"Could not start microphone capture");
            return 0;
        }

        [state->_lock lock];
        state->_listening = YES;
        [state->_lock unlock];
        state->_task = [[state->_recognizer
            recognitionTaskWithRequest:state->_request
                         resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
            [state->_lock lock];
            BOOL current = generation == state->_generation;
            [state->_lock unlock];
            if (!current) return;
            if (result) {
                NSString *transcript = result.bestTranscription.formattedString;
                double confidence = -1.0;
                NSArray<SFTranscriptionSegment *> *segments =
                    result.bestTranscription.segments;
                if (segments.count > 0) {
                    double total = 0.0;
                    for (SFTranscriptionSegment *segment in segments) {
                        total += segment.confidence;
                    }
                    confidence = total / (double)segments.count;
                }
                if (transcript.length > 0) {
                    [state enqueueType:1 text:transcript
                                 final:result.final confidence:confidence];
                }
            }
            if (error) {
                [state enqueueType:2 text:[error localizedDescription]
                                 final:YES confidence:-1.0];
            }
            if (error || result.final) {
                [state stopAudio];
                [state finish];
            }
        }] retain];
        return 1;
    }
}

void native_desktop_recognition_stop(void *opaque) {
    NativeDesktopSpeechRecognizer *state =
        (NativeDesktopSpeechRecognizer *)opaque;
    if (!state) return;
    [state stopAudio];
    [state->_request endAudio];
}

void native_desktop_recognition_abort(void *opaque) {
    NativeDesktopSpeechRecognizer *state =
        (NativeDesktopSpeechRecognizer *)opaque;
    if (!state) return;
    [state->_lock lock];
    state->_generation += 1;
    [state->_lock unlock];
    [state stopAudio];
    [state->_task cancel];
    [state finish];
}

int native_desktop_recognition_listening(void *opaque) {
    NativeDesktopSpeechRecognizer *state =
        (NativeDesktopSpeechRecognizer *)opaque;
    if (!state) return 0;
    [state->_lock lock];
    BOOL listening = state->_listening;
    [state->_lock unlock];
    return listening ? 1 : 0;
}

int native_desktop_recognition_poll(void *opaque, char **text_out,
                                    int *final_out, double *confidence_out) {
    @autoreleasepool {
        NativeDesktopSpeechRecognizer *state =
            (NativeDesktopSpeechRecognizer *)opaque;
        if (!state) return 0;
        [state->_lock lock];
        NSDictionary *event = nil;
        if (state->_events.count > 0) {
            event = [[state->_events objectAtIndex:0] retain];
            [state->_events removeObjectAtIndex:0];
        }
        [state->_lock unlock];
        if (!event) return 0;

        NSString *text = [event objectForKey:@"text"];
        if (text_out) *text_out = text ? strdup([text UTF8String]) : NULL;
        if (final_out) *final_out = [[event objectForKey:@"final"] boolValue] ? 1 : 0;
        if (confidence_out) {
            *confidence_out = [[event objectForKey:@"confidence"] doubleValue];
        }
        int type = [[event objectForKey:@"type"] intValue];
        [event release];
        return type;
    }
}

void native_desktop_recognition_free_string(char *value) {
    free(value);
}

void native_desktop_recognition_close(void *opaque) {
    NativeDesktopSpeechRecognizer *state =
        (NativeDesktopSpeechRecognizer *)opaque;
    if (!state) return;
    native_desktop_recognition_abort(state);
    [state release];
}
