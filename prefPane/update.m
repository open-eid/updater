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

#import <CryptoTokenKit/CryptoTokenKit.h>
#import <Security/Security.h>

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
        self.updaterversion = [self versionInfo:@"ee.ria.ID-updater"];
        self.baseversion = [self versionInfo:@"ee.ria.open-eid"];
        self.clientversion = [self versionInfo:@"ee.ria.qdigidocclient"];
        self.digidoc4 = [self versionInfo:@"ee.ria.qdigidoc4"];
        self.utilityversion = [self versionInfo:@"ee.ria.qesteidutil"];
    }
    return self;
}

- (BOOL)checkCertificatePinning:(NSURLAuthenticationChallenge *)challenge {
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecTrustResultType trustResult;
    SecTrustEvaluate(serverTrust, &trustResult);
    if ((trustResult == kSecTrustResultUnspecified ||
         trustResult == kSecTrustResultProceed) &&
        SecTrustGetCertificateCount(serverTrust) > 0) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, 0);
        NSData *der = CFBridgingRelease(SecCertificateCopyData(certificate));
        return [self.cert_bundle containsObject:der];
    }
    return NO;
}

- (void)request {
    NSURL *url = [NSURL URLWithString:@CONFIG_URL];
    url = [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"config.rsa"];
    request = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    [request addValue:[self userAgent:YES] forHTTPHeaderField:@"User-Agent"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [self receivedData:data withResponse:response];
    }] resume];
}

- (NSString*)userAgent:(BOOL)diangostics {
    NSDictionary *os = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    struct utsname unameData;
    uname(&unameData);

    NSString *devices = [TKSmartCardSlotManager.defaultManager.slotNames componentsJoinedByString:@"/"];
    NSMutableArray *agent = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"id-updater/%@", self.updaterversion]];
    if (diangostics && self.clientversion.length) {
        [agent addObject:[NSString stringWithFormat:@"qdigidocclient/%@", self.clientversion]];
    }
    if (diangostics && self.utilityversion.length) {
        [agent addObject:[NSString stringWithFormat:@"qesteidutility/%@", self.utilityversion]];
    }
    if (diangostics && self.digidoc4.length) {
        [agent addObject:[NSString stringWithFormat:@"qdigidoc4/%@", self.digidoc4]];
    }
    NSString *locale = NSBundle.mainBundle.preferredLocalizations[0];
    [agent addObject:[NSString stringWithFormat:@"(Mac OS %@ (%lu/%s)) Locale: %@ / %@ Devices: %@",
        os[@"ProductVersion"], sizeof(void *)<<3, unameData.machine, locale, @"UTF-8", devices]];
    return [agent componentsJoinedByString:@" "];
}

- (BOOL)verify:(NSData *)data error:(NSError **)error {
    NSString *pem = @((char*)config_pub);
    pem = [pem stringByReplacingOccurrencesOfString:@"-----BEGIN RSA PUBLIC KEY-----" withString:@""];
    pem = [pem stringByReplacingOccurrencesOfString:@"-----END RSA PUBLIC KEY-----" withString:@""];
    pem = [NSString stringWithFormat:@"%@%@", @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A", pem];
    NSData *keyData = [[NSData alloc] initWithBase64EncodedString:pem options:NSDataBase64DecodingIgnoreUnknownCharacters];
    NSDictionary *parameters = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic
    };
    CFErrorRef err = nil;
    id key = CFBridgingRelease(SecKeyCreateFromData((__bridge CFDictionaryRef)parameters, (__bridge CFDataRef)keyData, &err));
    if (err) { if(error) *error = CFBridgingRelease(err); return false; }

    NSData *signatureData = [[NSData alloc] initWithBase64EncodedString:signature options:NSDataBase64DecodingIgnoreUnknownCharacters];
    BOOL isValid = SecKeyVerifySignature((__bridge SecKeyRef)key, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA512,
                                         (__bridge CFDataRef)data, (__bridge CFDataRef)signatureData, &err);
    if (err) { if(error) *error = CFBridgingRelease(err); return false; }
    return isValid;
}

- (BOOL)verifyCMSSignature:(NSData *)signatureData data:(NSData *)data cert:(NSData *)cert {
    #define RETURN_IF_OERROR(MSG) if (oserr) { NSLog(MSG); return false; }
    CMSDecoderRef decoderRef;
    OSStatus oserr = CMSDecoderCreate(&decoderRef);
    RETURN_IF_OERROR(@"CMSDecoderCreate")
    id decoder = CFBridgingRelease(decoderRef);

    oserr = CMSDecoderUpdateMessage((__bridge CMSDecoderRef)decoder, signatureData.bytes, signatureData.length);
    RETURN_IF_OERROR(@"CMSDecoderUpdateMessage")
    oserr = CMSDecoderFinalizeMessage((__bridge CMSDecoderRef)decoder);
    RETURN_IF_OERROR(@"CMSDecoderFinalizeMessage")
    oserr = CMSDecoderSetDetachedContent((__bridge CMSDecoderRef)decoder, (__bridge CFDataRef)data);
    RETURN_IF_OERROR(@"CMSDecoderSetDetachedContent")

    size_t numSignersOut = 0;
    oserr = CMSDecoderGetNumSigners((__bridge CMSDecoderRef)decoder, &numSignersOut);
    RETURN_IF_OERROR(@"CMSDecoderGetNumSigners")
    if (numSignersOut != 1) {
        NSLog(@"Invalid number of signers: %lu", numSignersOut);
        return false;
    }

    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CMSSignerStatus status;
    oserr = CMSDecoderCopySignerStatus((__bridge CMSDecoderRef)decoder, 0, policy, TRUE, &status, nil, nil);
    CFRelease(policy);
    RETURN_IF_OERROR(@"CMSDecoderCopySignerStatus")
    bool isValid = status == kCMSSignerValid;

    SecCertificateRef signerCert;
    oserr = CMSDecoderCopySignerCert((__bridge CMSDecoderRef)decoder, 0, &signerCert);
    RETURN_IF_OERROR(@"CMSDecoderCopySignerCert")
    bool isSameCert = [cert isEqualToData:CFBridgingRelease(SecCertificateCopyData(signerCert))];
    CFRelease(signerCert);

    NSLog(@"Signature is (%d) and cert is equal(%d)", isValid, isSameCert);
    return isValid && isSameCert;
}

- (NSString*)versionInfo:(NSString *)pkg {
    NSDictionary *list = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/db/receipts/%@.plist", pkg]];
    return list ? list[@"PackageVersion"] : [NSString string];
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self checkCertificatePinning:challenge]) {
            completionHandler(NSURLSessionAuthChallengeUseCredential,
                              [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
        } else {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        }
    }
}

- (void)receivedData:(NSData *)data withResponse:(NSURLResponse *)response {
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
        NSMutableArray *certs = [NSMutableArray arrayWithCapacity:[self.centralConfig[@"CERT-BUNDLE"] count]];
        for (NSString *b64 in self.centralConfig[@"CERT-BUNDLE"]) {
            [certs addObject:[[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters]];
        }
        self.cert_bundle = certs;
        NSString *version = json[@"OSX-LATEST"];
        if (version) {
            NSLog(@"Remote version: %@", version);
            if ([version compare:self.baseversion options:NSNumericSearch] > 0) {
                [self.delegate updateAvailable:version filename:json[@"OSX-DOWNLOAD"]];
            }
        }
        NSString *message_url = json[@"UPDATER-MESSAGE-URL"];
        if (message_url) {
            NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:Nil];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:message_url]
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
            [request addValue:[self userAgent:NO] forHTTPHeaderField:@"User-Agent"];
            [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = (NSHTTPURLResponse*)response;
                if (http.statusCode != 200) {
                    [self.delegate didFinish:nil];
                    return;
                }
                [self.delegate message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
                [self.delegate didFinish:nil];
            }] resume];
            return;
        }
        NSString *message = json[@"OSX-MESSAGE"];
        if (message) {
            NSLog(@"Message: %@", message);
            [self.delegate message:message];
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
