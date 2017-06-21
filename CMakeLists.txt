cmake_minimum_required(VERSION 3.0)
if(POLICY CMP0043)
        cmake_policy(SET CMP0043 NEW)
endif()
if(POLICY CMP0063)
        cmake_policy(SET CMP0063 NEW)
endif()
project(id-updater VERSION 3.12.2)

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/modules")

include( VersionInfo )
set_app_name( PROGNAME ID-updater )

set_env( CONFIG_URL "https://id.eesti.ee/config.json" CACHE STRING "Set Config URL" )
set_env( SIGNCERT "" CACHE STRING "Common name of certificate to used sign binaries, empty skip signing" )
add_definitions( -DCONFIG_URL="${CONFIG_URL}" )
string( REPLACE ".json" ".pub" PUB_URL ${CONFIG_URL} )
file( DOWNLOAD ${PUB_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.pub )

if( APPLE )
	add_custom_command( OUTPUT config.h
		COMMAND xxd -i config.pub config.h
		COMMENT "Generating config.h"
	)
	include_directories( ${CMAKE_CURRENT_BINARY_DIR} )
	set_source_files_properties( prefPane/id-updater-helper.m prefPane/id-updater.m prefPane/update.m PROPERTIES LANGUAGE C )
	add_executable( id-updater-helper prefPane/id-updater-helper.m prefPane/update.m config.h )
	set_target_properties( id-updater-helper PROPERTIES
		COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-unused-parameter -fobjc-arc"
		LINKER_LANGUAGE C
	)
	target_link_libraries( id-updater-helper "-framework Foundation -framework PCSC -framework Security" )

	add_custom_command( OUTPUT ID_updater.nib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile ID_updater.nib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
	)

	find_library( XAR xar )
	add_library( ${PROGNAME} MODULE
		ID_updater.nib
		config.h
		prefPane/Base.lproj/ID_updater.xib
		prefPane/en.lproj/InfoPlist.strings
		prefPane/en.lproj/Localizable.strings
		prefPane/en.lproj/ID_updater.strings
		prefPane/et.lproj/InfoPlist.strings
		prefPane/et.lproj/Localizable.strings
		prefPane/et.lproj/ID_updater.strings
		prefPane/ru.lproj/InfoPlist.strings
		prefPane/ru.lproj/Localizable.strings
		prefPane/ru.lproj/ID_updater.strings
		prefPane/Icon.icns
		prefPane/id-updater.m
		prefPane/update.m
	)
	set_source_files_properties( prefPane/Icon.icns
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources )
	set_source_files_properties( ID_updater.nib
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Base.lproj )
	set_source_files_properties( prefPane/en.lproj/InfoPlist.strings prefPane/en.lproj/ID_updater.strings prefPane/en.lproj/Localizable.strings
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/en.lproj )
	set_source_files_properties( prefPane/et.lproj/InfoPlist.strings prefPane/et.lproj/ID_updater.strings prefPane/et.lproj/Localizable.strings
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/et.lproj )
	set_source_files_properties( prefPane/ru.lproj/InfoPlist.strings prefPane/ru.lproj/ID_updater.strings prefPane/ru.lproj/Localizable.strings
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/ru.lproj )
	set_target_properties( ${PROGNAME} PROPERTIES
		BUNDLE YES
		BUNDLE_EXTENSION prefPane
		RESOURCES prefPane/Icon.icns
		COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-unused-parameter -fobjc-arc"
		LINKER_LANGUAGE C
		XCODE_ATTRIBUTE_WRAPPER_EXTENSION prefPane
		MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Info.plist.cmake
	)
	target_link_libraries( ${PROGNAME} ${XAR}
		"-framework Security -framework Cocoa -framework PreferencePanes -framework PCSC -framework Security"
	)
	add_custom_command( TARGET ${PROGNAME} POST_BUILD
		COMMAND cp $<TARGET_FILE:id-updater-helper> $<TARGET_FILE_DIR:${PROGNAME}>/../Resources )
	install( DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROGNAME}.prefPane DESTINATION /Library/PreferencePanes )

	add_custom_target( codesign DEPENDS id-updater-helper
		COMMAND codesign -f -s "Developer ID Application: ${SIGNCERT}"
			$<TARGET_FILE_DIR:${PROGNAME}>/../Resources/id-updater-helper
			$<TARGET_FILE:${PROGNAME}>
	)
	add_custom_target( pkgbuild DEPENDS codesign
		COMMAND make install DESTDIR=install \;
			chmod 755 install/Library/PreferencePanes/ID-updater.prefPane/Contents/Resources/id-updater-helper \;
			pkgbuild
			--root install
			--sign "Developer ID Installer: ${SIGNCERT}"
			updater_${VERSION}$ENV{VER_SUFFIX}.pkg
	)
	add_custom_target( zipdebug DEPENDS ${PROGNAME}
		COMMAND dsymutil -o ${PROGNAME}.dSYM $<TARGET_FILE:${PROGNAME}>
		COMMAND dsymutil -o ${PROGNAME}.dSYM $<TARGET_FILE:id-updater-helper>
		COMMAND zip -r updater-dbg_${VERSION}$ENV{VER_SUFFIX}.zip ${PROGNAME}.dSYM
	)
else()
	file( DOWNLOAD ${CONFIG_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.json )
	string( REPLACE ".json" ".rsa" RSA_URL ${CONFIG_URL} )
	file( DOWNLOAD ${RSA_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.rsa )
	configure_file( common/config.qrc config.qrc COPYONLY )

	cmake_policy( SET CMP0020 NEW )
	find_package( OpenSSL REQUIRED )
	find_package( Qt5Network REQUIRED HINTS ${QTSDK} )
	find_package( Qt5Widgets REQUIRED HINTS ${QTSDK} )
	find_package( Qt5LinguistTools REQUIRED HINTS ${QTSDK} )

	include_directories( ${CMAKE_CURRENT_BINARY_DIR} common/qtsingleapplication/src ${OPENSSL_INCLUDE_DIR} )
	add_subdirectory( common/qtsingleapplication )

	configure_file( translations.qrc translations.qrc COPYONLY )
	qt5_add_translation( SOURCES idupdater_et.ts idupdater_ru.ts
		common/translations/qtbase_et.ts common/translations/qtbase_ru.ts
		common/translations/common_et.ts common/translations/common_ru.ts
	)
	qt5_add_resources( SOURCES idupdater.qrc ${CMAKE_CURRENT_BINARY_DIR}/translations.qrc ${CMAKE_CURRENT_BINARY_DIR}/config.qrc )
	qt5_wrap_ui( SOURCES idupdater.ui )

	add_executable( ${PROGNAME} WIN32
		${SOURCES}
		idupdater.rc
		Application.cpp
		idupdater.cpp
		ScheduledUpdateTask.cpp
		common/Common.cpp
		common/Configuration.cpp
		common/QPCSC.cpp
		common/Settings.h
	)
	set_target_properties( ${PROGNAME} PROPERTIES
		AUTOMOC TRUE
		COMPILE_DEFINITIONS "UNICODE;CONFIG_URL=\"${CONFIG_URL}\";COMMON_STATIC;NO_CACHE"
		COMPILE_FLAGS "/Zc:wchar_t-" # required for task scheduler BSTR type
	)
	target_link_libraries( ${PROGNAME} Qt5::Widgets Qt5::Network qtsingleapplication
		msi Mstask Userenv wintrust Crypt32 taskschd comsupp ws2_32 Setupapi winscard Wtsapi32 ${OPENSSL_CRYPTO_LIBRARY}
	)
	add_manifest( ${PROGNAME} )
	install( TARGETS ${PROGNAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin )

	if(CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(PLATFORM x64)
		list(APPEND CANDLE_EXTRA "-dlibs_path=C:/Openssl-Win64/bin")
	else()
		set(PLATFORM x86)
		list(APPEND CANDLE_EXTRA "-dlibs_path=C:/Openssl-Win32/bin")
	endif()
	set(MSI_FILE "ID-Updater-${VERSION}$ENV{VER_SUFFIX}.${PLATFORM}")
	add_custom_target(installer DEPENDS ${PROGNAME}
		COMMAND "$ENV{WIX}bin\\candle.exe" -nologo -arch ${PLATFORM} -dPlatform=${PLATFORM}
			-dMSI_VERSION=${VERSION} ${CANDLE_EXTRA} -dqt_path=${_qt5Core_install_prefix}
			-dupdater_path=$<TARGET_FILE:${PROGNAME}> ${CMAKE_SOURCE_DIR}/idupdater.wxs
			${CMAKE_SOURCE_DIR}/cmake/modules/WelcomeDlg2.wxs ${CMAKE_SOURCE_DIR}/cmake/modules/WixUI_Minimal2.wxs
		COMMAND "$ENV{WIX}bin\\light.exe" -nologo -o "${MSI_FILE}.msi" -ext WixUIExtension
			idupdater.wixobj  WelcomeDlg2.wixobj WixUI_Minimal2.wixobj
			-dWixUIDialogBmp=${CMAKE_SOURCE_DIR}/cmake/modules/dlgbmp.bmp
			-dWixUIBannerBmp=${CMAKE_SOURCE_DIR}/cmake/modules/banner.bmp
	)
	if(SIGNCERT)
		list(APPEND SIGNCMD signtool.exe sign /a /v /s MY /n "${SIGNCERT}" /fd SHA256
			/du http://installer.id.ee /tr http://sha256timestamp.ws.symantec.com/sha256/timestamp /td SHA256)
		add_custom_command(TARGET ${PROGNAME} POST_BUILD
			COMMAND ${SIGNCMD} $<TARGET_FILE:${PROGNAME}>
		)
		add_custom_command(TARGET installer POST_BUILD
			COMMAND ${SIGNCMD} "${MSI_FILE}.msi"
		)
	endif()
endif()
