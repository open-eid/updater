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

#include <sys/utsname.h>

#ifndef UPDATER_URL
#define UPDATER_URL "http://ftp.id.eesti.ee/pub/id/mac/"
#endif
#define UPDATER_ID @"ee.ria.id-updater"

@interface Update () <NSXMLParserDelegate> {
    NSMutableString *message;
}
@end

@implementation Update

- (id)initWithDelegate:(id <UpdateDelegate>)delegate {
    if (self = [super init]) {
        self.delegate = delegate;
        self.baseversion = [self versionInfo:@"ee.ria.estonianidcard"];
        self.clientversion = [self versionInfo:@"ee.ria.qdigidocclient"];
        self.utilityversion = [self versionInfo:@"ee.ria.qesteidutil"];
        self.pluginversion = [self versionInfo:@"ee.ria.esteidfirefoxplugin"];
        self.chromepluginversion = [self versionInfo:@"ee.ria.chrome-token-signing"];
        self.pkcs11version = [self versionInfo:@"ee.ria.esteid-pkcs11"];
        self.tokendversion = [self versionInfo:@"ee.ria.esteid-tokend"];
        self.loaderversion = [self versionInfo:@"ee.ria.esteidpkcs11loader"];
        NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:UPDATER_ID];
        self.url = [prefs objectForKey:@"Url"] != nil ? [prefs objectForKey:@"Url"] : @UPDATER_URL;
        NSLog(@"Url: %@", self.url);
    }
    return self;
}

- (NSString*)versionInfo:(NSString *)pkg {
    NSDictionary *list = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/db/receipts/%@.plist", pkg]];
    return list ? [list objectForKey:@"PackageVersion"] : [NSString string];
}

- (void)request {
    NSDictionary *os = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    struct utsname unameData;
    uname(&unameData);

    SCARDCONTEXT ctx = 0;
    SCardEstablishContext(SCARD_SCOPE_SYSTEM, 0, 0, &ctx);
    uint32_t size = 0;
    SCardListReaders(ctx, 0, 0, &size);
    char *readers = (char*)malloc(size * sizeof(char));
    SCardListReaders(ctx, 0, readers, &size);
    int len = 0;
    char *p = readers;
    NSMutableArray *list = [NSMutableArray array];
    while ((len = strlen(p))) {
        [list addObject:[NSString stringWithCString:p encoding:NSUTF8StringEncoding]];
        p = p + len + 1;
    }
    free(readers);
    SCardReleaseContext(ctx);

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/products.xml", self.url]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    NSString *agent = [NSString stringWithFormat:@"id-updater/%@", self.baseversion];
    if (self.clientversion) {
        agent = [NSString stringWithFormat:@"%@ qdigidocclient/%@", agent, self.clientversion];
    }
    if (self.utilityversion) {
        agent = [NSString stringWithFormat:@"%@ qesteidutility/%@", agent, self.utilityversion];
    }
    agent = [NSString stringWithFormat:@"%@ (Mac OS %@(%lu/%s)) Locale: %@ Devices: %@", agent,
             [os objectForKey:@"ProductVersion"], sizeof(void *)<<3, unameData.machine, @"UTF-8", [list componentsJoinedByString:@"/"]];
    [request addValue:agent forHTTPHeaderField:@"User-Agent"];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue new]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error)
    {
        if (error != nil) {
            [self.delegate error:error];
        } else if (data != nil) {
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
            parser.delegate = self;
            [parser parse];
        }
    }];
}

#pragma mark - XML parser delegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict {
    if ([elementName isEqualToString:@"product"]) {
        NSLog(@"Remote version: %@", [attributeDict objectForKey:@"ProductVersion"]);
        if ([(NSString*)[attributeDict objectForKey:@"ProductVersion"] compare:self.baseversion options:NSNumericSearch] > 0) {
            [self.delegate updateAvailable:[attributeDict objectForKey:@"ProductVersion"] filename:[attributeDict objectForKey:@"filename"]];
        }
    } else if ([elementName isEqualToString:@"message"]) {
        message = [NSMutableString new];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (message) {
        [message appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"message"]) {
        NSLog(@"Message: %@", message);
        [self.delegate message:message];
    }
}

@end
