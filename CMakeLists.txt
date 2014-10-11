cmake_minimum_required( VERSION 2.8 )
project( id-updater )

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/modules")
set(CMAKE_FIND_ROOT_PATH ${CMAKE_OSX_SYSROOT})

include( VersionInfo )
set_app_name( PROGNAME ID-updater )

set( UPDATER_URL "http://ftp.id.eesti.ee/pub/id/updater/" CACHE STRING "URL to download manifest.xml" )
add_definitions( -DUPDATER_URL="${UPDATER_URL}" )

if( APPLE )
	set_source_files_properties( prefPane/id-updater-helper.m prefPane/id-updater.m prefPane/update.m PROPERTIES LANGUAGE C )
	add_executable( id-updater-helper prefPane/id-updater-helper.m prefPane/update.m )
	set_target_properties( id-updater-helper PROPERTIES
		COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-unused-parameter -fobjc-arc"
		LINKER_LANGUAGE C
	)
	target_link_libraries( id-updater-helper "-framework Foundation -framework PCSC" )

	add_custom_command( OUTPUT ID_updater.nib et/ID_updater.nib et/ID_updater.xib ru/ID_updater.nib ru/ID_updater.xib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile ID_updater.nib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
		# 10.7 support
		COMMAND mkdir -p et ru
		COMMAND ibtool --strings-file ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/et.lproj/ID_updater.strings
			 --write et/ID_updater.xib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
		COMMAND ibtool --strings-file ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/ru.lproj/ID_updater.strings
			 --write ru/ID_updater.xib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile et/ID_updater.nib et/ID_updater.xib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile ru/ID_updater.nib ru/ID_updater.xib
	)

	find_package( OpenSSL REQUIRED )
	find_library( XAR xar )
	add_library( ${PROGNAME} MODULE
		ID_updater.nib
		et/ID_updater.nib
		ru/ID_updater.nib
		prefPane/Base.lproj/ID_updater.xib
		prefPane/en.lproj/Localizable.strings
		prefPane/en.lproj/ID_updater.strings
		prefPane/et.lproj/Localizable.strings
		prefPane/et.lproj/ID_updater.strings
		prefPane/ru.lproj/Localizable.strings
		prefPane/ru.lproj/ID_updater.strings
		mac/Resources/Icon.icns
		prefPane/id-updater.m
		prefPane/update.m
	)
	set_source_files_properties( ID_updater.nib
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Base.lproj ) # Installed to next section for 10.7 support
	set_source_files_properties( prefPane/en.lproj/ID_updater.strings prefPane/en.lproj/Localizable.strings ID_updater.nib
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/en.lproj )
	set_source_files_properties( prefPane/et.lproj/ID_updater.strings prefPane/et.lproj/Localizable.strings et/ID_updater.nib
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/et.lproj )
	set_source_files_properties( prefPane/ru.lproj/ID_updater.strings prefPane/ru.lproj/Localizable.strings ru/ID_updater.nib
		PROPERTIES MACOSX_PACKAGE_LOCATION Resources/ru.lproj )
	set_target_properties( ${PROGNAME} PROPERTIES
		BUNDLE YES
		BUNDLE_EXTENSION prefPane
		RESOURCES mac/Resources/Icon.icns
		COMPILE_FLAGS "-Wno-deprecated-declarations -Wno-unused-parameter -fobjc-arc"
		LINKER_LANGUAGE C
		XCODE_ATTRIBUTE_WRAPPER_EXTENSION prefPane
		MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Info.plist.cmake
	)
	target_link_libraries( ${PROGNAME} ${XAR} ${OPENSSL_CRYPTO_LIBRARY}
		"-framework Security -framework Cocoa -framework PreferencePanes -framework PCSC"
	)
	install( DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROGNAME}.prefPane DESTINATION /Library/PreferencePanes )
	install( TARGETS id-updater-helper DESTINATION /Library/PreferencePanes/id-updater.prefPane/Contents/Resources )
else()
	cmake_policy( SET CMP0020 NEW )
	find_package( Qt5Network REQUIRED )
	find_package( Qt5Widgets REQUIRED )
	find_package( Qt5LinguistTools REQUIRED )

	include_directories( ${CMAKE_CURRENT_BINARY_DIR} common/qtsingleapplication/src )
	add_subdirectory( common/qtsingleapplication )

	configure_file( translations.qrc translations.qrc COPYONLY )
	qt5_add_translation( SOURCES idupdater_et.ts idupdater_ru.ts common/translations/qtbase_et.ts common/translations/qtbase_ru.ts )
	qt5_add_resources( SOURCES idupdater.qrc ${CMAKE_CURRENT_BINARY_DIR}/translations.qrc )
	qt5_wrap_ui( SOURCES idupdater.ui )

	add_executable( ${PROGNAME} WIN32
		${SOURCES}
		idupdater.rc
		Application.cpp
		idupdater.cpp
		main.cpp
		InstallChecker.cpp
		ProcessStarter.cpp
		ScheduledUpdateTask.cpp
		common/QPCSC.cpp
	)
	set_target_properties( ${PROGNAME} PROPERTIES
		AUTOMOC TRUE
		COMPILE_DEFINITIONS UNICODE
		COMPILE_FLAGS "/Zc:wchar_t-" # required for task scheduler BSTR type
	)
	target_link_libraries( ${PROGNAME} Qt5::Widgets Qt5::Network qtsingleapplication
		msi Mstask Userenv wintrust Crypt32 taskschd comsupp ws2_32 Setupapi winscard Wtsapi32
	)
	add_manifest( ${PROGNAME} )
	install( TARGETS ${PROGNAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin )
endif()
