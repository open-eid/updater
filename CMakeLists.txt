cmake_minimum_required(VERSION 3.22)
project(ID-updater VERSION 3.19.0)

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
string(REPLACE ".json" ".ecpub" PUB_URL ${CONFIG_URL})
message("Fetching pub key: ${PUB_URL}")
file(DOWNLOAD ${PUB_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.ecpub)

if( APPLE )
	add_custom_command(OUTPUT config.h
		BYPRODUCTS module.modulemap
		COMMAND xxd -i config.ecpub config.h
		COMMAND echo "\\\#define CONFIG_URL \\\"${CONFIG_URL}\\\"" >> config.h
		COMMAND echo "module config [system] {" > module.modulemap
		COMMAND echo "	private header \\\"config.h\\\"" >> module.modulemap
		COMMAND echo "	export *" >> module.modulemap
		COMMAND echo "}" >> module.modulemap
		COMMENT "Generating config.h"
	)
	set(SWIFT_FLAGS xcrun --sdk macosx swiftc -I ${CMAKE_CURRENT_BINARY_DIR})
	if(CMAKE_BUILD_TYPE STREQUAL "Debug")
		list(APPEND SWIFT_FLAGS -g)
	elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
		list(APPEND SWIFT_FLAGS -O)
	elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
		list(APPEND SWIFT_FLAGS -O -g)
	elseif(CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
		list(APPEND SWIFT_FLAGS -Osize)
	endif()
	set(SWIFTMOD_DIR ${CMAKE_CURRENT_BINARY_DIR}/id_updater_lib.swiftmodule)
	set(SWIFTHDR_DIR ${CMAKE_CURRENT_BINARY_DIR}/id_updater_lib)
	add_custom_command(OUTPUT
			libid-updater-lib.a
		BYPRODUCTS
			libid-updater-lib_arm64.a
			libid-updater-lib_x86_64.a
			${SWIFTMOD_DIR}/arm64-apple-macos.swiftmodule
			${SWIFTMOD_DIR}/x86_64-apple-macos.swiftmodule
		DEPENDS
			config.h
			prefPane/AdvancedWindowController.swift
			prefPane/id-updater.swift
			prefPane/update.swift
		COMMENT "Build id-updater-lib"
		COMMAND ${CMAKE_COMMAND} -E make_directory ${SWIFTMOD_DIR}
		COMMAND ${CMAKE_COMMAND} -E make_directory ${SWIFTHDR_DIR}
		COMMAND ${SWIFT_FLAGS} -target arm64-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}
			-module-name id_updater_lib
			-emit-module -emit-module-path ${SWIFTMOD_DIR}/arm64-apple-macos.swiftmodule
			-emit-objc-header -emit-objc-header-path ${SWIFTHDR_DIR}/id_updater_lib-Swift.h
			-emit-library -static -o libid-updater-lib_arm64.a
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/AdvancedWindowController.swift
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/id-updater.swift
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/update.swift
		COMMAND ${SWIFT_FLAGS} -target x86_64-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}
			-module-name id_updater_lib
			-emit-module -emit-module-path ${SWIFTMOD_DIR}/x86_64-apple-macos.swiftmodule
			-emit-objc-header -emit-objc-header-path ${SWIFTHDR_DIR}/id_updater_lib-Swift.h
			-emit-library -static -o libid-updater-lib_x86_64.a
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/AdvancedWindowController.swift
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/id-updater.swift
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/update.swift
		COMMAND lipo -create libid-updater-lib_arm64.a libid-updater-lib_x86_64.a -output libid-updater-lib.a
	)
	add_custom_command(OUTPUT id-updater-helper
		BYPRODUCTS
			id-updater-helper_arm64
			id-updater-helper_x86_64
		DEPENDS
			${CMAKE_CURRENT_BINARY_DIR}/libid-updater-lib.a
			prefPane/update.swift
			prefPane/main.swift
		COMMENT "Build id-updater-helper"
		COMMAND ${SWIFT_FLAGS} -target arm64-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET} -parse-as-library
			-o id-updater-helper_arm64
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/update.swift
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/main.swift
		COMMAND ${SWIFT_FLAGS} -target x86_64-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET} -parse-as-library
			-o id-updater-helper_x86_64
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/update.swift
			${CMAKE_CURRENT_SOURCE_DIR}/prefPane/main.swift
		COMMAND lipo -create id-updater-helper_arm64 id-updater-helper_x86_64 -output id-updater-helper
	)

	add_custom_command( OUTPUT ID_updater.nib
		COMMAND ibtool --errors --warnings --notices --output-format human-readable-text
			--compile ID_updater.nib ${CMAKE_CURRENT_SOURCE_DIR}/prefPane/Base.lproj/ID_updater.xib
	)

	file(GLOB RESOURCE_FILES prefPane/Icon.icns prefPane/*.lproj)
	find_library( XAR xar )
	add_library(${PROJECT_NAME} MODULE
		${CMAKE_CURRENT_BINARY_DIR}/id-updater-helper
		ID_updater.nib
		${RESOURCE_FILES}
		prefPane/Icon.icns
		prefPane/id-updater.m
	)
	set_source_files_properties(ID_updater.nib PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Base.lproj)
	set_source_files_properties(${RESOURCE_FILES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
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
	target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
	target_link_libraries(${PROJECT_NAME} ${XAR} ${CMAKE_CURRENT_BINARY_DIR}/libid-updater-lib.a)
	add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
		COMMAND cp ${CMAKE_CURRENT_BINARY_DIR}/id-updater-helper $<TARGET_BUNDLE_CONTENT_DIR:${PROJECT_NAME}>/Resources
	)
	install( TARGETS ${PROJECT_NAME} DESTINATION /Library/PreferencePanes )

	# Sign bundle after resources are copied
	add_custom_target(signhelper DEPENDS ${PROJECT_NAME})
	if(SIGNCERT)
		add_custom_command(TARGET signhelper POST_BUILD
			COMMAND codesign -f --options=runtime -s "Developer ID Application: ${SIGNCERT}"
				$<TARGET_BUNDLE_CONTENT_DIR:${PROJECT_NAME}>/Resources/id-updater-helper
				$<TARGET_BUNDLE_DIR:${PROJECT_NAME}>
		)
	endif()
	add_custom_target(pkgbuild DEPENDS signhelper
		COMMAND DESTDIR=install ${CMAKE_COMMAND} --install ${CMAKE_BINARY_DIR}
		COMMAND chmod 755 install/Library/PreferencePanes/ID-updater.prefPane/Contents/Resources/id-updater-helper
		COMMAND pkgbuild --root install "$<$<BOOL:${SIGNCERT}>:--sign;${SIGNCERT}>" updater_${VERSION}$ENV{VER_SUFFIX}.pkg
		COMMAND_EXPAND_LISTS
	)
	add_custom_target(zipdebug DEPENDS ${PROJECT_NAME}
		COMMAND dsymutil -o ${PROJECT_NAME}.dSYM $<TARGET_FILE:${PROJECT_NAME}> id-updater-helper
		COMMAND zip -r updater-dbg_${VERSION}$ENV{VER_SUFFIX}.zip ${PROJECT_NAME}.dSYM
	)
else()
	if(NOT EXISTS ${CMAKE_SOURCE_DIR}/common/CMakeLists.txt)
		message(FATAL_ERROR "cmake submodule directory empty, did you 'git clone --recursive'?")
	endif()
	file(DOWNLOAD ${CONFIG_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.json)
	string(REPLACE ".json" ".ecc" ECC_URL ${CONFIG_URL})
	file(DOWNLOAD ${ECC_URL} ${CMAKE_CURRENT_BINARY_DIR}/config.ecc)
	set(CONFIG_DIR ${CMAKE_CURRENT_BINARY_DIR})

	find_package(OpenSSL 3.0.0 REQUIRED)
	find_package(Qt6 6.0.0 REQUIRED COMPONENTS Core Widgets Network LinguistTools)

	add_executable(${PROJECT_NAME} WIN32
		${SOURCES}
		Application.cpp
		idupdater.rc
		idupdater.ui
		idupdater.cpp
		ScheduledUpdateTask.cpp
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
	target_link_libraries(${PROJECT_NAME} PRIVATE Qt6::Widgets Qt6::Network OpenSSL::Crypto
		msi wintrust Crypt32 taskschd comsupp Setupapi winscard Wtsapi32
	)
	qt_add_translations(${PROJECT_NAME} TS_FILES idupdater_et.ts idupdater_ru.ts
		common/translations/common_et.ts common/translations/common_ru.ts
		common/translations/qtbase_et.ts common/translations/qtbase_ru.ts
		RESOURCE_PREFIX /
	)
	qt_add_resources(${PROJECT_NAME} icon FILES appicon.png)
	qt_add_resources(${PROJECT_NAME} config BASE ${CONFIG_DIR} PREFIX / FILES
		${CONFIG_DIR}/config.json ${CONFIG_DIR}/config.ecc ${CONFIG_DIR}/config.ecpub
	)

	if(OPENSSL_ROOT_DIR)
		set(SSL_PATH "${OPENSSL_ROOT_DIR}/bin")
	endif()
	if(NOT EXISTS "${SSL_PATH}")
		get_filename_component(SSL_PATH "${OPENSSL_INCLUDE_DIR}/../bin" ABSOLUTE)
	endif()
	set(MSI_FILE "ID-Updater-${VERSION}$ENV{VER_SUFFIX}.$ENV{PLATFORM}")
	get_target_property(qtCore_install_prefix Qt6::qmake IMPORTED_LOCATION)
	get_filename_component(qtCore_install_prefix ${qtCore_install_prefix} DIRECTORY)
	add_custom_target(installer DEPENDS ${PROJECT_NAME}
		COMMAND wix.exe build -nologo
			-arch $ENV{PLATFORM}
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
