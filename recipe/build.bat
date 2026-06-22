@echo on
setlocal enabledelayedexpansion

:: Bazel on Windows needs a short output_user_root to avoid MAX_PATH issues
set "STARTUP_FLAGS=--output_user_root=C:/tmp"

:: Configure .bazelrc for Windows MSVC build
>> .bazelrc echo.
>> .bazelrc echo build --verbose_failures
>> .bazelrc echo build --define=PREFIX=%PREFIX:\=/%
>> .bazelrc echo build --define=PROTOC_PREFIX=%BUILD_PREFIX:\=/%
>> .bazelrc echo build --define=PROTOBUF_INCLUDE_PATH=%PREFIX:\=/%/include
>> .bazelrc echo build --local_resources=cpu=%CPU_COUNT%
>> .bazelrc echo build --define=with_cross_compiler_support=true
>> .bazelrc echo build --copt=/std:c++20 --cxxopt=/std:c++20
>> .bazelrc echo build --copt=/Zc:__cplusplus --cxxopt=/Zc:__cplusplus
>> .bazelrc echo build --cxxopt=/Zc:preprocessor --host_cxxopt=/Zc:preprocessor
>> .bazelrc echo build --cxxopt=-DANTLR4CPP_STATIC --host_cxxopt=-DANTLR4CPP_STATIC
>> .bazelrc echo common --http_connector_attempts=10
>> .bazelrc echo common --experimental_repository_downloader_retries=10

:: Prepare systemlibs definitions
if not exist third_party\systemlibs mkdir third_party\systemlibs
xcopy /E /I /Y "%PREFIX%\share\bazel\systemlibs\absl" third_party\systemlibs\absl\
if "%ERRORLEVEL%" NEQ "0" exit /b 1
xcopy /E /I /Y "%PREFIX%\share\bazel\systemlibs\protobuf" third_party\systemlibs\protobuf\
if "%ERRORLEVEL%" NEQ "0" exit /b 1
xcopy /E /I /Y "%PREFIX%\share\bazel\protobuf\bazel" third_party\systemlibs\protobuf\
if "%ERRORLEVEL%" NEQ "0" exit /b 1

:: Extract ABSEIL_VERSION
for /f "tokens=1" %%a in ('conda list -p "%PREFIX%" libabseil --fields version 2^>nul ^| findstr /r "^[^#]"') do set "ABSEIL_VERSION=%%a"
if "!ABSEIL_VERSION!" == "" (
    echo ERROR: Failed to extract ABSEIL_VERSION
    exit /b 1
)
echo ABSEIL_VERSION=!ABSEIL_VERSION!

:: Extract PROTOC_VERSION and strip trailing .0 if present (33.1.0 -> 33.1)
for /f "tokens=1" %%a in ('conda list -p "%PREFIX%" libprotobuf --fields version 2^>nul ^| findstr /r "^[^#]"') do set "PROTOC_RAW=%%a"
if "!PROTOC_RAW!" == "" (
    echo ERROR: Failed to extract PROTOC_VERSION
    exit /b 1
)
echo PROTOC_RAW=!PROTOC_RAW!
for /f "tokens=*" %%a in ('python -c "import sys,re;v=sys.argv[1];m=re.match(r'^\d+\.(\d+\.\d+)$',v);print(m.group(1) if m else v)" "!PROTOC_RAW!"') do set "PROTOC_VERSION=%%a"
echo PROTOC_VERSION=!PROTOC_VERSION!

:: Patch MODULE.bazel with version strings
python -c "import sys; p=sys.argv[1]; content=open('MODULE.bazel').read(); open('MODULE.bazel','w').write(content.replace('PROTOC_VERSION',p))" "!PROTOC_VERSION!"
if "%ERRORLEVEL%" NEQ "0" exit /b 1
python -c "import sys; p=sys.argv[1]; content=open('MODULE.bazel').read(); open('MODULE.bazel','w').write(content.replace('ABSEIL_VERSION',p))" "!ABSEIL_VERSION!"
if "%ERRORLEVEL%" NEQ "0" exit /b 1
python -c "import sys; p=sys.argv[1]; content=open('third_party/systemlibs/absl/MODULE.bazel').read(); open('third_party/systemlibs/absl/MODULE.bazel','w').write(content.replace('ABSEIL_VERSION',p))" "!ABSEIL_VERSION!"
if "%ERRORLEVEL%" NEQ "0" exit /b 1
python -c "import sys; p=sys.argv[1]; content=open('third_party/systemlibs/protobuf/MODULE.bazel').read(); open('third_party/systemlibs/protobuf/MODULE.bazel','w').write(content.replace('ABSEIL_VERSION',p))" "!ABSEIL_VERSION!"
if "%ERRORLEVEL%" NEQ "0" exit /b 1

:: Create patch for rules_cc to provide _cc_internal.freeze stub
:: when cc_common.internal_DO_NOT_USE is missing (no official bazel release has it)
set PATCH_DIR=%SRC_DIR%\rules_cc_patch
if not exist "%PATCH_DIR%" mkdir "%PATCH_DIR%"
>"%PATCH_DIR%\freeze.patch" echo --- a/cc/private/cc_internal.bzl
>>"%PATCH_DIR%\freeze.patch" echo +++ b/cc/private/cc_internal.bzl
>>"%PATCH_DIR%\freeze.patch" echo @@ -1,7 +1,15 @@
>>"%PATCH_DIR%\freeze.patch" echo  """Gracefully resolve cc_internal."""
>>"%PATCH_DIR%\freeze.patch" echo  
>>"%PATCH_DIR%\freeze.patch" echo  -# buildifier: disable=native-cc-common
>>"%PATCH_DIR%\freeze.patch" echo  -cc_internal = cc_common.internal_DO_NOT_USE^(^) if hasattr^(cc_common, "internal_DO_NOT_USE"^) else struct^(^)
>>"%PATCH_DIR%\freeze.patch" echo  +# buildifier: disable=native-cc-common
>>"%PATCH_DIR%\freeze.patch" echo  +_inner = cc_common.internal_DO_NOT_USE^(^) if hasattr^(cc_common, "internal_DO_NOT_USE"^) else None
>>"%PATCH_DIR%\freeze.patch" echo  +if _inner:
>>"%PATCH_DIR%\freeze.patch" echo  +    cc_internal = _inner
>>"%PATCH_DIR%\freeze.patch" echo  +else:
>>"%PATCH_DIR%\freeze.patch" echo  +    # Provide stub implementations when the bazel binary doesn't expose cc_internal
>>"%PATCH_DIR%\freeze.patch" echo  +    def _freeze_impl^(x^):
>>"%PATCH_DIR%\freeze.patch" echo  +        return x
>>"%PATCH_DIR%\freeze.patch" echo  +    cc_internal = struct^(freeze = _freeze_impl, check_private_api = lambda ^*args, ^**kwargs: None^)
>>"%PATCH_DIR%\freeze.patch" echo.

:: Override rules_cc with patched archive
>> MODULE.bazel echo.
>> MODULE.bazel echo archive_override(
>> MODULE.bazel echo     module_name = "rules_cc",
>> MODULE.bazel echo     urls = ["https://github.com/bazelbuild/rules_cc/archive/refs/tags/0.2.19.tar.gz"],
>> MODULE.bazel echo     patches = ["@//:rules_cc_patch/freeze.patch"],
>> MODULE.bazel echo     patch_strip = 1,
>> MODULE.bazel echo )

:: Copy release files
copy /Y release\pyproject.toml .
if "%ERRORLEVEL%" NEQ "0" exit /b 1
copy /Y release\setup.py .
if "%ERRORLEVEL%" NEQ "0" exit /b 1

:: Substitute $VERSION in pyproject.toml
python -c "import sys; content=open('pyproject.toml').read(); open('pyproject.toml','w').write(content.replace('$VERSION',sys.argv[1]))" "%PKG_VERSION%"
if "%ERRORLEVEL%" NEQ "0" exit /b 1

:: Remove cel_expr_python.ext.* extension modules from setup.py
:: These link to the same protobuf descriptors as the main module, causing
:: an internal protobuf assertion failure (duplicate descriptors in the pool).
python -c "import re; content=open('setup.py').read(); open('setup.py','w').write(re.sub(r'BazelExtension\(\n\s+cel_expr_python\.ext\.\w+,\n\s+[\"\w\.\-]+,\n\s+[\"\w\.\-]+,\n\s+\)\n,?\s*','',content,flags=re.DOTALL))"
if "%ERRORLEVEL%" NEQ "0" exit /b 1

:: Remove test files
del /Q cel_expr_python\*_test.py 2>nul

:: Build and install
%PYTHON% -m pip install -vvv .
if "%ERRORLEVEL%" NEQ "0" exit /b 1

:: Cleanup
bazel %STARTUP_FLAGS% clean --expunge
if "%ERRORLEVEL%" NEQ "0" exit /b 1

endlocal
