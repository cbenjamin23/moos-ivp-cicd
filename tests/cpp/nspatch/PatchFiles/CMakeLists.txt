set(NSPATCH_SRC ${MOOSIVP_SOURCE_TREE_BASE}/ivp/src/app_nspatch)

add_moos_cpp_test(test_nspatch_patch_files
  SOURCES
    PatchFilesTest.cpp
    ${NSPATCH_SRC}/BHVFile.cpp
    ${NSPATCH_SRC}/MOOSFile.cpp
    ${NSPATCH_SRC}/PatchApplicator.cpp
    ${NSPATCH_SRC}/Populator_BHVFile.cpp
    ${NSPATCH_SRC}/Populator_MOOSFile.cpp
  LIBS
    mbutil
  INCLUDES
    ${NSPATCH_SRC}
  LABELS
    nspatch
    merged-upstream
    PatchFiles
)
