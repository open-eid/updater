Id-updater version [3.12.1](https://github.com/open-eid/updater/releases/tag/v3.12.1) release notes
--------------------------------------
- Fix day of month selection

[Full Changelog](https://github.com/open-eid/updater/compare/v3.12.0...v3.12.1)


Id-updater version 3.12.0 release notes
--------------------------------------
Changes compared to ver 3.11.1

- Use Central configuration
- OSX: Run updater in userspace
- WIN: Handle WIX Burn executables


Id-updater version 3.11.1 release notes
--------------------------------------
Changes compared to ver 3.10.2

- Removed Chrome NPAPI enabler


Id-updater version 3.10.2 release notes
--------------------------------------
Changes compared to ver 3.8

- Added functionality to OSX and Windows ID-Updaters for enabling NPAPI support in Chrome browser, the -chrome-npapi flag is set.
- Added chrome-token-signing component's version number information to the OSX ID-Updater's diagnostics GUI.
- Added functionality for identifying Windows 10 operating system in Windows ID-Updater.
- Added the external server's URL value to debugging view.
- Implemented usage of the operating system's proxy settings via QT in case of Windows platform.
- Added diagnostics GUI view for OSX ID-Updater that enables to view information about the web components that are updated.
- Development of the software can now be monitored in GitHub environment: https://github.com/open-eid/updater


Id-updater version 3.8 release notes
--------------------------------------

- Created new ID-card software updater for OSX platform by using the platform’s own tools. The ID-Updater application can be managed from System Preferences.
- Improved Updater’s execution in Windows platform, the updater is run on laptops regardless of whether the user is on battery power or AC power. 
- Improved Updater system to distribute the server’s load when necessary. 
- Changed the user-agent data that is sent to the server with Windows Updater, the version number of the whole .msi package is now sent instead of only the version number of the Updater.
