/*
 * id-updater
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#import <id_updater_lib/id_updater_lib-Swift.h>

#import <PreferencePanes/PreferencePanes.h>

#undef NSLocalizedString
#define NSLocalizedString(key, comment) \
[bundlelang localizedStringForKey:(key) value:@"" table:nil]

@interface ID_updater : NSPreferencePane <UpdateDelegate, NSURLSessionDownloadDelegate, NSUserNotificationCenterDelegate>

@property (weak) IBOutlet NSTextField *mainLabel;
@property (weak) IBOutlet NSTextField *statusLabel;
@property (weak) IBOutlet NSTextField *infoLabel;
@property (weak) IBOutlet NSProgressIndicator *progress;
@property (weak) IBOutlet NSButton *install;
@property (weak) IBOutlet NSButton *autoUpdate;
@property (strong) AdvancedWindowController *advancedViewController;

@end

@implementation ID_updater {
    NSURL *filename;
    NSTimer *timer;
    double lastRecvd;
    Update *update;
    NSBundle *bundlelang;
    NSDateFormatter *df;
    NSUserDefaults *defaults;
    dispatch_source_t watcher;
    int fileDescriptor;
    VerifiedPackageInstaller *verifiedPackageInstaller;
}

- (void)mainViewDidLoad {
    NSURL *url = [NSURL fileURLWithPath:@"~/Library/LaunchAgents/ee.ria.id-updater.plist".stringByStandardizingPath];
    NSDictionary *schedule = [NSDictionary dictionaryWithContentsOfURL:url error:nil];
    self.autoUpdate.state = schedule != nil;

    bundlelang = self.bundle;
    NSArray *languages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    NSLog(@"Languages %@", languages);
    if([@"et" isEqualToString:languages[0]]) {
        NSLog(@"Estonian %@", [self.bundle pathForResource:languages[0] ofType:@"lproj"]);
        bundlelang = [NSBundle bundleWithPath:[self.bundle pathForResource:languages[0] ofType:@"lproj"]];
    }

    df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    defaults = NSUserDefaults.standardUserDefaults;
    [self setLastUpdateCheck:NO];

    verifiedPackageInstaller = [[VerifiedPackageInstaller alloc] initWithLocalizedBundle:bundlelang];
    update = [[Update alloc] initWithDelegate:self];
    self.mainLabel.stringValue = [NSString stringWithFormat:@"%@ %@", self.mainLabel.stringValue, update.baseVersion];
}

- (void)willSelect {
    [self watchFile:@"/var/db/receipts/ee.ria.open-eid.plist"];
    [update request];
}

- (void)willUnselect {
    dispatch_source_cancel(watcher);
    watcher = nil;
}

- (void)watchFile:(NSString *)filePath {
    fileDescriptor = open([filePath fileSystemRepresentation], O_EVTONLY);
    if (fileDescriptor < 0) {
        NSLog(@"Failed to open file: %@", filePath);
        return;
    }

    watcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fileDescriptor,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_event_handler(watcher, ^{
        NSLog(@"File changed on disk: %@", filePath);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"Update UI");
            self.install.hidden = YES;
            self.mainLabel.stringValue = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Your ID-software is up to date - version", nil), update.baseVersion];
        });
    });
    dispatch_source_set_cancel_handler(watcher, ^{ close(fileDescriptor); });
    dispatch_resume(watcher);

    NSLog(@"Started watching %@", filePath);
}

- (void)setLastUpdateCheck:(BOOL)set {
    NSDictionary *dict = [defaults persistentDomainForName:self.bundle.bundleIdentifier];
    if (!dict)
        dict = @{@"LastCheck": @"None"};
    if (set) {
        NSMutableDictionary *newDict = [dict mutableCopy];
        newDict[@"LastCheck"] = [df stringFromDate:[[NSDate alloc] init]];
        [defaults setPersistentDomain:newDict forName:self.bundle.bundleIdentifier];
        [defaults synchronize];
        dict = [defaults persistentDomainForName:self.bundle.bundleIdentifier];
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Last checked:", nil), dict[@"LastCheck"]];
}

#pragma mark - UserNotificationCenter Delegate

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    [center removeAllDeliveredNotifications];
}

#pragma mark - Update delegate

- (void)didFinish:(NSError *)error {
    [self setLastUpdateCheck:YES];
    if (error == nil) {
        return;
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        switch (error.code) {
            case UpdateErrorInvalidSignature:
                self.infoLabel.stringValue = NSLocalizedString(@"The configuration file located on the server cannot be validated.", nil);
                break;

            case UpdateErrorFileNotFound:
                self.infoLabel.stringValue = NSLocalizedString(@"File not found", nil);
                break;

            default:
                self.infoLabel.stringValue = error.localizedDescription;
                break;
        }
    });
}

- (void)message:(NSString *)message {
    dispatch_sync(dispatch_get_main_queue(), ^{
        self.infoLabel.stringValue = message;
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        if (center) {
            NSUserNotification *notification = [NSUserNotification new];
            notification.title = NSLocalizedString(@"Update message", nil);
            notification.informativeText = message;
            notification.soundName = NSUserNotificationDefaultSoundName;
            center.delegate = self;
            [center deliverNotification:notification];
        }
    });
}

- (void)updateAvailable:(NSString *)_available filename:(NSURL *)_filename {
    dispatch_sync(dispatch_get_main_queue(), ^{
        self.install.hidden = NO;
        filename = _filename;
        self.mainLabel.stringValue = [NSString stringWithFormat: @"%@ %@",
                                      NSLocalizedString(@"Update available", nil), _available];
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        if (center) {
            NSUserNotification *notification = [NSUserNotification new];
            notification.title = NSLocalizedString(@"Update available", nil);
            notification.subtitle = [NSString stringWithFormat: @"%@ %@",
                                     NSLocalizedString(@"ID-software", nil), _available];
            notification.informativeText = NSLocalizedString(@"https://www.id.ee/en/article/id-software-versions-info-release-notes/", nil);
            notification.soundName = NSUserNotificationDefaultSoundName;
            notification.contentImage = [[NSImage alloc] initWithContentsOfFile:
                                         [self.bundle pathForResource:@"Icon" ofType:@"icns"]];
            center.delegate = self;
            [center deliverNotification:notification];
        }
    });
}

#pragma mark - Connection delegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    dispatch_sync(dispatch_get_main_queue(), ^{
        self.progress.maxValue = totalBytesExpectedToWrite;
        self.progress.doubleValue = totalBytesWritten;
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progress stopAnimation:self];
        [self->timer invalidate];
        self->timer = nil;
    });
    NSString *errorMessage = [verifiedPackageInstaller installVerifiedPackageFromDownloadedDiskImage:location
                                                                                 trustedCertificates:update.cert_bundle];
    if (errorMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.infoLabel.stringValue = errorMessage;
        });
    }
}

#pragma mark - base implementation

- (IBAction)schedule:(id)sender {
    NSString *arg = self.autoUpdate.state ? @"-weekly" : @"-remove";
    [[NSTask launchedTaskWithLaunchPath:[self.bundle pathForResource:@"id-updater-helper" ofType:nil] arguments:@[arg]] waitUntilExit];
}

- (IBAction)help:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:NSLocalizedString(@"https://www.id.ee", nil)]];
}

- (IBAction)installUpdate:(id)sender {
    self.progress.hidden = NO;
    self.progress.indeterminate = NO;
    self.progress.doubleValue = 0;
    [self.progress startAnimation:self];
    NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:filename];
    [request addValue:[update userAgent:YES] forHTTPHeaderField:@"User-Agent"];
    [[defaultSession downloadTaskWithRequest:request] resume];
    lastRecvd = 0;
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        self.infoLabel.stringValue = [NSString stringWithFormat:@"%.2f KB/s", (self.progress.doubleValue - self->lastRecvd)/1000];
        self->lastRecvd = self.progress.doubleValue;
    }];
}

- (IBAction)diagnostics:(id)sender {
    self.advancedViewController = [[AdvancedWindowController alloc] initWithParent:self.mainView.window];
}

@end
