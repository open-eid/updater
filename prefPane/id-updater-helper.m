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

#define PATH "/Library/LaunchAgents/ee.ria.id-updater.plist"

@interface Updater : Update <UpdateDelegate> {
    NSString *path;
}
@end

@implementation Updater
- (id)initWithPath:(NSString *)_path {
    if (self = [super initWithDelegate:self]) {
        path = _path;
        NSLog(@"Installed %@: %@", path, self.baseversion);
        [self request:YES];
    }
    return self;
}

+ (void)enableChromeNPAPI {
    NSError *error;
    NSString *users = @"/Users";
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL dir;
    for (NSString *file in [manager contentsOfDirectoryAtPath:users error:&error]) {
        NSString *user = [users stringByAppendingPathComponent:file];
        if (![manager fileExistsAtPath:user isDirectory:&dir] || !dir) {
            continue;
        }

        NSString *conf = [user stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/Local State"];
        NSData *data = [NSData dataWithContentsOfFile:conf];
        if (!data) {
            continue;
        }

        NSLog(@"Parsing file %@", conf);
        NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
        if (!json) {
            continue;
        }

        NSString *version = json[@"user_experience_metrics"][@"stability"][@"stats_version"];
        NSLog(@"Chrome version %@", version);
        if ([version compare:@"42.0.0.0" options:NSNumericSearch] < 0) {
            continue;
        }

        BOOL enabled = [json[@"browser"][@"enabled_labs_experiments"] containsObject:@"enable-npapi"];
        NSLog(@"enable-npapi %u", enabled);
        if (enabled) {
            continue;
        }

        [json[@"browser"][@"enabled_labs_experiments"] addObject:@"enable-npapi"];
        data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
        if (!data) {
            NSLog(@"Failed to create JSON %@", error);
            continue;
        }

        if (![data writeToFile:conf atomically:NO]) {
            NSLog(@"Failed to save file");
        }
    }
}

#pragma mark - Update Delegate

- (void)error:(NSError *)error {
    NSLog(@"Error: %@", error.localizedDescription);
}

- (void)message:(NSString *)message {
    NSLog(@"TMP %@", @[path]);
    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
}

- (void)updateAvailable:(NSString *)available filename:(NSString *)filename {
    NSLog(@"TMP %@", @[path]);
    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]];
}
@end

#pragma mark - Main

int main(int argc, const char * argv[])
{
    if (argc != 2)
        return 1;

    @autoreleasepool {
        if (strcmp(argv[1], "-chrome-npapi") == 0) {
            [Updater enableChromeNPAPI];
            return 0;
        }

        if (strcmp(argv[1], "-task") == 0) {
            [[Updater alloc] initWithPath:[[NSString stringWithFormat:@"%s/../../..", argv[0]] stringByStandardizingPath]];
            return 0;
        }

        if (strcmp(argv[1], "-remove") == 0) {
            system("/bin/launchctl unload -w " PATH);
            NSError *error;
            [[NSFileManager defaultManager] removeItemAtPath:@PATH error:&error];
            return 0;
        }

        NSDateComponents *components = [[NSCalendar currentCalendar]
                                        components:NSHourCalendarUnit|NSMinuteCalendarUnit|NSWeekdayCalendarUnit|NSDayCalendarUnit
                                        fromDate:[NSDate date]];
        NSNumber *hour = [NSNumber numberWithInteger:[components hour]];
        NSNumber *minute = [NSNumber numberWithInteger:[components minute]];
        NSNumber *weekday = [NSNumber numberWithInteger:[components weekday]];
        NSNumber *day = [NSNumber numberWithInteger:[components day]];
        NSDictionary *settings = nil;
        if (strcmp(argv[1], "-daily") == 0) {
            settings = @{@"Label": @"id updater task",
                         @"ProgramArguments": @[[NSString stringWithUTF8String:argv[0]], @"-task"],
                         @"StartCalendarInterval": @{@"Hour": hour, @"Minute": minute}};
        } else if (strcmp(argv[1], "-weekly") == 0) {
            settings = @{@"Label": @"id updater task",
                         @"ProgramArguments": @[[NSString stringWithUTF8String:argv[0]], @"-task"],
                         @"StartCalendarInterval": @{@"Hour": hour, @"Minute": minute, @"Weekday": weekday}};
        } else if (strcmp(argv[1], "-monthly") == 0) {
            settings = @{@"Label": @"id updater task",
                         @"ProgramArguments": @[[NSString stringWithUTF8String:argv[0]], @"-task"],
                         @"StartCalendarInterval": @{@"Hour": hour, @"Minute": minute, @"Day": day}};
        } else {
            return 0;
        }
        NSString *errorstr;
        NSData *data = [NSPropertyListSerialization dataFromPropertyList:settings format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorstr];
        [data writeToFile:@PATH atomically:YES];
        system("/bin/launchctl load -w " PATH);
    }
    return 0;
}
