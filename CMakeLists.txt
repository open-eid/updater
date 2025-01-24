cmake_minimum_required(VERSION 3.16)
if(POLICY CMP0074)
	cmake_policy(SET CMP0074 NEW)
endif()
project(ID-updater VERSION 3.17.0)

macro( SET_ENV NAME DEF )
	if( DEFINED ENV{${NAME}} )
		set( ${NAME} $ENV{${NAME}} ${ARGN} )
	else()
		set( ${NAME} ${DEF} ${ARGN} )
	endif()
endmacro()

set_env(BUILD_NUMBER 0)
set(VERSION ${PROJECT_VERSION}.${BUILD_NUMBER})
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
	target_compile_options(id-updater-helper PRIVATE -Wno-unused-parameter -fobjc-arc -fmodules)

	add_custom_command( OUTPUT ID_updater.nib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile ID_updater.nib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
	)
	set(EN_RESOURCES prefPane/en.lproj/InfoPlist.strings prefPane/en.lproj/ID_updater.strings prefPane/en.lproj/Localizable.strings)
	set(ET_RESOURCES prefPane/et.lproj/InfoPlist.strings prefPane/et.lproj/ID_updater.strings prefPane/et.lproj/Localizable.strings)
	set(RU_RESOURCES prefPane/ru.lproj/InfoPlist.strings prefPane/ru.lproj/ID_updater.strings prefPane/ru.lproj/Localizable.strings)

	find_library( XAR xar )
	add_library(${PROJECT_NAME} MODULE
		ID_updater.nib
		config.h
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
	set_target_properties(${PROJECT_NAME} PROPERTIES
		BUNDLE YES
		BUNDLE_EXTENSION prefPane
		RESOURCES prefPane/Icon.icns
		COMPILE_FLAGS "-Wno-unused-parameter -fobjc-arc -fmodules"
		XCODE_ATTRIBUTE_WRAPPER_EXTENSION prefPane
		MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Info.plist.cmake
		MACOSX_BUNDLE_BUNDLE_NAME ${PROJECT_NAME}
		MACOSX_BUNDLE_GUI_IDENTIFIER "ee.ria.${PROJECT_NAME}"
		MACOSX_BUNDLE_COPYRIGHT "(C) 2010-2025 Estonian Information System Authority"
		MACOSX_BUNDLE_ICON_FILE Icon.icns
		MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
		MACOSX_BUNDLE_BUNDLE_VERSION ${BUILD_NUMBER}
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "ee.ria.${PROJECT_NAME}"
	)
	target_link_libraries(${PROJECT_NAME} ${XAR})
	add_dependencies(${PROJECT_NAME} id-updater-helper)
	set_target_properties(id-updater-helper PROPERTIES
		RUNTIME_OUTPUT_DIRECTORY $<TARGET_BUNDLE_CONTENT_DIR:${PROJECT_NAME}>/Resources
	)
	install( TARGETS ${PROJECT_NAME} DESTINATION /Library/PreferencePanes )

	if(SIGNCERT)
		add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
			COMMAND codesign -f --options=runtime -s "Developer ID Application: ${SIGNCERT}"
				$<TARGET_BUNDLE_CONTENT_DIR:${PROJECT_NAME}>/Resources/id-updater-helper
				$<TARGET_BUNDLE_DIR:${PROJECT_NAME}>
		)
	endif()
	add_custom_target(pkgbuild DEPENDS ${PROJECT_NAME}
		COMMAND make install DESTDIR=install
		COMMAND chmod 755 install/Library/PreferencePanes/ID-updater.prefPane/Contents/Resources/id-updater-helper
		COMMAND pkgbuild --root install "$<$<BOOL:${SIGNCERT}>:--sign;${SIGNCERT}>" updater_${VERSION}$ENV{VER_SUFFIX}.pkg
		COMMAND_EXPAND_LISTS
	)
	add_custom_target(zipdebug DEPENDS ${PROJECT_NAME}
		COMMAND dsymutil -o ${PROJECT_NAME}.dSYM $<TARGET_FILE:${PROJECT_NAME}> $<TARGET_FILE:id-updater-helper>
		COMMAND zip -r updater-dbg_${VERSION}$ENV{VER_SUFFIX}.zip ${PROJECT_NAME}.dSYM
	)
else()
	if(NOT EXISTS ${CMAKE_SOURCE_DIR}/common/CMakeLists.txt)
		message(FATAL_ERROR "cmake submodule directory empty, did you 'git clone --recursive'?")
	endif()
	file( DOWNLOAD ${CONFIG_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.json )
	string( REPLACE ".json" ".rsa" RSA_URL ${CONFIG_URL} )
	file( DOWNLOAD ${RSA_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.rsa )
	configure_file( common/config.qrc config.qrc COPYONLY )

	find_package(OpenSSL 3.0.0 REQUIRED)
	find_package(Qt6 6.0.0 REQUIRED COMPONENTS Core Widgets Network LinguistTools)

	configure_file( translations.qrc translations.qrc COPYONLY )
	qt_add_translation(SOURCES idupdater_et.ts idupdater_ru.ts
		common/translations/qtbase_et.ts common/translations/qtbase_ru.ts
		common/translations/common_et.ts common/translations/common_ru.ts
	)

	add_executable(${PROJECT_NAME} WIN32
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
		common/qtsingleapplication/src/qtlocalpeer.cpp
		common/qtsingleapplication/src/qtsingleapplication.cpp
	)
	set_target_properties(${PROJECT_NAME} PROPERTIES
		AUTOMOC TRUE
		AUTORCC TRUE
		AUTOUIC TRUE
		COMPILE_OPTIONS "/guard:cf"
		LINK_OPTIONS "/guard:cf"
		INTERPROCEDURAL_OPTIMIZATION YES
		INTERPROCEDURAL_OPTIMIZATION_DEBUG NO
	)
	target_include_directories(${PROJECT_NAME} PRIVATE common/qtsingleapplication/src)
	target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_20)
	target_compile_definitions(${PROJECT_NAME} PRIVATE
		WIN32_LEAN_AND_MEAN
		UNICODE
		CONFIG_URL="${CONFIG_URL}"
		NO_CACHE
		VERSION="${VERSION}"
		VERSION_INF=${PROJECT_VERSION_MAJOR},${PROJECT_VERSION_MINOR},${PROJECT_VERSION_PATCH},${BUILD_NUMBER}
	)
	target_link_libraries(${PROJECT_NAME} Qt6::Widgets Qt6::Network OpenSSL::Crypto
		msi wintrust Crypt32 taskschd comsupp Setupapi winscard Wtsapi32
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
	get_target_property(qtCore_install_prefix Qt6::qmake IMPORTED_LOCATION)
	get_filename_component(qtCore_install_prefix ${qtCore_install_prefix} DIRECTORY)
	add_custom_target(installer DEPENDS ${PROJECT_NAME}
		COMMAND wix.exe build -nologo
			-arch ${PLATFORM}
			-ext WixToolset.UI.wixext
			-bv WixUIDialogBmp=${CMAKE_SOURCE_DIR}/common/dlgbmp.bmp
			-bv WixUIBannerBmp=${CMAKE_SOURCE_DIR}/common/banner.bmp
			-d appicon=${CMAKE_SOURCE_DIR}/appicon.ico
			-d qt_path=${qtCore_install_prefix}
			-d qt_suffix=$<$<CONFIG:Debug>:d>
			-d libs_path="${SSL_PATH}"
			-d updater_path=$<TARGET_FILE:${PROJECT_NAME}>
			${CMAKE_SOURCE_DIR}/idupdater.wxs
			${CMAKE_SOURCE_DIR}/common/WelcomeDlg.wxs
			${CMAKE_SOURCE_DIR}/common/WixUI_Minimal.wxs
			-o ${MSI_FILE}.msi
	)
	if(SIGNCERT)
		if(CROSSSIGNCERT)
			target_link_options(${PROJECT_NAME} PRIVATE "/INTEGRITYCHECK")
		endif()
		list(APPEND SIGNCMD signtool.exe sign /a /v /s MY /n "${SIGNCERT}" /fd SHA256
			/du http://installer.id.ee /tr http://timestamp.digicert.com /td SHA256)
		add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
			COMMAND ${SIGNCMD} "$<$<BOOL:${CROSSSIGNCERT}>:/ph;/ac;${CROSSSIGNCERT}>" $<TARGET_FILE:${PROJECT_NAME}>
			COMMAND_EXPAND_LISTS
		)
		add_custom_command(TARGET installer POST_BUILD
			COMMAND ${SIGNCMD} ${MSI_FILE}.msi
		)
	endif()
endif()
