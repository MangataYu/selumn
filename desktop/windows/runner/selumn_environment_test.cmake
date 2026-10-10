cmake_minimum_required(VERSION 3.14)
include("${CMAKE_CURRENT_LIST_DIR}/selumn_environment.cmake")

set(production "U0VMVU1OX0VOVklST05NRU5UPXByb2R1Y3Rpb24=")
set(staging "U0VMVU1OX0VOVklST05NRU5UPXN0YWdpbmc=")
set(development "U0VMVU1OX0VOVklST05NRU5UPWRldmVsb3BtZW50")
set(other "RkxVVFRFUl9CVUlMRF9OVU1CRVI9OTc=")

# Fatal errors run in child CMake processes so rejection is testable.
if(DEFINED rejection_case)
  if(rejection_case STREQUAL "unknown")
    set(invalid "U0VMVU1OX0VOVklST05NRU5UPWludmFsaWQ=")
  elseif(rejection_case STREQUAL "empty")
    set(invalid "U0VMVU1OX0VOVklST05NRU5UPQ==")
  elseif(rejection_case STREQUAL "missing_equals")
    set(invalid "U0VMVU1OX0VOVklST05NRU5U")
  elseif(rejection_case STREQUAL "duplicate")
    set(invalid "${staging},${staging}")
  elseif(rejection_case STREQUAL "conflicting")
    set(invalid "${staging},${production}")
  elseif(rejection_case STREQUAL "duplicate_tool_variable")
    set(invalid_tool "DART_DEFINES=${staging};DART_DEFINES=${staging}")
  elseif(rejection_case STREQUAL "inconsistent_sources")
    set(invalid "${staging}")
    set(invalid_tool "DART_DEFINES=${production}")
  else()
    message(FATAL_ERROR "Unknown test case.")
  endif()
  selumn_windows_product_name(actual "${invalid}" "${invalid_tool}")
  return()
endif()

function(expect_name expected definitions tool_environment)
  selumn_windows_product_name(actual "${definitions}" "${tool_environment}")
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Expected '${expected}', got '${actual}'.")
  endif()
endfunction()

expect_name("Selume" "" "")
expect_name("Selume" "${other}" "")
expect_name("Selume" "${production}" "")
expect_name("Selume Staging" "${staging}" "")
expect_name("Selume Development" "${development}" "")
expect_name("Selume" "" "FLUTTER_ROOT=test;DART_DEFINES=${other}")
expect_name("Selume Staging" ""
  "FLUTTER_ROOT=test;DART_DEFINES=${other},${staging};TRACK_WIDGET_CREATION=true")
expect_name("Selume Development" "" "DART_DEFINES=${development},${other}")
expect_name("Selume Staging" "${staging}" "DART_DEFINES=${staging}")

foreach(case IN ITEMS unknown empty missing_equals duplicate conflicting
    duplicate_tool_variable inconsistent_sources)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" "-Drejection_case=${case}"
      -P "${CMAKE_CURRENT_LIST_FILE}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(result EQUAL 0 OR NOT error MATCHES "SELUMN_ENVIRONMENT|DART_DEFINES")
    message(FATAL_ERROR "Expected rejection for ${case}: ${output}${error}")
  endif()
endforeach()
message(STATUS "Selumn native environment checks passed (16 cases).")
