copy release\pyproject.toml .
copy release\setup.py .

REM Remove any windows --remote_cache= line from .bazelrc to avoid issues with CI
sed -i "/windows --remote_cache=/d" .bazelrc

REM Point Bazel at the MSYS2 bash provided by m2-base.
set "BAZEL_SH=%BUILD_PREFIX%\Library\usr\bin\bash.exe"


REM Use a short output base on the build drive to avoid Windows MAX_PATH
REM issues with the deeply nested bazel output tree.
for %%d in ("%SRC_DIR%") do set "BLDDRIVE=%%~dd"
set "BAZEL_OB=%BLDDRIVE%\_b"
md "%BAZEL_OB%" 2>nul

echo.>> .bazelrc
echo startup --output_base=%BAZEL_OB:\=/%>> .bazelrc

REM Substitute $VERSION in pyproject.toml with the value of PKG_VERSION.
powershell -NoProfile -Command "(Get-Content pyproject.toml) -replace '\$VERSION', $env:PKG_VERSION | Set-Content pyproject.toml"

REM Remove cel_expr_python.ext.* BazelExtension blocks from setup.py.
powershell -NoProfile -Command "$s = Get-Content setup.py -Raw; $s = [regex]::Replace($s, '(?ms)^[^\r\n]*BazelExtension\([^\)]*cel_expr_python\.ext\.[^\)]*\),?\r?\n?', ''); Set-Content setup.py $s"

REM Remove test files.
del /q cel_expr_python\*_test.py 2>nul

%PYTHON% -m pip install -vvv .

