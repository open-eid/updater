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

#define UPDATER_ID @"ee.ria.id-updater"

@interface Updater : Update <UpdateDelegate> {
    NSString *path;
}
@end

@implementation Updater
- (id)initWithPath:(NSString *)_path {
    if (self = [super initWithDelegate:self]) {
        path = _path;
        NSLog(@"Installed %@: %@", path, self.baseversion);
        [self request];
    }
    return self;
}

#pragma mark - Update Delegate

- (void)didFinish:(NSError *)error {
    if (error) {
        NSLog(@"Error: %@", error.localizedDescription);
    }
    exit(0);
}

- (void)message:(NSString *)message {
    NSLog(@"%@", message);
    [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]] waitUntilExit];
}

- (void)updateAvailable:(NSString *)available filename:(NSString *)filename {
    NSLog(@"Update available %@ %@", available, filename);
    [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[path]] waitUntilExit];
}
@end

#pragma mark - Main

int main(int argc, const char * argv[])
{
    if (argc != 2)
        return 1;

    @autoreleasepool {
        if (strcmp(argv[1], "-task") == 0) {
            Updater *updater __attribute__((unused)) = [[Updater alloc] initWithPath:[NSString stringWithFormat:@"%s/../../..", argv[0]].stringByStandardizingPath];
            [NSRunLoop.mainRunLoop run];
            return 0;
        }

        NSString *PATH = (@"~/Library/LaunchAgents/ee.ria.id-updater.plist").stringByStandardizingPath;
        [NSFileManager.defaultManager createDirectoryAtPath:(@"~/Library/LaunchAgents").stringByStandardizingPath withIntermediateDirectories:YES attributes:nil error:nil];
        if (strcmp(argv[1], "-remove") == 0) {
            [[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"unload", @"-w", PATH]] waitUntilExit];
            NSError *error;
            [[NSFileManager defaultManager] removeItemAtPath:PATH error:&error];
            return 0;
        }

        NSDateComponents *components = [[NSCalendar currentCalendar]
                                        components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitWeekday|NSCalendarUnitDay
                                        fromDate:[NSDate date]];
        NSNumber *hour = @(components.hour);
        NSNumber *minute = @(components.minute);
        NSNumber *weekday = @(components.weekday);
        NSNumber *day = @(components.day);
        NSDictionary *settings = nil;
        if (strcmp(argv[1], "-daily") == 0) {
            settings = @{@"Label": UPDATER_ID,
                         @"ProgramArguments": @[@(argv[0]), @"-task"],
                         @"StartCalendarInterval": @{@"Hour": hour, @"Minute": minute}};
        } else if (strcmp(argv[1], "-weekly") == 0) {
            settings = @{@"Label": UPDATER_ID,
                         @"ProgramArguments": @[@(argv[0]), @"-task"],
                         @"StartCalendarInterval": @{@"Hour": hour, @"Minute": minute, @"Weekday": weekday}};
        } else if (strcmp(argv[1], "-monthly") == 0) {
            settings = @{@"Label": UPDATER_ID,
                         @"ProgramArguments": @[@(argv[0]), @"-task"],
                         @"StartCalendarInterval": @{@"Hour": hour, @"Minute": minute, @"Day": day}};
        } else {
            return 0;
        }
        NSError *error;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:settings format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        [data writeToFile:PATH atomically:YES];
        [[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"load", @"-w", PATH]] waitUntilExit];
    }
    return 0;
}
