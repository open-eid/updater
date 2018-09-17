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

- (BOOL)verify:(NSData *)data
{
#if 0
    NSString *test1 = @
    "-----BEGIN RSA PUBLIC KEY-----\n"
    "MIIBCgKCAQEAzRQ9uWWPQ3mcboFG/NpwlVCupelL34g6JEzw5FmfwU87azeSg80u\n"
    "HAeQ340DijIB/OMk6eF3i65nl4moKUv8MJzrcBMYLKshQDR2U3cmxHDjdM+2ta+5\n"
    "71p1WfU0jWNDujHZFNZOu25fkKiHmtLLx0PzastQtkKZ23bXRRFD0pvJKBceWxG/\n"
    "JBPaxLEClxivYFEuAYt2QYtVenKYtitXhmflXqda4QJRwtfxQaeZymHGaxn12Ilc\n"
    "Bt6ZSAIE4DDXOL2Mwg/qR3x6UWg989OMfTGau7jiv+vaO92eC452VJIu/iNGXtrA\n"
    "iKnuGiERYeTupQIcV89wBIcQjqZIYH6fxQIDAQAB\r\n"
    "-----END RSA PUBLIC KEY-----\n";
    SecExternalFormat externalFormat = kSecFormatPEMSequence;
    //SecExternalFormat externalFormat = kSecFormatOpenSSL;
    //SecExternalItemType itemType = kSecItemTypeCertificate;
    SecExternalItemType itemType = kSecItemTypePublicKey;
    //SecExternalItemType itemType = kSecItemTypeAggregate;
    SecItemImportExportKeyParameters keyParams = {
        .version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION,
        .flags = kSecKeyImportOnlyOne | kSecItemPemArmour,
        .passphrase = NULL,
        .alertTitle = NULL,
        .alertPrompt = NULL,
        .accessRef = NULL,
        .keyUsage = NULL,//(__bridge CFArrayRef)@[(id)kSecAttrCanVerify],
        .keyAttributes = NULL, /* See below for rant */
    };
    CFDataRef pem = (__bridge CFDataRef)([test1 dataUsingEncoding:NSASCIIStringEncoding]);//CFDataCreate(0, config_pub, config_pub_len);
    CFShow(pem);
    CFArrayRef temparray = NULL;
    OSStatus oserr = SecItemImport(pem, NULL, &externalFormat, &itemType, 0, NULL, NULL, &temparray);
    CFRelease(pem);
    if (oserr) {
        fprintf(stderr, "SecItemImport failed (oserr=%d)\n", oserr);
        CFShow(temparray);
        return false;
    }
    
    SecKeyRef publickey = (SecKeyRef)CFArrayGetValueAtIndex(temparray, 0);
#endif

    NSString *pem = [NSString stringWithUTF8String:(char*)config_pub];
    pem = [pem stringByReplacingOccurrencesOfString:@"-----BEGIN RSA PUBLIC KEY-----" withString:@""];
    pem = [pem stringByReplacingOccurrencesOfString:@"-----END RSA PUBLIC KEY-----" withString:@""];
    pem = [NSString stringWithFormat:@"%@%@", @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A", pem];
    NSData *keyData = [[NSData alloc] initWithBase64EncodedString:pem options:NSDataBase64DecodingIgnoreUnknownCharacters];
    CFMutableDictionaryRef parameters = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
    CFDictionarySetValue(parameters, kSecAttrKeyType, kSecAttrKeyTypeRSA);
    CFDictionarySetValue(parameters, kSecAttrKeyClass, kSecAttrKeyClassPublic);
    CFErrorRef error = 0;
    SecKeyRef key = SecKeyCreateFromData(parameters, (__bridge CFDataRef)keyData, &error);
    if (error) { CFShow(error); return false; }
    SecTransformRef verifier = SecVerifyTransformCreate(key, (__bridge CFDataRef)[[NSData alloc] initWithBase64EncodedString:signature options:NSDataBase64DecodingIgnoreUnknownCharacters], &error);
    if (error) { CFShow(error); return false; }
    SecTransformSetAttribute(verifier, kSecTransformInputAttributeName, (__bridge CFDataRef)data, &error);
    if (error) { CFShow(error); return false; }
    SecTransformSetAttribute(verifier, kSecDigestTypeAttribute, kSecDigestSHA2, &error);
    if (error) { CFShow(error); return false; }
    SecTransformSetAttribute(verifier, kSecDigestLengthAttribute, (__bridge CFNumberRef)@512, &error);
    if (error) { CFShow(error); return false; }
    CFTypeRef result = SecTransformExecute(verifier, &error);
    if (error) { CFShow(error); return false; }
    return result == kCFBooleanTrue;
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
    if ([file isEqualToString:@"config.json"]) {
        if (![self verify:data]) {
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
