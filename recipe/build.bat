copy release\pyproject.toml .
copy release\setup.py .

REM Substitute $VERSION in pyproject.toml with the value of PKG_VERSION.
powershell -NoProfile -Command "(Get-Content pyproject.toml) -replace '\$VERSION', $env:PKG_VERSION | Set-Content pyproject.toml"

REM Remove cel_expr_python.ext.* BazelExtension blocks from setup.py.
powershell -NoProfile -Command "$s = Get-Content setup.py -Raw; $s = [regex]::Replace($s, '(?ms)^[^\r\n]*BazelExtension\([^\)]*cel_expr_python\.ext\.[^\)]*\),?\r?\n?', ''); Set-Content setup.py $s"

REM Remove test files.
del /q cel_expr_python\*_test.py 2>nul

%PYTHON% -m pip install -vvv .

