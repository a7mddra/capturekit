cmake_minimum_required(VERSION 3.16)

if(APPLE)
    project(CAPTUREKIT LANGUAGES CXX OBJCXX)
else()
    project(CAPTUREKIT LANGUAGES CXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)

if(UNIX AND NOT APPLE)
    find_package(Qt6 REQUIRED COMPONENTS DBus)
endif()

set(PACKAGE_JSON_PATH "${CMAKE_CURRENT_SOURCE_DIR}/package.json")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${PACKAGE_JSON_PATH}")

if(EXISTS "${PACKAGE_JSON_PATH}")
    file(READ "${PACKAGE_JSON_PATH}" PACKAGE_JSON_CONTENT)
    
    string(REGEX MATCH "\"version\":[ \t]*\"([0-9]+\\.[0-9]+\\.[0-9]+)\"" _ ${PACKAGE_JSON_CONTENT})
    set(APP_VERSION ${CMAKE_MATCH_1})
    
    string(REGEX MATCH "\"organization\":[ \t]*\"([^\"]+)\"" _ ${PACKAGE_JSON_CONTENT})
    set(ORG_NAME ${CMAKE_MATCH_1})
    
    string(REGEX MATCH "\"name\":[ \t]*\"([^\"]+)\"" _ ${PACKAGE_JSON_CONTENT})
    set(APP_NAME ${CMAKE_MATCH_1})
    
    message(STATUS "🔗 Monorepo Sync: Configuring ${APP_NAME} v${APP_VERSION}")
else()
    message(FATAL_ERROR "Could not find package.json")
endif()

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/config.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/config.h"
    @ONLY
)
include_directories("${CMAKE_CURRENT_BINARY_DIR}/generated")

set(UI_SOURCES
    src/interface/DrawView.cpp
    src/interface/DrawView.h
    src/interface/Window.h
)

if(APPLE)
    list(APPEND UI_SOURCES src/interface/Window.mm)
    set_source_files_properties(src/interface/Window.mm PROPERTIES LANGUAGE OBJCXX)
else()
    list(APPEND UI_SOURCES src/interface/Window.cpp)
endif()

if(WIN32)

    set(ENGINE_SOURCES src/engine/Capture_Win.cpp)
    set(ENGINE_LIBS dwmapi gdiplus user32 gdi32)
elseif(APPLE)

    
    find_library(COREGRAPHICS_LIB CoreGraphics)
    find_library(COCOA_LIB Cocoa)
    set(ENGINE_LIBS ${COREGRAPHICS_LIB} ${COCOA_LIB})
else()

    set(ENGINE_SOURCES src/engine/Capture_Unix.cpp)
    set(ENGINE_LIBS Qt6::DBus)
endif()


if(WIN32)
    add_executable(capturekit_ui WIN32 src/main.cpp ${UI_SOURCES} ${ENGINE_SOURCES})
else()
    add_executable(capturekit_ui src/main.cpp ${UI_SOURCES} ${ENGINE_SOURCES})
endif()

target_include_directories(capturekit_ui PRIVATE 
    src/engine 
    src/interface
)

target_link_libraries(capturekit_ui PRIVATE 
    Qt6::Core 
    Qt6::Gui 
    Qt6::Widgets 
    ${ENGINE_LIBS}
)

if(UNIX)
    set_target_properties(capturekit_ui PROPERTIES
        OUTPUT_NAME "capturekit-bin"
        INSTALL_RPATH "$ORIGIN/libs"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
    install(TARGETS capturekit_ui DESTINATION bin)
endif()
