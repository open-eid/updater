# Win/OSX updater component

![European Regional Development Fund](https://github.com/open-eid/DigiDoc4-Client/blob/master/client/images/EL_Regionaalarengu_Fond.png "European Regional Development Fund - DO NOT REMOVE THIS IMAGE BEFORE 05.03.2020")

 * License: LGPL 2.1
 * &copy; Estonian Information System Authority

## Building
[![Build Status](https://github.com/open-eid/updater/workflows/CI/badge.svg?branch=master)](https://github.com/open-eid/updater/actions)

### OSX

1. Fetch the source

        git clone --recursive https://github.com/open-eid/updater
        cd updater

2. Configure

        cmake -B build -S .

3. Build

        cmake --build build

4. Install

        sudo cmake --build build --target install

6. Execute

        open /Library/PreferencePanes/id-updater.prefPane

## Support
Official builds are provided through official distribution point [id.ee](https://www.id.ee/en/article/install-id-software/). If you want support, you need to be using official builds.

Source code is provided on "as is" terms with no warranty (see license for more information). Do not file Github issues with generic support requests.
