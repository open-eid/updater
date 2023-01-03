cmake_minimum_required(VERSION 3.16)
if(POLICY CMP0074)
	cmake_policy(SET CMP0074 NEW)
endif()
project(id-updater VERSION 3.14.0)

set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake/modules)

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
	add_executable( id-updater-helper prefPane/id-updater-helper.m prefPane/update.m config.h )
	target_compile_options(id-updater-helper PRIVATE "-Wno-unused-parameter" "-fobjc-arc")
	target_link_libraries(id-updater-helper "-framework Foundation -framework CryptoTokenKit -framework Security")

	add_custom_command( OUTPUT ID_updater.nib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile ID_updater.nib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
	)
	set(EN_RESOURCES prefPane/en.lproj/InfoPlist.strings prefPane/en.lproj/ID_updater.strings prefPane/en.lproj/Localizable.strings)
	set(ET_RESOURCES prefPane/et.lproj/InfoPlist.strings prefPane/et.lproj/ID_updater.strings prefPane/et.lproj/Localizable.strings)
	set(RU_RESOURCES prefPane/ru.lproj/InfoPlist.strings prefPane/ru.lproj/ID_updater.strings prefPane/ru.lproj/Localizable.strings)

	find_library( XAR xar )
	add_library( ${PROGNAME} MODULE
		ID_updater.nib
		config.h
		prefPane/Base.lproj/ID_updater.xib
		${EN_RESOURCES}
		${ET_RESOURCES}
		${RU_RESOURCES}
		prefPane/Icon.icns
		prefPane/id-updater.m
		prefPane/update.m
	)
	set_source_files_properties(prefPane/Icon.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
	set_source_files_properties(ID_updater.nib PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Base.lproj)
	set_source_files_properties(${EN_RESOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/en.lproj)
	set_source_files_properties(${ET_RESOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/et.lproj)
	set_source_files_properties(${RU_RESOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/ru.lproj)
	set_target_properties( ${PROGNAME} PROPERTIES
		BUNDLE YES
		BUNDLE_EXTENSION prefPane
		RESOURCES prefPane/Icon.icns
		COMPILE_FLAGS "-Wno-unused-parameter -fobjc-arc"
		XCODE_ATTRIBUTE_WRAPPER_EXTENSION prefPane
		MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Info.plist.cmake
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "ee.ria.${PROGNAME}"
	)
	target_link_libraries(${PROGNAME} ${XAR}
		"-framework Cocoa -framework PreferencePanes -framework CryptoTokenKit -framework Security"
	)
	add_custom_command( TARGET ${PROGNAME} POST_BUILD
		COMMAND cp $<TARGET_FILE:id-updater-helper> $<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Resources )
	install( TARGETS ${PROGNAME} DESTINATION /Library/PreferencePanes )

	add_custom_target( signhelper DEPENDS ${PROGNAME} )
	if(SIGNCERT)
		add_custom_command( TARGET signhelper POST_BUILD
			COMMAND codesign -f --options=runtime -s "Developer ID Application: ${SIGNCERT}"
				$<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Resources/id-updater-helper
				$<TARGET_BUNDLE_DIR:${PROGNAME}>
		)
	endif()
	add_custom_target( pkgbuild DEPENDS signhelper
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
	find_package(QT NAMES Qt6 Qt5 COMPONENTS Core REQUIRED)
	find_package(Qt${QT_VERSION_MAJOR} 5.12.0 REQUIRED COMPONENTS Core Widgets Network LinguistTools)
	if(${QT_VERSION} VERSION_LESS "5.15.0")
		macro(qt_add_translation)
			qt5_add_translation(${ARGN})
		endmacro()
	endif()

	include_directories( ${CMAKE_CURRENT_BINARY_DIR} common/qtsingleapplication/src )
	add_subdirectory( common/qtsingleapplication )

	configure_file( translations.qrc translations.qrc COPYONLY )
	qt_add_translation(SOURCES idupdater_et.ts idupdater_ru.ts
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
		COMPILE_OPTIONS "/guard:cf"
		LINK_OPTIONS "/guard:cf"
		INTERPROCEDURAL_OPTIMIZATION YES
		INTERPROCEDURAL_OPTIMIZATION_DEBUG NO
	)
	target_compile_definitions(${PROGNAME} PRIVATE WIN32_LEAN_AND_MEAN UNICODE CONFIG_URL="${CONFIG_URL}" COMMON_STATIC NO_CACHE)
	target_link_libraries( ${PROGNAME} Qt${QT_VERSION_MAJOR}::Widgets Qt${QT_VERSION_MAJOR}::Network qtsingleapplication OpenSSL::Crypto
		msi Mstask Userenv wintrust Crypt32 taskschd comsupp ws2_32 Setupapi winscard Wtsapi32
	)

	if(CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(PLATFORM x64)
	else()
		set(PLATFORM x86)
	endif()
	if(OPENSSL_ROOT_DIR)
		set(SSL_PATH "${OPENSSL_ROOT_DIR}/bin")
	endif()
	if(NOT EXISTS "${SSL_PATH}")
		get_filename_component(SSL_PATH "${OPENSSL_INCLUDE_DIR}/../bin" ABSOLUTE)
	endif()
	set(MSI_FILE "ID-Updater-${VERSION}$ENV{VER_SUFFIX}.${PLATFORM}")
	get_target_property(qtCore_install_prefix Qt${QT_VERSION_MAJOR}::qmake IMPORTED_LOCATION)
	get_filename_component(qtCore_install_prefix ${qtCore_install_prefix} DIRECTORY)
	add_custom_target(installer DEPENDS ${PROGNAME}
		COMMAND "$ENV{WIX}bin\\candle.exe" -nologo -arch ${PLATFORM} -dPlatform=${PLATFORM}
			-dMSI_VERSION=${VERSION} -dqt_path=${qtCore_install_prefix} -dqt_ver_major=${QT_VERSION_MAJOR}
			-dqt_suffix=$<$<CONFIG:Debug>:d> -dqtconf=${CMAKE_SOURCE_DIR}/qt.conf -dlibs_path="${SSL_PATH}"
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
