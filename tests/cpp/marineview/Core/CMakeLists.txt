find_package(TIFF QUIET)
find_package(OpenGL QUIET)
find_package(FLTK QUIET)

find_package(MOOSGeodesy QUIET CONFIG
  HINTS
    ${MOOSIVP_SOURCE_TREE_BASE}/build/MOOS/MOOSGeodesy
)

if(TARGET MOOSGeodesy)
  set(MOOSGEODESY_TEST_LIBS MOOSGeodesy)
elseif(MOOSGeodesy_LIBRARIES)
  set(MOOSGEODESY_TEST_LIBS ${MOOSGeodesy_LIBRARIES})
else()
  find_library(MOOSGEODESY_LIBRARY
    NAMES MOOSGeodesy
    HINTS
      ${MOOSIVP_SOURCE_TREE_BASE}/build/MOOS/MOOSGeodesy/lib
  )
  set(MOOSGEODESY_TEST_LIBS ${MOOSGEODESY_LIBRARY})
endif()

if(MOOSGeodesy_INCLUDE_DIRS)
  set(MOOSGEODESY_TEST_INCLUDES ${MOOSGeodesy_INCLUDE_DIRS})
else()
  find_path(MOOSGEODESY_INCLUDE_DIR
    NAMES MOOS/libMOOSGeodesy/MOOSGeodesy.h
    HINTS
      ${MOOSIVP_SOURCE_TREE_BASE}/MOOS/MOOSGeodesy/libMOOSGeodesy/include
      ${MOOSIVP_SOURCE_TREE_BASE}/MOOS_Jul2724/MOOSGeodesy/libMOOSGeodesy/include
      ${MOOSIVP_SOURCE_TREE_BASE}/MOOS_Jul0519/MOOSGeodesy/libMOOSGeodesy/include
  )
  set(MOOSGEODESY_TEST_INCLUDES ${MOOSGEODESY_INCLUDE_DIR})
endif()

if(NOT MOOSGEODESY_TEST_LIBS OR NOT MOOSGEODESY_TEST_INCLUDES)
  message(FATAL_ERROR "Could not find MOOSGeodesy library/include under ${MOOSIVP_SOURCE_TREE_BASE}")
endif()

set(MARINEVIEW_SRC ${MOOSIVP_SOURCE_TREE_BASE}/ivp/src/lib_marineview)
get_filename_component(MARINEVIEW_DATA_DIR ${MOOSIVP_SOURCE_TREE_BASE}/ivp/data ABSOLUTE)
get_filename_component(MARINEVIEW_DATAX_DIR ${MOOSIVP_SOURCE_TREE_BASE}/ivp/datax ABSOLUTE)

if(APPLE)
  set(MARINEVIEW_PLATFORM_DEFINE OPSYS_IS_OS_X=1)
else()
  set(MARINEVIEW_PLATFORM_DEFINE OPSYS_IS_LINUX=1)
endif()

add_moos_cpp_test(test_marineview_core
  SOURCES
    MarineViewCoreTest.cpp
    ${MARINEVIEW_SRC}/LMV_Utils.cpp
    ${MARINEVIEW_SRC}/OpAreaSpec.cpp
    ${MARINEVIEW_SRC}/VehicleSet.cpp
  LIBS
    geodaid
    contacts
    geometry
    mbutil
    ${MOOS_LIBRARIES}
    ${MOOSGEODESY_TEST_LIBS}
  INCLUDES
    ${MOOSGEODESY_TEST_INCLUDES}
  DEFINES
    MARINEVIEW_ENABLE_CORE_TESTS
  LABELS
    marineview
    pMarineViewer
  SUITE_LABELS
    BearingLineTest=BearingLine
    LMVUtilsTest=LMV_Utils
    OpAreaSpecTest=OpAreaSpec
    VehicleSetTest=VehicleSet
)

if(TIFF_FOUND AND OpenGL_FOUND)
  add_moos_cpp_test(test_marineview_backimg
    SOURCES
      MarineViewCoreTest.cpp
      ${MARINEVIEW_SRC}/BackImg.cpp
      ${MARINEVIEW_SRC}/TiffUtils.cpp
    LIBS
      geometry
      mbutil
      ${TIFF_LIBRARIES}
      ${OPENGL_LIBRARIES}
      ${MOOSGEODESY_TEST_LIBS}
    INCLUDES
      ${MOOSGEODESY_TEST_INCLUDES}
      ${TIFF_INCLUDE_DIRS}
    DEFINES
      MARINEVIEW_ENABLE_BACKIMG_TESTS
      ${MARINEVIEW_PLATFORM_DEFINE}
      DATA_DIR="${MARINEVIEW_DATA_DIR}"
      DATA_DIRX="${MARINEVIEW_DATAX_DIR}"
    LABELS
      marineview
      pMarineViewer
      requires_tiff
      requires_opengl
    SUITE_LABELS
      BackImgTest=BackImg
  )
else()
  message(STATUS "Skipping marineview BackImg CTests because TIFF or OpenGL was not found")
endif()

if(TIFF_FOUND AND OpenGL_FOUND AND FLTK_FOUND)
  add_moos_cpp_test(test_marineview_gui
    SOURCES
      MarineViewCoreTest.cpp
      ${MARINEVIEW_SRC}/VehicleSet.cpp
    LIBS
      marineview
      geodaid
      contacts
      geometry
      mbutil
      ${TIFF_LIBRARIES}
      ${OPENGL_LIBRARIES}
      ${FLTK_LIBRARIES}
      ${MOOS_LIBRARIES}
      ${MOOSGEODESY_TEST_LIBS}
    INCLUDES
      ${MOOSGEODESY_TEST_INCLUDES}
      ${TIFF_INCLUDE_DIRS}
      ${FLTK_INCLUDE_DIR}
    DEFINES
      MARINEVIEW_ENABLE_GUI_TESTS
    LABELS
      marineview
      pMarineViewer
      gui
      requires_tiff
      requires_fltk
      requires_opengl
    SUITE_LABELS
      MarineViewerTest=MarineViewer
      MarineGUITest=MarineGUI,MarineViewWidgets
      MarineVehiGUITest=MarineVehiGUI,MarineViewWidgets
  )
else()
  message(STATUS "Skipping marineview GUI CTests because TIFF, OpenGL, or FLTK was not found")
endif()

add_moos_cpp_test(test_marineview_shapes
  SOURCES
    ShapeCatalogTest.cpp
  LABELS
    marineview
    MarineViewShapes
    pMarineViewer
)

add_moos_cpp_test(test_marineview_legacy_shapes
  SOURCES
    ShapeLegacyCatalogTest.cpp
  LABELS
    marineview
    MarineViewShapes
    pMarineViewer
)
