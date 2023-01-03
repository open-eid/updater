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

#import "update.h"

#import <PreferencePanes/PreferencePanes.h>

#include <xar/xar.h>

#undef NSLocalizedString
#define NSLocalizedString(key, comment) \
[bundlelang localizedStringForKey:(key) value:@"" table:nil]

@interface AdvancedWindowController: NSWindowController
@end

@implementation AdvancedWindowController

- (instancetype)initWithText:(NSString*)text {
    if (self = [super init]) {
        NSView *view = [[NSView alloc] init];

        NSTextField *label = [NSTextField labelWithString:text];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:label];
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:25].active = YES;
        [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor].active = YES;

        NSButton *ok = [[NSButton alloc] init];
        ok.translatesAutoresizingMaskIntoConstraints = NO;
        ok.title = @"OK";
        ok.keyEquivalent = @"\r";
        ok.highlighted = YES;
        ok.bezelStyle = NSBezelStyleRounded;
        ok.target = self;
        ok.action = @selector(buttonPressed:);
        [view addSubview:ok];
        [ok.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-25].active = YES;
        [ok.rightAnchor constraintEqualToAnchor:view.rightAnchor constant:-25].active = YES;

        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 250)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        self.window.contentView = view;
        self.window.defaultButtonCell = ok.cell;
    }
    return self;
}

- (void)buttonPressed:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (void)showWindow:(id)sender {
    [self.window makeKeyAndOrderFront:sender];
}

@end

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
    NSString *filename;
    NSTimer *timer;
    double lastRecvd;
    Update *update;
    NSBundle *bundlelang;
    NSDateFormatter *df;
    NSUserDefaults *defaults;
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

    update = [[Update alloc] initWithDelegate:self];
    self.mainLabel.stringValue = [NSString stringWithFormat:@"%@ %@", self.mainLabel.stringValue, update.baseversion];
    [update request];
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
            case InvalidSignature:
                self.infoLabel.stringValue = NSLocalizedString(@"The configuration file located on the server cannot be validated.", nil);
                break;

            case FileNotFound:
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

- (void)updateAvailable:(NSString *)_available filename:(NSString *)_filename {
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
    [self.progress stopAnimation:self];
    [timer invalidate];
    timer = nil;
    NSString *tmp = [NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), filename.lastPathComponent];
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    [NSFileManager.defaultManager moveItemAtPath:location.path toPath:tmp error:nil];

    NSString *volumePath = @"/Volumes/Open-EID";
    NSArray *args = @[@"attach", @"-verify", @"-mountpoint", volumePath, tmp];
    NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:args];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        self.infoLabel.stringValue = [NSString stringWithFormat:@"Verify failed, status: %i", task.terminationStatus];
        return;
    }

    NSArray *paths = [NSFileManager.defaultManager subpathsAtPath:volumePath];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF contains[cd] %@", @".pkg"];
    NSString *path = [NSString stringWithFormat:@"%@/%@", volumePath,
                      [paths filteredArrayUsingPredicate:predicate].lastObject];

    xar_t xar = xar_open(path.UTF8String, 0);
    if (!xar) {
        self.infoLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Failed to open xar archive: %@", nil), path];
        return;
    }

    NSData *certData;
    xar_signature_t sig = xar_signature_first(xar);
    xar_signature_t next = xar_signature_next(sig);
    if(next && strcmp("CMS", xar_signature_type(next)) == 0)
        sig = next;
    NSString *signatureType = @(xar_signature_type(sig));
    NSLog(@"Signature type %@", signatureType);
    for (int32_t i = 0, count = xar_signature_get_x509certificate_count(sig); i < count; ++i) {
        uint32_t size = 0;
        const uint8_t *data = nil;
        if (xar_signature_get_x509certificate_data(sig, i, &data, &size))
            continue;

        NSData *der = [NSData dataWithBytesNoCopy:(uint8_t*)data length:size freeWhenDone:NO];
        if ([update.cert_bundle containsObject:der])
            certData = [NSData dataWithBytes:(uint8_t*)data length:size]; // Make copy of memory will be lost after xar_close
    }

    if (!certData) {
        self.infoLabel.stringValue = NSLocalizedString(@"No matching certificate", nil);
        xar_close(xar);
        return;
    }

    uint8_t *signedData = nil, *signatureData = nil;
    uint32_t signedDataSize = 0, signatureDataSize = 0;
    off_t offset = 0;
    uint8_t err = xar_signature_copy_signed_data(sig, &signedData, &signedDataSize, &signatureData, &signatureDataSize, &offset);
    NSData *signature = [NSData dataWithBytesNoCopy:signatureData length:signatureDataSize];
    NSData *data = [NSData dataWithBytesNoCopy:signedData length:signedDataSize];
    xar_close(xar);
    if (err) {
        self.infoLabel.stringValue = NSLocalizedString(@"Failed to copy signature", nil);
        return;
    }

    if([signatureType isEqualToString:@"CMS"]) {
        if ([update verifyCMSSignature:signature data:data cert:certData])
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
        else
        {
            NSLog(@"CMS Verify error");
            self.infoLabel.stringValue = NSLocalizedString(@"Failed to verify signature", nil);
        }
        return;
    }

    SecCertificateRef certref = SecCertificateCreateWithData(0, (__bridge CFDataRef)certData);
    SecKeyRef publickey = SecCertificateCopyKey(certref);
    CFRelease(certref);
    if (publickey == nil) {
        self.infoLabel.stringValue = NSLocalizedString(@"Failed to copy public key", nil);
        return;
    }

    CFErrorRef error = nil;
    bool isValid = SecKeyVerifySignature(publickey, kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1,
                                         (__bridge CFDataRef)data, (__bridge CFDataRef)signature, &error);
    CFRelease(publickey);
    if (isValid)
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
    else
    {
        NSLog(@"Verify error: %@", CFBridgingRelease(error));
        self.infoLabel.stringValue = NSLocalizedString(@"Failed to verify signature", nil);
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
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:filename]];
    [request addValue:[update userAgent:YES] forHTTPHeaderField:@"User-Agent"];
    [[defaultSession downloadTaskWithRequest:request] resume];
    lastRecvd = 0;
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timer:) userInfo:nil repeats:YES];
}

- (void)timer:(NSTimer*)timer {
    self.infoLabel.stringValue = [NSString stringWithFormat:@"%.2f KB/s", (self.progress.doubleValue - lastRecvd)/1000];
    lastRecvd = self.progress.doubleValue;
}

- (IBAction)diagnostics:(id)sender {
    NSDictionary *versions = @{
        NSLocalizedString(@"DigiDoc3 Client", nil): update.clientversion,
        @"DigiDoc4": update.digidoc4,
        NSLocalizedString(@"ID-Card Utility", nil): update.utilityversion,
        @"Open-EID": update.baseversion,
        @"ID-Updater": [update versionInfo:@"ee.ria.ID-updater"],
        NSLocalizedString(@"Safari (Extensions) browser plugin", nil): [update versionInfo:@"ee.ria.safari-token-signing"],
        NSLocalizedString(@"Safari (NPAPI) browser plugin", nil): [update versionInfo:@"ee.ria.firefox-token-signing"],
        NSLocalizedString(@"Chrome/Firefox browser plugin", nil): [update versionInfo:@"ee.ria.chrome-token-signing"],
        NSLocalizedString(@"Chrome browser plugin", nil): [update versionInfo:@"ee.ria.token-signing-chrome"],
        NSLocalizedString(@"Chrome browser plugin policy", nil): [update versionInfo:@"ee.ria.token-signing-chrome-policy"],
        NSLocalizedString(@"Firefox browser plugin", nil): [update versionInfo:@"ee.ria.token-signing-firefox"],
        NSLocalizedString(@"Web-eID native component", nil): [update versionInfo:@"eu.web-eid.web-eid"],
        NSLocalizedString(@"Safari browser extension (Web-eID)", nil): [update versionInfo:@"eu.web-eid.web-eid-safari"],
        NSLocalizedString(@"Chrome browser extension (Web-eID)", nil): [update versionInfo:@"eu.web-eid.web-eid-chrome"],
        NSLocalizedString(@"Chrome browser extension policy (Web-eID)", nil): [update versionInfo:@"eu.web-eid.web-eid-chrome-policy"],
        NSLocalizedString(@"Firefox browser extension (Web-eID)", nil): [update versionInfo:@"eu.web-eid.web-eid-firefox"],
        NSLocalizedString(@"PKCS11 loader", nil): [update versionInfo:@"ee.ria.firefox-pkcs11-loader"],
        NSLocalizedString(@"IDEMIA PKCS11 loader", nil): [update versionInfo:@"com.idemia.awp.xpi"],
        @"OpenSC": [update versionInfo:@"org.opensc-project.mac"],
        @"IDEMIA PKCS11": [update versionInfo:@"com.idemia.awp.pkcs11"],
        @"EstEID Tokend": [update versionInfo:@"ee.ria.esteid-tokend"],
        @"EstEID CTK Tokend": [update versionInfo:@"ee.ria.esteid-ctk-tokend"],
        @"IDEMIA Tokend": [update versionInfo:@"com.idemia.awp.tokend"],
    };
    NSMutableArray *list = [[NSMutableArray alloc] init];
    [versions enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if (object != nil && ((NSString*)object).length != 0)
            [list addObject:[NSString stringWithFormat:@"%@ (%@)", key, object]];
    }];
    self.advancedViewController = [[AdvancedWindowController alloc] initWithText:[list componentsJoinedByString:@"\n"]];
    [self.mainView.window beginSheet:self.advancedViewController.window completionHandler:nil];
}

@end
