cmake_minimum_required(VERSION 3.16)
if(POLICY CMP0074)
	cmake_policy(SET CMP0074 NEW)
endif()
project(id-updater VERSION 3.13.0 LANGUAGES CXX)

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/modules")

include( VersionInfo )
set_app_name( PROGNAME ID-updater )

set_env( CONFIG_URL "https://id.eesti.ee/config.json" CACHE STRING "Set Config URL" )
set_env( SIGNCERT "" CACHE STRING "Common name of certificate to used sign binaries, empty skip signing" )
add_definitions( -DCONFIG_URL="${CONFIG_URL}" )
string( REPLACE ".json" ".pub" PUB_URL ${CONFIG_URL} )
file( DOWNLOAD ${PUB_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.pub )

if( APPLE )
	enable_language(OBJC)
	add_custom_command( OUTPUT config.h
		COMMAND xxd -i config.pub config.h
		COMMENT "Generating config.h"
	)
	include_directories( ${CMAKE_CURRENT_BINARY_DIR} )
	add_executable( id-updater-helper prefPane/id-updater-helper.m prefPane/update.m config.h )
	target_compile_options(id-updater-helper PRIVATE "-Wno-unused-parameter" "-fobjc-arc")
	target_link_libraries(id-updater-helper "-framework Foundation -framework CryptoTokenKit -framework Security")

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
		COMPILE_FLAGS "-Wno-unused-parameter -fobjc-arc"
		XCODE_ATTRIBUTE_WRAPPER_EXTENSION prefPane
		MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Info.plist.cmake
	)
	target_link_libraries(${PROGNAME} ${XAR}
		"-framework Cocoa -framework PreferencePanes -framework CryptoTokenKit -framework Security"
	)
	add_custom_command( TARGET ${PROGNAME} POST_BUILD
		COMMAND cp $<TARGET_FILE:id-updater-helper> $<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Resources )
	install( DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROGNAME}.prefPane DESTINATION /Library/PreferencePanes )

	if(SIGNCERT)
		add_custom_target( TARGET ${PROGNAME} POST_BUILD
			COMMAND codesign -f --options=runtime -s "Developer ID Application: ${SIGNCERT}"
				$<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Resources/id-updater-helper
				$<TARGET_FILE:${PROGNAME}>
		)
	endif()
	add_custom_target( pkgbuild DEPENDS ${PROGNAME}
		COMMAND make install DESTDIR=install
		COMMAND chmod 755 install/Library/PreferencePanes/ID-updater.prefPane/Contents/Resources/id-updater-helper
		COMMAND pkgbuild --root install "$<$<BOOL:${SIGNCERT}>:--sign;${SIGNCERT}>" updater_${VERSION}$ENV{VER_SUFFIX}.pkg
		COMMAND_EXPAND_LISTS
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

	find_package( OpenSSL REQUIRED )
	find_package( Qt5 5.9.0 REQUIRED COMPONENTS Core Widgets Network LinguistTools )

	include_directories( ${CMAKE_CURRENT_BINARY_DIR} common/qtsingleapplication/src )
	add_subdirectory( common/qtsingleapplication )

	configure_file( translations.qrc translations.qrc COPYONLY )
	qt5_add_translation( SOURCES idupdater_et.ts idupdater_ru.ts
		common/translations/qtbase_et.ts common/translations/qtbase_ru.ts
		common/translations/common_et.ts common/translations/common_ru.ts
	)

	add_executable( ${PROGNAME} WIN32
		${SOURCES}
		Application.cpp
		idupdater.qrc
		idupdater.rc
		idupdater.ui
		idupdater.cpp
		ScheduledUpdateTask.cpp
		${CMAKE_CURRENT_BINARY_DIR}/translations.qrc
		${CMAKE_CURRENT_BINARY_DIR}/config.qrc
		common/Common.cpp
		common/Configuration.cpp
		common/QPCSC.cpp
	)
	set_target_properties( ${PROGNAME} PROPERTIES
		AUTOMOC TRUE
		AUTORCC TRUE
		AUTOUIC TRUE
		COMPILE_DEFINITIONS "UNICODE;CONFIG_URL=\"${CONFIG_URL}\";COMMON_STATIC;NO_CACHE"
		COMPILE_OPTIONS "/guard:cf"
		LINK_OPTIONS "/guard:cf"
		INTERPROCEDURAL_OPTIMIZATION YES
	)
	set_property(SOURCE ScheduledUpdateTask.cpp APPEND PROPERTY COMPILE_OPTIONS "/Zc:wchar_t-") # required for task scheduler BSTR type
	target_link_libraries( ${PROGNAME} Qt5::Widgets Qt5::Network qtsingleapplication OpenSSL::Crypto
		msi Mstask Userenv wintrust Crypt32 taskschd comsupp ws2_32 Setupapi winscard Wtsapi32
	)
	add_manifest( ${PROGNAME} )

	if(CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(PLATFORM x64)
		set(SSL_PATH "C:/OpenSSL-Win64/bin")
	else()
		set(PLATFORM x86)
		set(SSL_PATH "C:/OpenSSL-Win32/bin")
	endif()
	if(OPENSSL_ROOT_DIR)
		set(SSL_PATH "${OPENSSL_ROOT_DIR}/bin")
	endif()
	if(NOT EXISTS "${SSL_PATH}")
		get_filename_component(SSL_PATH "${OPENSSL_CRYPTO_LIBRARY}" DIRECTORY)
		get_filename_component(SSL_PATH "${SSL_PATH}/../bin" ABSOLUTE)
	endif()
	set(MSI_FILE "ID-Updater-${VERSION}$ENV{VER_SUFFIX}.${PLATFORM}")
	add_custom_target(installer DEPENDS ${PROGNAME}
		COMMAND "$ENV{WIX}bin\\candle.exe" -nologo -arch ${PLATFORM} -dPlatform=${PLATFORM}
			-dMSI_VERSION=${VERSION} ${CANDLE_EXTRA} -dqt_path=${_qt5Core_install_prefix}
			-dqtconf=${CMAKE_SOURCE_DIR}/qt.conf -dlibs_path="${SSL_PATH}"
			-dupdater_path=$<TARGET_FILE:${PROGNAME}> ${CMAKE_SOURCE_DIR}/idupdater.wxs
			${CMAKE_SOURCE_DIR}/cmake/modules/WelcomeDlg2.wxs ${CMAKE_SOURCE_DIR}/cmake/modules/WixUI_Minimal2.wxs
		COMMAND "$ENV{WIX}bin\\light.exe" -nologo -o "${MSI_FILE}.msi" -ext WixUIExtension
			idupdater.wixobj  WelcomeDlg2.wixobj WixUI_Minimal2.wixobj
			-dWixUIDialogBmp=${CMAKE_SOURCE_DIR}/cmake/modules/dlgbmp.bmp
			-dWixUIBannerBmp=${CMAKE_SOURCE_DIR}/cmake/modules/banner.bmp
	)
	if(SIGNCERT)
		if(CROSSSIGNCERT)
			target_link_options(${PROGNAME} PRIVATE "/INTEGRITYCHECK")
		endif()
		list(APPEND SIGNCMD signtool.exe sign /a /v /s MY /n "${SIGNCERT}" /fd SHA256
			/du http://installer.id.ee /tr http://sha256timestamp.ws.symantec.com/sha256/timestamp /td SHA256)
		add_custom_command(TARGET ${PROGNAME} POST_BUILD
			COMMAND ${SIGNCMD} "$<$<BOOL:${CROSSSIGNCERT}>:/ph;/ac;${CROSSSIGNCERT}>" $<TARGET_FILE:${PROGNAME}>
			COMMAND_EXPAND_LISTS
		)
		add_custom_command(TARGET installer POST_BUILD
			COMMAND ${SIGNCMD} "${MSI_FILE}.msi"
		)
	endif()
endif()
