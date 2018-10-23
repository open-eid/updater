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

#import <PCSC/winscard.h>

#include <Security/Security.h>

#include <sys/utsname.h>

#include "config.h"

#define UPDATER_ID @"ee.ria.id-updater"

@implementation Update {
    NSMutableURLRequest *request;
    NSString *signature;
}

- (id)initWithDelegate:(id <UpdateDelegate>)delegate {
    if (self = [super init]) {
        self.delegate = delegate;
        self.baseversion = [self versionInfo:@"ee.ria.open-eid"];
        self.updaterversion = [self versionInfo:@"ee.ria.ID-updater"];
        self.clientversion = [self versionInfo:@"ee.ria.qdigidocclient"];
        self.digidoc4 = [self versionInfo:@"ee.ria.qdigidoc4"];
        self.utilityversion = [self versionInfo:@"ee.ria.qesteidutil"];
        self.pluginversion = [self versionInfo:@"ee.ria.firefox-token-signing"];
        self.safaripluginversion = [self versionInfo:@"ee.ria.safari-token-signing"];
        self.chromepluginversion = [self versionInfo:@"ee.ria.chrome-token-signing"];
        self.loaderversion = [self versionInfo:@"ee.ria.firefox-pkcs11-loader"];
        self.pkcs11version = [self versionInfo:@"org.opensc-project.mac"];
        self.tokendversion = [self versionInfo:@"ee.ria.esteid-tokend"];
        self.ctktokendversion = [self versionInfo:@"ee.ria.esteid-ctk-tokend"];
    }
    return self;
}

- (void)request {
    NSURL *url = [NSURL URLWithString:@CONFIG_URL];
    url = [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"config.rsa"];
    request = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    [request addValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [self receivedData:data withResponse:response];
    }] resume];
}

- (NSString*)userAgent {
    NSDictionary *os = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    struct utsname unameData;
    uname(&unameData);

    SCARDCONTEXT ctx = 0;
    SCardEstablishContext(SCARD_SCOPE_SYSTEM, 0, 0, &ctx);
    uint32_t size = 0;
    SCardListReaders(ctx, 0, 0, &size);
    char *readers = (char*)malloc(size * sizeof(char));
    SCardListReaders(ctx, 0, readers, &size);
    NSMutableArray *list = [NSMutableArray array];
    for (char *p = readers; *p; p += strlen(p) + 1) {
        [list addObject:[NSString stringWithCString:p encoding:NSUTF8StringEncoding]];
    }
    free(readers);
    SCardReleaseContext(ctx);

    NSMutableArray *agent = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"id-updater/%@", self.baseversion]];
    if (self.clientversion) {
        [agent addObject:[NSString stringWithFormat:@"qdigidocclient/%@", self.clientversion]];
    }
    if (self.utilityversion) {
        [agent addObject:[NSString stringWithFormat:@"qesteidutility/%@", self.utilityversion]];
    }
    if (self.digidoc4) {
        [agent addObject:[NSString stringWithFormat:@"qdigidoc4/%@", self.digidoc4]];
    }
    [agent addObject:[NSString stringWithFormat:@"(Mac OS %@(%lu/%s)) Locale: %@ Devices: %@",
        [os objectForKey:@"ProductVersion"], sizeof(void *)<<3, unameData.machine, @"UTF-8", [list componentsJoinedByString:@"/"]]];
    return [agent componentsJoinedByString:@" "];
}

- (BOOL)verify:(NSData *)data error:(NSError **)error
{
    NSString *pem = [NSString stringWithUTF8String:(char*)config_pub];
    pem = [pem stringByReplacingOccurrencesOfString:@"-----BEGIN RSA PUBLIC KEY-----" withString:@""];
    pem = [pem stringByReplacingOccurrencesOfString:@"-----END RSA PUBLIC KEY-----" withString:@""];
    pem = [NSString stringWithFormat:@"%@%@", @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A", pem];
    NSData *keyData = [[NSData alloc] initWithBase64EncodedString:pem options:NSDataBase64DecodingIgnoreUnknownCharacters];
    NSDictionary *parameters = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic
    };
    CFErrorRef err = 0;
    id key = CFBridgingRelease(SecKeyCreateFromData((__bridge CFDictionaryRef)parameters, (__bridge CFDataRef)keyData, &err));
    if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    return [self verifySignature:[[NSData alloc] initWithBase64EncodedString:signature options:NSDataBase64DecodingIgnoreUnknownCharacters] data:data key:(__bridge SecKeyRef)key digest:(__bridge CFNumberRef)@512 error:error];
}

- (BOOL)verifySignature:(NSData *)signatureData data:(NSData *)data key:(SecKeyRef)key digest:(CFNumberRef)digest error:(NSError **)error {
    CFErrorRef err = nil;
    id verifier = CFBridgingRelease(SecVerifyTransformCreate(key, (__bridge CFDataRef)signatureData, &err));
    if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    SecTransformSetAttribute((__bridge SecTransformRef)verifier, kSecTransformInputAttributeName, (__bridge CFDataRef)data, &err);
    if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    if (digest != nil) {
        SecTransformSetAttribute((__bridge SecTransformRef)verifier, kSecDigestTypeAttribute, kSecDigestSHA2, &err);
        if (err) { if(error) *error = CFBridgingRelease(err); return false; }
        SecTransformSetAttribute((__bridge SecTransformRef)verifier, kSecDigestLengthAttribute, digest, &err);
        if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    } else {
        SecTransformSetAttribute((__bridge SecTransformRef)verifier, kSecInputIsAttributeName, kSecInputIsDigest, &err);
        if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    }
    CFTypeRef result = SecTransformExecute((__bridge SecTransformRef)verifier, &err);
    bool isValid = result == kCFBooleanTrue;
    CFRelease(result);
    if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    return isValid;
}

- (NSString*)versionInfo:(NSString *)pkg {
    NSDictionary *list = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/db/receipts/%@.plist", pkg]];
    return list ? [list objectForKey:@"PackageVersion"] : [NSString string];
}

- (void)receivedData:(NSData *)data withResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *http = (NSHTTPURLResponse*)response;
    if (http.statusCode != 200) {
        [self.delegate didFinish:[NSError errorWithDomain:@"ee.ria.ID-updater" code:FileNotFound userInfo:nil]];
        return;
    }

    NSString *file = request.URL.absoluteString.lastPathComponent;
    NSError *error;
    if ([file isEqualToString:@"config.json"]) {
        if (![self verify:data error:&error]) {
            NSLog(@"Verify error: %@", error);
            [self.delegate didFinish:[NSError errorWithDomain:@"ee.ria.ID-updater" code:InvalidSignature userInfo:nil]];
            return;
        }
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!json) {
            [self.delegate didFinish:error];
            return;
        }

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyyMMddHHmmss'Z'";
        df.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        if ([NSDate.date compare:[df dateFromString:json[@"META-INF"][@"DATE"]]] == NSOrderedAscending) {
            [self.delegate didFinish:[NSError errorWithDomain:@"ee.ria.ID-updater" code:DateLaterThanCurrent userInfo:nil]];
            return;
        }

        self.centralConfig = json;
        NSString *message = json[@"OSX-MESSAGE"];
        NSString *version = json[@"OSX-LATEST"];
        if (message) {
            NSLog(@"Message: %@", message);
            [self.delegate message:message];
        }
        else if (version) {
            NSLog(@"Remote version: %@", version);
            if ([version compare:self.baseversion options:NSNumericSearch] > 0) {
                [self.delegate updateAvailable:version filename:json[@"OSX-DOWNLOAD"]];
            }
        }
        [self.delegate didFinish:error];
    } else if ([file isEqualToString:@"config.rsa"]) {
        signature = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        request.URL = [NSURL URLWithString:@CONFIG_URL];
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            [self receivedData:data withResponse:response];
        }] resume];
    }
}

@end
