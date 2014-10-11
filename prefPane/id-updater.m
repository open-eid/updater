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
#import <SecurityInterface/SFAuthorizationView.h>

#include <openssl/x509v3.h>
#include <xar/xar.h>

#define PATH "/Library/LaunchAgents/ee.ria.id-updater.plist"
#undef NSLocalizedString
#define NSLocalizedString(key, comment) \
[bundlelang localizedStringForKey:(key) value:@"" table:nil]

@interface ID_updater : NSPreferencePane <UpdateDelegate, NSURLConnectionDataDelegate, NSUserNotificationCenterDelegate> {
    IBOutlet SFAuthorizationView *authView;
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
    NSString *filename;
    NSFileHandle *file;
    NSTimer *timer;
    double lastRecvd;
    Update *update;
    NSBundle *bundlelang;
}
@end

@implementation ID_updater

- (void)mainViewDidLoad {
    AuthorizationItem items = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &items};
    authView.authorizationRights = &rights;
    authView.delegate = self;
    changeSchedule.enabled = self.isUnlocked;

    NSDictionary *schedule = [NSDictionary dictionaryWithContentsOfFile:@PATH];
    if (!schedule) {
        [changeSchedule selectItemAtIndex:3];
    } else if ([(NSDictionary*)[schedule objectForKey:@"StartCalendarInterval"] objectForKey:@"Weekday"]) {
        [changeSchedule selectItemAtIndex:1];
    } else if ([(NSDictionary*)[schedule objectForKey:@"StartCalendarInterval"] objectForKey:@"Day"]) {
        [changeSchedule selectItemAtIndex:2];
    }

    update = [[Update alloc] initWithDelegate:self];
    installed.stringValue = update.baseversion;
    bundlelang = self.bundle;
    NSArray *languages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    NSLog(@"Languages %@", languages);
    if([@"et" isEqualToString:[languages objectAtIndex:0]]) {
        NSLog(@"Estonian %@", [self.bundle pathForResource:[languages objectAtIndex:0] ofType:@"lproj"]);
        bundlelang = [NSBundle bundleWithPath:[self.bundle pathForResource:[languages objectAtIndex:0] ofType:@"lproj"]];
    }
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
    [changelogurl addAttribute:NSLinkAttributeName value:[changelogurl string] range:NSMakeRange(0, [changelogurl length])];
    [[changelog textStorage] setAttributedString:changelogurl];

    info.stringValue = [NSString stringWithFormat:@"%@ (%@)\n%@ (%@)\n%@ (%@)\n%@ (%@)\n%@ (%@)\n%@ (%@)",
                        NSLocalizedString(@"DigiDoc client", nil), update.clientversion,
                        NSLocalizedString(@"ID-Card Utility", nil), update.utilityversion,
                        NSLocalizedString(@"Browser plugin", nil), update.pluginversion,
                        NSLocalizedString(@"PKCS11", nil), update.pkcs11version,
                        NSLocalizedString(@"Tokend", nil), update.tokendversion,
                        NSLocalizedString(@"PKCS11 loader", nil), update.loaderversion];
    [update request];
}

#pragma mark - Auhtorization delegate

- (void)authorizationViewDidAuthorize:(SFAuthorizationView *)view {
    changeSchedule.enabled = self.isUnlocked;
}

- (void)authorizationViewDidDeauthorize:(SFAuthorizationView *)view {
    changeSchedule.enabled = self.isUnlocked;
}

#pragma mark - UserNotificationCenter Delegate

/*- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}*/

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    [center removeAllDeliveredNotifications];
}

#pragma mark - Update delegate

- (void)error:(NSError *)error {
    status.stringValue = [error localizedDescription];
}

- (void)message:(NSString *)message {
    status.stringValue = message;
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
}

- (void)updateAvailable:(NSString *)_available filename:(NSString *)_filename {
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
}

#pragma mark - Connection delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    progress.maxValue = response.expectedContentLength;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [progress incrementBy:data.length];
    [file writeData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [progress stopAnimation:self];
    [file closeFile];
    [timer invalidate];
    timer = nil;
    NSArray *args = @[@"attach", @"-verify", @"-mountpoint", @"/Volumes/estonianidcard",
                      [NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), filename]];
    NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:args];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        status.stringValue = [NSString stringWithFormat:@"Verify failed, status: %i", task.terminationStatus];
        return;
    }

    NSArray *paths = [NSFileManager.defaultManager subpathsAtPath:@"/Volumes/estonianidcard"];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF contains[cd] %@", @".pkg"];
    NSString *path = [NSString stringWithFormat:@"%@/%@", @"/Volumes/estonianidcard",
                      [paths filteredArrayUsingPredicate:predicate].lastObject];

    xar_t xar = xar_open(path.UTF8String, 0);
    if (!xar) {
        status.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Failed to open xar archive: %@", nil), path];
        return;
    }

    X509 *cert = nil;
    xar_signature_t sig = xar_signature_first(xar);
    int32_t count = xar_signature_get_x509certificate_count(sig);
    for (int32_t i = 0; i < count; ++i)	{
        uint32_t size = 0;
        const uint8_t *data = 0;
        if (xar_signature_get_x509certificate_data(sig, i, &data, &size))
            continue;

        X509 *c = d2i_X509(nil, &data, size);
        if (!c)
            continue;

        unsigned char *cn = nil;
        for (int i = 0; i < X509_NAME_entry_count(c->cert_info->subject); ++i) {
            X509_NAME_ENTRY *e = X509_NAME_get_entry(c->cert_info->subject, i);
            const char *obj = OBJ_nid2sn(OBJ_obj2nid(X509_NAME_ENTRY_get_object(e)));
            if (strcmp(obj, "CN") != 0)
                continue;
            size = ASN1_STRING_to_UTF8(&cn, X509_NAME_ENTRY_get_data(e));
            break;
        }

        if (!cn)
            continue;

        if (strcmp((const char*)cn, "Estonian Informatics Centre") == 0 ||
            strcmp((const char*)cn, "Developer ID Installer: Riigi Infosüsteemi Amet") == 0) {
            OPENSSL_free(cn);
            cert = c;
            break;
        }
        OPENSSL_free(cn);
        X509_free(c);
    }

    if (!cert) {
        status.stringValue = NSLocalizedString(@"No matching certificate", nil);
        xar_close(xar);
        return;
    }

    uint8_t *data = 0, *signature = 0;
    uint32_t dataSize = 0, signatureSize = 0;
    off_t offset = 0;
    if (xar_signature_copy_signed_data(sig, &data, &dataSize, &signature, &signatureSize, &offset)) {
        status.stringValue = NSLocalizedString(@"Failed to copy signature", nil);
        xar_close(xar);
        return;
    }

    RSA *pub = EVP_PKEY_get1_RSA(X509_get_pubkey(cert));
    int result = RSA_verify(NID_sha1, data, dataSize, signature, signatureSize, pub);
    RSA_free(pub);
    xar_close(xar);
    free(data);
    free(signature);

    if (result == 1)
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
    else
        status.stringValue = NSLocalizedString(@"Failed to verify signature", nil);
}

#pragma mark - base implementation

- (BOOL)isUnlocked {
    return authView.authorizationState == SFAuthorizationViewUnlockedState;
}

- (IBAction)schedule:(id)sender {
    const char *args[2] = { nil, nil };
    switch (changeSchedule.indexOfSelectedItem) {
        case 0: args[0] = "-daily"; break;
        case 1: args[0] = "-weekly"; break;
        case 2: args[0] = "-monthly"; break;
        case 3: args[0] = "-remove"; break;
        default: break;
    }
    NSString *path = [self.bundle pathForResource:@"id-updater-helper" ofType:nil];
    AuthorizationExecuteWithPrivileges(authView.authorization.authorizationRef, path.UTF8String, kAuthorizationFlagDefaults, (char *const *)args, nil);
}

- (IBAction)installUpdate:(id)sender {
    speed.hidden = NO;
    progress.hidden = NO;
    progress.indeterminate = NO;
    progress.doubleValue = 0;
    [progress startAnimation:self];
    NSString *tmp = [NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), filename];
    [NSFileManager.defaultManager createFileAtPath:tmp contents:nil attributes:nil];
    file = [NSFileHandle fileHandleForWritingAtPath:tmp];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", update.url, filename]];
    [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:url] delegate:self];
    lastRecvd = 0;
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timer:) userInfo:nil repeats:YES];
}

- (void)timer:(NSTimer*)timer {
    speed.stringValue = [NSString stringWithFormat:@"%.2f KB/s", (progress.doubleValue - lastRecvd)/1000];
    lastRecvd = progress.doubleValue;
}

@end
