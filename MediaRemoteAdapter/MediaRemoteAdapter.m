//
//  MediaRemoteAdapter.m
//  Mac灵动岛
//
//  Since macOS 15.4, mediaremoted only answers now-playing queries from Apple-signed
//  processes. This library is loaded into /usr/bin/perl (see NowPlayingManager) and
//  streams the system-wide now-playing state to stdout, one JSON object per line.
//  The process exits when its stdin is closed, i.e. when the app goes away.
//

#import <Foundation/Foundation.h>

typedef void (*MRGetNowPlayingInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetNowPlayingClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRRegisterForNotificationsFn)(dispatch_queue_t);
typedef CFStringRef (*MRClientStringFn)(id);

static MRGetNowPlayingInfoFn MRGetNowPlayingInfo;
static MRGetNowPlayingClientFn MRGetNowPlayingClient;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRClientStringFn MRClientGetBundleIdentifier;
static MRClientStringFn MRClientGetParentAppBundleIdentifier;

static dispatch_queue_t queue;
static NSData *lastLine;
static BOOL refreshScheduled;

static void writeLine(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json || [json isEqualToData:lastLine]) return;
    lastLine = json;

    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];
    const uint8_t *bytes = line.bytes;
    size_t remaining = line.length;
    while (remaining > 0) {
        ssize_t written = write(STDOUT_FILENO, bytes, remaining);
        if (written <= 0) exit(0); // The app closed the pipe.
        bytes += written;
        remaining -= (size_t)written;
    }
}

static void emitSnapshot(void) {
    __block NSDictionary *info = nil;
    __block NSString *bundleID = nil;
    __block NSString *parentBundleID = nil;
    __block BOOL isPlaying = NO;

    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    MRGetNowPlayingInfo(queue, ^(CFDictionaryRef raw) {
        info = [(__bridge NSDictionary *)raw copy];
        dispatch_group_leave(group);
    });

    dispatch_group_enter(group);
    MRGetNowPlayingClient(queue, ^(id client) {
        if (client) {
            bundleID = [(__bridge NSString *)MRClientGetBundleIdentifier(client) copy];
            if (MRClientGetParentAppBundleIdentifier) {
                parentBundleID = [(__bridge NSString *)MRClientGetParentAppBundleIdentifier(client) copy];
            }
        }
        dispatch_group_leave(group);
    });

    dispatch_group_enter(group);
    MRGetIsPlaying(queue, ^(Boolean playing) {
        isPlaying = playing;
        dispatch_group_leave(group);
    });

    dispatch_group_notify(group, queue, ^{
        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        if (info.count > 0) {
            payload[@"playing"] = @(isPlaying);
            if (bundleID) payload[@"bundleID"] = bundleID;
            if (parentBundleID) payload[@"parentBundleID"] = parentBundleID;

            NSDictionary<NSString *, NSString *> *keys = @{
                @"kMRMediaRemoteNowPlayingInfoTitle": @"title",
                @"kMRMediaRemoteNowPlayingInfoArtist": @"artist",
                @"kMRMediaRemoteNowPlayingInfoAlbum": @"album",
                @"kMRMediaRemoteNowPlayingInfoDuration": @"duration",
                @"kMRMediaRemoteNowPlayingInfoElapsedTime": @"elapsed",
                @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @"rate",
            };
            [keys enumerateKeysAndObjectsUsingBlock:^(NSString *mrKey, NSString *jsonKey, BOOL *stop) {
                id value = info[mrKey];
                if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
                    payload[jsonKey] = value;
                }
            }];

            // Elapsed time was sampled at this moment, not when we read it.
            id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
            if ([timestamp isKindOfClass:NSDate.class]) {
                payload[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
            }

            id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if ([artwork isKindOfClass:NSData.class] && [(NSData *)artwork length] > 0) {
                payload[@"artwork"] = [(NSData *)artwork base64EncodedStringWithOptions:0];
            }
        }
        writeLine(payload);
    });
}

// Change notifications arrive in bursts (app, info and playing state together); coalesce them.
static void scheduleSnapshot(void) {
    dispatch_async(queue, ^{
        if (refreshScheduled) return;
        refreshScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), queue, ^{
            refreshScheduled = NO;
            emitSnapshot();
        });
    });
}

static void exitWithParent(void) {
    dispatch_source_t stdinSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    dispatch_source_set_event_handler(stdinSource, ^{
        char buffer[256];
        if (read(STDIN_FILENO, buffer, sizeof buffer) <= 0) exit(0);
    });
    dispatch_resume(stdinSource);

    // Backstop in case EOF is never delivered: once the app dies we are re-parented to launchd.
    pid_t parent = getppid();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (getppid() != parent) exit(0);
    });
    dispatch_resume(timer);

    // Keep the sources alive for the life of the process.
    CFBridgingRetain(stdinSource);
    CFBridgingRetain(timer);
}

static BOOL loadMediaRemote(void) {
    NSURL *url = [NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"];
    CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)url);
    if (!bundle) return NO;

    MRGetNowPlayingInfo = (MRGetNowPlayingInfoFn)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingInfo"));
    MRGetNowPlayingClient = (MRGetNowPlayingClientFn)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingClient"));
    MRGetIsPlaying = (MRGetIsPlayingFn)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingApplicationIsPlaying"));
    MRClientGetBundleIdentifier = (MRClientStringFn)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRNowPlayingClientGetBundleIdentifier"));
    MRClientGetParentAppBundleIdentifier = (MRClientStringFn)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRNowPlayingClientGetParentAppBundleIdentifier"));
    MRRegisterForNotificationsFn registerForNotifications = (MRRegisterForNotificationsFn)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteRegisterForNowPlayingNotifications"));

    if (!MRGetNowPlayingInfo || !MRGetNowPlayingClient || !MRGetIsPlaying || !MRClientGetBundleIdentifier || !registerForNotifications) {
        return NO;
    }
    registerForNotifications(queue);
    return YES;
}

/// Entry point, installed by perl as an XSUB. Never returns.
__attribute__((visibility("default")))
void mediaremote_adapter_stream(void *perlInterpreter, void *perlCV) {
    queue = dispatch_queue_create("MediaRemoteAdapter", DISPATCH_QUEUE_SERIAL);
    if (!loadMediaRemote()) {
        fprintf(stderr, "MediaRemoteAdapter: MediaRemote symbols unavailable\n");
        exit(1);
    }
    exitWithParent();

    NSArray<NSString *> *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ];
    for (NSString *name in names) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            scheduleSnapshot();
        }];
    }

    scheduleSnapshot();
    CFRunLoopRun();
    exit(0);
}
