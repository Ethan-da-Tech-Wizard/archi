cmake_minimum_required(VERSION 3.21)
project(archi VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(archi
    src/main.cpp
)

qt_add_qml_module(archi
    URI Archi
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/InfiniteCanvas.qml
        qml/ShapeItem.qml
        qml/ArrowLayer.qml
        qml/ShapeIcon.qml
        qml/LogicTest.qml
    RESOURCE_PREFIX /qt/qml
)

target_link_libraries(archi PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

set_target_properties(archi PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)
