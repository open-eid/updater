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

@interface ID_updater : NSPreferencePane <UpdateDelegate, NSURLSessionDownloadDelegate, NSUserNotificationCenterDelegate> {
    IBOutlet NSPopUpButton *changeSchedule;
    IBOutlet NSTextField *changeScheduleLabel;
    IBOutlet NSTextField *status;
    IBOutlet NSTextView *changelog;
    IBOutlet NSTextField *changelogLabel;
    IBOutlet NSTextField *installed;
    IBOutlet NSTextField *installedLabel;
    IBOutlet NSTextField *available;
    IBOutlet NSTextField *availableLabel;
    IBOutlet NSTextField *speed;
    IBOutlet NSProgressIndicator *progress;
    IBOutlet NSButton *install;
    IBOutlet NSTextField *info;
    IBOutlet NSTabViewItem *updates;
    IBOutlet NSTabViewItem *versionInfo;
    IBOutlet NSTextField *serverMessage;
    NSString *filename;
    NSTimer *timer;
    double lastRecvd;
    Update *update;
    NSBundle *bundlelang;
}
@end

@implementation ID_updater

- (void)mainViewDidLoad {
    NSDictionary *schedule = [NSDictionary dictionaryWithContentsOfFile:(@"~/Library/LaunchAgents/ee.ria.id-updater.plist").stringByStandardizingPath];
    if (!schedule) {
        [changeSchedule selectItemAtIndex:3];
    } else if (((NSDictionary*)schedule[@"StartCalendarInterval"])[@"Weekday"]) {
        [changeSchedule selectItemAtIndex:1];
    } else if (((NSDictionary*)schedule[@"StartCalendarInterval"])[@"Day"]) {
        [changeSchedule selectItemAtIndex:2];
    }

    update = [[Update alloc] initWithDelegate:self];
    installed.stringValue = update.baseversion;
    bundlelang = self.bundle;
    NSArray *languages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    NSLog(@"Languages %@", languages);
    if([@"et" isEqualToString:languages[0]]) {
        NSLog(@"Estonian %@", [self.bundle pathForResource:languages[0] ofType:@"lproj"]);
        bundlelang = [NSBundle bundleWithPath:[self.bundle pathForResource:languages[0] ofType:@"lproj"]];
    }
    status.stringValue = NSLocalizedString(status.stringValue, nil);
    changeScheduleLabel.stringValue = NSLocalizedString(changeScheduleLabel.stringValue, nil);
    changelogLabel.stringValue = NSLocalizedString(changelogLabel.stringValue, nil);
    installedLabel.stringValue = NSLocalizedString(installedLabel.stringValue, nil);
    availableLabel.stringValue = NSLocalizedString(availableLabel.stringValue, nil);
    install.title = NSLocalizedString(install.title, nil);
    for (int i = 0; i < changeSchedule.numberOfItems; ++i) {
        NSMenuItem *item = [changeSchedule itemAtIndex:i];
        item.title = NSLocalizedString(item.title, nil);
    }
    versionInfo.label = NSLocalizedString(versionInfo.label, nil);
    updates.label = NSLocalizedString(updates.label, nil);

    NSMutableAttributedString *changelogurl = [[NSMutableAttributedString alloc]
                                               initWithString:NSLocalizedString(@"http://www.id.ee/eng/changelog", nil)];
    [changelogurl addAttribute:NSLinkAttributeName value:changelogurl.string range:NSMakeRange(0, changelogurl.length)];
    [changelog.textStorage setAttributedString:changelogurl];

    NSDictionary *versions = @{
        NSLocalizedString(@"DigiDoc3 Client", nil): update.clientversion,
        NSLocalizedString(@"DigiDoc4", nil): update.digidoc4,
        NSLocalizedString(@"ID-Card Utility", nil): update.utilityversion,
        NSLocalizedString(@"Open-EID", nil): update.baseversion,
        NSLocalizedString(@"ID-Updater", nil): [update versionInfo:@"ee.ria.ID-updater"],
        NSLocalizedString(@"Safari (Extensions) browser plugin", nil): [update versionInfo:@"ee.ria.safari-token-signing"],
        NSLocalizedString(@"Safari (NPAPI) browser plugin", nil): [update versionInfo:@"ee.ria.firefox-token-signing"],
        NSLocalizedString(@"Chrome/Firefox browser plugin", nil): [update versionInfo:@"ee.ria.chrome-token-signing"],
        NSLocalizedString(@"Chrome browser plugin", nil): [update versionInfo:@"ee.ria.token-signing-chrome"],
        NSLocalizedString(@"Chrome browser plugin policy", nil): [update versionInfo:@"ee.ria.token-signing-chrome-policy"],
        NSLocalizedString(@"Firefox browser plugin", nil): [update versionInfo:@"ee.ria.token-signing-firefox"],
        NSLocalizedString(@"PKCS11 loader", nil): [update versionInfo:@"ee.ria.firefox-pkcs11-loader"],
        NSLocalizedString(@"IDEMIA PKCS11 loader", nil): [update versionInfo:@"com.idemia.awp.xpi"],
        NSLocalizedString(@"OpenSC", nil): [update versionInfo:@"org.opensc-project.mac"],
        NSLocalizedString(@"IDEMIA PKCS11", nil): [update versionInfo:@"com.idemia.awp.pkcs11"],
        NSLocalizedString(@"EstEID Tokend", nil): [update versionInfo:@"ee.ria.esteid-tokend"],
        NSLocalizedString(@"EstEID CTK Tokend", nil): [update versionInfo:@"ee.ria.esteid-ctk-tokend"],
        NSLocalizedString(@"IDEMIA Tokend", nil): [update versionInfo:@"com.idemia.awp.tokend"],
    };
    NSMutableArray *list = [[NSMutableArray alloc] init];
    [versions enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if (object != nil && ((NSString*)object).length != 0)
            [list addObject:[NSString stringWithFormat:@"%@ (%@)", key, object]];
    }];
    info.stringValue = [list componentsJoinedByString:@"\n"];
    [update request];
}

#pragma mark - UserNotificationCenter Delegate

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    [center removeAllDeliveredNotifications];
}

#pragma mark - Update delegate

- (void)didFinish:(NSError *)error {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (error) {
            switch (error.code) {
                case InvalidSignature:
                    status.stringValue = NSLocalizedString(@"The configuration file located on the server cannot be validated.", nil);
                    break;

                case FileNotFound:
                    status.stringValue = NSLocalizedString(@"File not found", nil);
                    break;

                default:
                    status.stringValue = error.localizedDescription;
                    break;
            }
        }
    });
}

- (void)message:(NSString *)message {
    dispatch_sync(dispatch_get_main_queue(), ^{
        serverMessage.stringValue = message;
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        if (center) {
            NSUserNotification *notification = [NSUserNotification new];
            notification.title = NSLocalizedString(@"Update message", nil);
            notification.subtitle = message;
            notification.informativeText = message;
            notification.soundName = NSUserNotificationDefaultSoundName;
            center.delegate = self;
            [center deliverNotification:notification];
        }
    });
}

- (void)updateAvailable:(NSString *)_available filename:(NSString *)_filename {
    dispatch_sync(dispatch_get_main_queue(), ^{
        availableLabel.hidden = NO;
        available.hidden = NO;
        install.hidden = NO;
        available.stringValue = _available;
        filename = _filename;

        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        if (center) {
            NSUserNotification *notification = [NSUserNotification new];
            notification.title = NSLocalizedString(@"Update available", nil);
            notification.subtitle = _available;
            notification.informativeText = NSLocalizedString(@"http://www.id.ee/eng/changelog", nil);
            notification.soundName = NSUserNotificationDefaultSoundName;
            center.delegate = self;
            [center deliverNotification:notification];
        }
    });
}

#pragma mark - Connection delegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    dispatch_sync(dispatch_get_main_queue(), ^{
        self->progress.maxValue = totalBytesExpectedToWrite;
        self->progress.doubleValue = totalBytesWritten;
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    [progress stopAnimation:self];
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
        status.stringValue = [NSString stringWithFormat:@"Verify failed, status: %i", task.terminationStatus];
        return;
    }

    NSArray *paths = [NSFileManager.defaultManager subpathsAtPath:volumePath];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF contains[cd] %@", @".pkg"];
    NSString *path = [NSString stringWithFormat:@"%@/%@", volumePath,
                      [paths filteredArrayUsingPredicate:predicate].lastObject];

    xar_t xar = xar_open(path.UTF8String, 0);
    if (!xar) {
        status.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Failed to open xar archive: %@", nil), path];
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
        if ([update.centralConfig[@"CERT-BUNDLE"] containsObject:[der base64EncodedStringWithOptions:0]])
            certData = [NSData dataWithBytes:(uint8_t*)data length:size]; // Make copy of memory will be lost after xar_close
    }

    if (!certData) {
        status.stringValue = NSLocalizedString(@"No matching certificate", nil);
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
        status.stringValue = NSLocalizedString(@"Failed to copy signature", nil);
        return;
    }

    if([signatureType isEqualToString:@"CMS"]) {
        if ([update verifyCMSSignature:signature data:data cert:certData])
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
        else
        {
            NSLog(@"CMS Verify error");
            status.stringValue = NSLocalizedString(@"Failed to verify signature", nil);
        }
        return;
    }

    SecCertificateRef certref = SecCertificateCreateWithData(0, (__bridge CFDataRef)certData);
    SecKeyRef publickey = nil;
    OSStatus oserr = SecCertificateCopyPublicKey(certref, &publickey);
    CFRelease(certref);
    if (oserr) {
        status.stringValue = NSLocalizedString(@"Failed to copy public key", nil);
        return;
    }

    NSError *error = nil;
    bool isValid = [update verifySignature:signature data:data key:publickey digestSize:nil error:&error];
    CFRelease(publickey);
    if (isValid)
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
    else
    {
        NSLog(@"Verify error: %@", error);
        status.stringValue = NSLocalizedString(@"Failed to verify signature", nil);
    }
}

#pragma mark - base implementation

- (IBAction)schedule:(id)sender {
    NSString *arg;
    switch (changeSchedule.indexOfSelectedItem) {
        case 0: arg = @"-daily"; break;
        case 1: arg = @"-weekly"; break;
        case 2: arg = @"-monthly"; break;
        case 3: arg = @"-remove"; break;
        default: break;
    }
    [[NSTask launchedTaskWithLaunchPath:[self.bundle pathForResource:@"id-updater-helper" ofType:nil] arguments:@[arg]] waitUntilExit];
}

- (IBAction)installUpdate:(id)sender {
    speed.hidden = NO;
    progress.hidden = NO;
    progress.indeterminate = NO;
    progress.doubleValue = 0;
    [progress startAnimation:self];
    NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:filename]];
    [request addValue:[update userAgent] forHTTPHeaderField:@"User-Agent"];
    [[defaultSession downloadTaskWithRequest:request] resume];
    lastRecvd = 0;
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timer:) userInfo:nil repeats:YES];
}

- (void)timer:(NSTimer*)timer {
    speed.stringValue = [NSString stringWithFormat:@"%.2f KB/s", (progress.doubleValue - lastRecvd)/1000];
    lastRecvd = progress.doubleValue;
}

@end
