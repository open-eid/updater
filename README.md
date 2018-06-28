# Win/OSX updater component

![European Regional Development Fund](https://github.com/e-gov/RIHA-Frontend/raw/master/logo/EU/EU.png "European Regional Development Fund - DO NOT REMOVE THIS IMAGE BEFORE 05.03.2020")

 * License: LGPL 2.1
 * &copy; Estonian Information System Authority

## Building
[![Build Status](https://travis-ci.org/open-eid/updater.svg?branch=master)](https://travis-ci.org/open-eid/updater)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/open-eid/updater?branch=master&svg=true)](https://ci.appveyor.com/project/open-eid/updater)
        
### OSX

1. Fetch the source

        git clone --recursive https://github.com/open-eid/updater
        cd updater

2. Configure

        mkdir build
        cd build
        cmake ..

3. Build

        make

4. Install

        sudo make install

6. Execute

        open /Library/PreferencePanes/id-updater.prefPane

## Support
Official builds are provided through official distribution point [installer.id.ee](https://installer.id.ee). If you want support, you need to be using official builds.

Source code is provided on "as is" terms with no warranty (see license for more information). Do not file Github issues with generic support requests.
