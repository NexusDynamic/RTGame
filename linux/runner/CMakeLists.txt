cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX C)

find_program(GLIB_COMPILE_RESOURCES NAMES glib-compile-resources REQUIRED)
set(GRESOURCE_C   com.zeyus.rise-together.gresource.c)
set(GRESOURCE_XML com.zeyus.rise-together.gresource.xml)
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${GRESOURCE_C}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMAND ${GLIB_COMPILE_RESOURCES}
    ARGS
        --generate-source
        --sourcedir=${CMAKE_CURRENT_SOURCE_DIR}
        --target=${CMAKE_CURRENT_BINARY_DIR}/${GRESOURCE_C}
        ${GRESOURCE_XML}
    VERBATIM
    MAIN_DEPENDENCY ${GRESOURCE_XML}
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/RiseTogether-appicon.png
)


# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${CMAKE_CURRENT_BINARY_DIR}/${GRESOURCE_C}"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

set_source_files_properties(
    ${CMAKE_CURRENT_BINARY_DIR}/${GRESOURCE_C}
    PROPERTIES GENERATED TRUE
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
