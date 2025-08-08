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

#import <Foundation/Foundation.h>

@protocol UpdateDelegate <NSObject>
- (void)didFinish:(NSError*)error;
- (void)message:(NSString*)message;
- (void)updateAvailable:(NSString*)available filename:(NSString*)filename;
@end

@interface Update : NSObject <NSURLSessionDelegate>

enum {
    InvalidSignature = 1000,
    DateLaterThanCurrent = 1001,
    FileNotFound = 1002,
    KeyError = 1003,
};

- (id)init;
- (id)initWithDelegate:(id <UpdateDelegate>)delegate;
- (BOOL)checkCertificatePinning:(NSURLAuthenticationChallenge *)challenge;
- (void)request;
- (NSString *)userAgent:(BOOL)diagnostics;
- (BOOL)verifyCMSSignature:(NSData *)signatureData data:(NSData *)data cert:(NSData *)cert;
- (NSString*)versionInfo:(NSString *)pkg;

@property(nonatomic, readonly, getter=getBaseversion) NSString *baseversion;
@property(retain) NSString *updaterversion;
@property(retain) NSString *digidoc4;
@property(retain) NSArray *cert_bundle;
@property(assign) id <UpdateDelegate> delegate;
@end
