include(FetchContent)

find_package(GTest QUIET)

if(NOT GTest_FOUND)
  FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/release-1.12.1.zip
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)
endif()

include(GoogleTest)

function(add_moos_cpp_test target)
  set(options)
  set(one_value_args WORKING_DIRECTORY DISCOVERY_MODE)
  set(multi_value_args SOURCES LIBS LABELS SUITE_LABELS INCLUDES DEFINES ENVIRONMENT)
  cmake_parse_arguments(MOOS_TEST "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

  set(moos_build_labels ${MOOS_TEST_LABELS})

  add_executable(${target} ${MOOS_TEST_SOURCES})
  target_link_libraries(${target}
    PRIVATE
      GTest::gtest_main
      ${MOOS_TEST_LIBS}
  )
  target_include_directories(${target}
    PRIVATE
      ${PROJECT_SOURCE_DIR}/tests/cpp/support
      ${MOOS_TEST_INCLUDES}
  )
  if(MOOS_TEST_DEFINES)
    target_compile_definitions(${target}
      PRIVATE
        ${MOOS_TEST_DEFINES}
    )
  endif()

  set(discovery_args
    TEST_PREFIX "${target}."
    TEST_LIST ${target}_TESTS
  )
  if(MOOS_TEST_WORKING_DIRECTORY)
    list(APPEND discovery_args
      WORKING_DIRECTORY "${MOOS_TEST_WORKING_DIRECTORY}"
    )
  endif()
  if(MOOS_TEST_DISCOVERY_MODE)
    list(APPEND discovery_args
      DISCOVERY_MODE "${MOOS_TEST_DISCOVERY_MODE}"
    )
  endif()

  if(MOOS_TEST_LABELS OR MOOS_TEST_SUITE_LABELS OR MOOS_TEST_ENVIRONMENT)
    set(test_properties_script "${CMAKE_CURRENT_BINARY_DIR}/${target}_properties.cmake")
    set(test_properties_content "if(DEFINED ${target}_TESTS)\n")
    if(MOOS_TEST_SUITE_LABELS)
      string(APPEND test_properties_content
        "  foreach(_moos_test IN LISTS ${target}_TESTS)\n"
        "    set(_moos_labels [=[${MOOS_TEST_LABELS}]=])\n"
      )
      foreach(suite_label IN LISTS MOOS_TEST_SUITE_LABELS)
        string(FIND "${suite_label}" "=" suite_label_separator)
        if(suite_label_separator EQUAL -1)
          message(FATAL_ERROR "SUITE_LABELS entries must use SuiteName=LabelA,LabelB format: ${suite_label}")
        endif()
        string(SUBSTRING "${suite_label}" 0 ${suite_label_separator} suite_label_suite)
        math(EXPR suite_label_values_start "${suite_label_separator} + 1")
        string(SUBSTRING "${suite_label}" ${suite_label_values_start} -1 suite_label_values)
        string(REPLACE "," ";" suite_labels "${suite_label_values}")
        list(APPEND moos_build_labels ${suite_labels})
        string(APPEND test_properties_content
          "    if(_moos_test MATCHES [=[\\.${suite_label_suite}\\.]=])\n"
        )
        foreach(suite_label_value IN LISTS suite_labels)
          string(APPEND test_properties_content
            "      list(APPEND _moos_labels [=[${suite_label_value}]=])\n"
          )
        endforeach()
        string(APPEND test_properties_content "    endif()\n")
      endforeach()
      string(APPEND test_properties_content
        "    set_tests_properties(\${_moos_test} PROPERTIES LABELS \"\${_moos_labels}\")\n"
        "  endforeach()\n"
      )
    elseif(MOOS_TEST_LABELS)
      string(APPEND test_properties_content
        "  set_tests_properties(\${${target}_TESTS} PROPERTIES LABELS [=[${MOOS_TEST_LABELS}]=])\n"
      )
    endif()
    if(MOOS_TEST_ENVIRONMENT)
      string(APPEND test_properties_content
        "  set_tests_properties(\${${target}_TESTS} PROPERTIES ENVIRONMENT [=[${MOOS_TEST_ENVIRONMENT}]=])\n"
      )
    endif()
    string(APPEND test_properties_content "endif()\n")
    file(GENERATE
      OUTPUT "${test_properties_script}"
      CONTENT "${test_properties_content}"
    )
  endif()

  gtest_discover_tests(${target}
    ${discovery_args}
  )

  if(MOOS_TEST_LABELS OR MOOS_TEST_SUITE_LABELS OR MOOS_TEST_ENVIRONMENT)
    set_property(DIRECTORY APPEND PROPERTY TEST_INCLUDE_FILES "${test_properties_script}")
  endif()

  # CTest labels are case-sensitive, but generated build-system paths may not
  # be.  In particular, the default macOS filesystem aliases targets such as
  # ctest-family-pnodereporter and ctest-family-pNodeReporter.  Preserve the
  # original labels on the tests and use a lowercase key only for focused
  # build targets.
  set(moos_build_target_keys)
  list(REMOVE_DUPLICATES moos_build_labels)
  foreach(build_label IN LISTS moos_build_labels)
    if(NOT build_label MATCHES "^[A-Za-z0-9_.+-]+$")
      message(FATAL_ERROR "CTest labels used for focused builds must contain only letters, numbers, _, ., +, or -: ${build_label}")
    endif()
    string(TOLOWER "${build_label}" build_target_key)
    list(APPEND moos_build_target_keys "${build_target_key}")
  endforeach()

  list(REMOVE_DUPLICATES moos_build_target_keys)
  foreach(build_target_key IN LISTS moos_build_target_keys)
    set(family_target "ctest-family-${build_target_key}")
    if(NOT TARGET ${family_target})
      add_custom_target(${family_target})
    endif()
    add_dependencies(${family_target} ${target})
  endforeach()
endfunction()

add_subdirectory(geometry)
add_subdirectory(gen_poly)

# Desired-state checks for acknowledged upstream defects. The OpRegion workflow
# enables them and publishes their real failures separately from its required gate.
option(MOOS_ENABLE_KNOWN_ISSUE_TESTS "Build known upstream defect contracts" OFF)
if(MOOS_ENABLE_KNOWN_ISSUE_TESTS)
  add_subdirectory(known_issues)
endif()

add_subdirectory(ivpbuild)
add_subdirectory(ivpcore)
add_subdirectory(ivpsolve)

add_subdirectory(bhvutil)
add_subdirectory(behaviors)
add_subdirectory(behaviors_marine)
add_subdirectory(behaviors_colregs)
add_subdirectory(dep_behaviors)
add_subdirectory(mbutil)
add_subdirectory(alogcheck)
add_subdirectory(alogavg)
add_subdirectory(alogbin)
add_subdirectory(alogcat)
add_subdirectory(alogclip)
add_subdirectory(aloghelm)
add_subdirectory(aloggrep)
add_subdirectory(alogeplot)
add_subdirectory(alogeval)
add_subdirectory(alogcd)
add_subdirectory(alogiter)
add_subdirectory(alogload)
add_subdirectory(alogmhash)
add_subdirectory(alogpare)
add_subdirectory(alogpick)
add_subdirectory(alogrm)
add_subdirectory(alogscan)
add_subdirectory(alogsplit)
add_subdirectory(alogsort)
add_subdirectory(alogtest)
add_subdirectory(alogtm)
add_subdirectory(gen_moos_app)
add_subdirectory(nspatch)
add_subdirectory(nsplug)
add_subdirectory(pechovar)
add_subdirectory(pickpos)
add_subdirectory(pluck)
add_subdirectory(projfield)
add_subdirectory(prealm)
add_subdirectory(tagrep)
add_subdirectory(logutils)
add_subdirectory(apputil)
add_subdirectory(manifest)
add_subdirectory(genutil)
add_subdirectory(ufield)
add_subdirectory(turngeo)
add_subdirectory(polar)
add_subdirectory(geodaid)
add_subdirectory(survey)
add_subdirectory(realm)
add_subdirectory(encounters)
add_subdirectory(marine_pid)
add_subdirectory(moosgeodesy)
add_subdirectory(usim_marine)
add_subdirectory(pnodereporter)
add_subdirectory(helmivp)
add_subdirectory(isay)
add_subdirectory(logic)
add_subdirectory(uhelmscope)
add_subdirectory(contacts)
add_subdirectory(evalutil)
add_subdirectory(mission_utility)
add_subdirectory(obstacles)
add_subdirectory(ucommand)
add_subdirectory(ufldbeaconrangesensor)
add_subdirectory(ufldcollisiondetect)
add_subdirectory(uflddelve)
add_subdirectory(uplotviewer)
add_subdirectory(utimerscript)
add_subdirectory(ipfview)
add_subdirectory(marineview)
add_subdirectory(zaicview)
