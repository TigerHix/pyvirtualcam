$ErrorActionPreference = 'Stop'

function exec {
    [CmdletBinding()]
    param([Parameter(Position=0,Mandatory=1)][scriptblock]$cmd)
    Write-Host "$cmd"
    # https://stackoverflow.com/q/2095088
    $ErrorActionPreference = 'Continue'
    & $cmd
    $ErrorActionPreference = 'Stop'
    if ($lastexitcode -ne 0) {
        throw ("ERROR exit code $lastexitcode")
    }
}

function Initialize-Python {
    if ($env:USE_CONDA -eq 1) {
        $env:CONDA_ROOT = $pwd.Path + "\external\miniconda_$env:PYTHON_ARCH"
        & .\.github\scripts\install-miniconda.ps1
        & $env:CONDA_ROOT\shell\condabin\conda-hook.ps1
        exec { conda update --yes -n base -c defaults conda }
    }
    # Check Python version/arch
    exec { python -c "import platform; assert platform.python_version().startswith('$env:PYTHON_VERSION')" }
    exec { python -c "import struct; assert struct.calcsize('P') * 8 == $env:PYTHON_ARCH" }
}

function Create-VEnv {
    [CmdletBinding()]
    param([Parameter(Position=0,Mandatory=1)][string]$name)
    if ($env:USE_CONDA -eq 1) {
        exec { conda create --yes --name $name -c defaults --strict-channel-priority python=$env:PYTHON_VERSION --force }
    } else {
        exec { python -m venv env\$name }
    }
}

function Enter-VEnv {
    [CmdletBinding()]
    param([Parameter(Position=0,Mandatory=1)][string]$name)
    if ($env:USE_CONDA -eq 1) {
        conda activate $name
    } else {
        & .\env\$name\scripts\activate
    }
}

function Create-And-Enter-VEnv {
    [CmdletBinding()]
    param([Parameter(Position=0,Mandatory=1)][string]$name)
    Create-VEnv $name
    Enter-VEnv $name
}

function Exit-VEnv {
    if ($env:USE_CONDA -eq 1) {
        conda deactivate
    } else {
        deactivate
    }
}

if (!$env:PYTHON_VERSION) {
    throw "PYTHON_VERSION env var missing, must be x.y"
}
if ($env:PYTHON_ARCH -ne '32' -and $env:PYTHON_ARCH -ne '64') {
    throw "PYTHON_ARCH env var must be 32 or 64"
}

$PYVER = ($env:PYTHON_VERSION).Replace('.', '')

Initialize-Python

Get-ChildItem env:


# Install and import in an empty environment.
# This is to catch DLL issues that may be hidden with dependencies.
Create-And-Enter-VEnv import-test
python -m pip uninstall -y pyvirtualcam
ls dist\*cp${PYVER}*win*.whl | % { exec { python -m pip install $_ } }

# Avoid using in-source package during tests
mkdir -f tmp_for_test | out-null
pushd tmp_for_test
exec { python -c "import pyvirtualcam" }
popd

Exit-VEnv

# Unit tests
# Run test suite with all required and optional dependencies
Create-And-Enter-VEnv testsuite
python -m pip uninstall -y pyvirtualcam
ls dist\*cp${PYVER}*win*.whl | % { exec { python -m pip install $_ } }
exec { python -m pip install -r dev-requirements.txt }

# Install test helper package
Push-Location test/win-dshow-capture
exec { python -m pip install wheel }
exec { python -u setup.py bdist_wheel }
python -m pip uninstall -y pyvirtualcam_win_dshow_capture
ls dist\*cp${PYVER}*win*.whl | % { exec { python -m pip install $_ } }
Pop-Location

# Avoid using in-source package during tests
mkdir -f tmp_for_test | out-null
pushd tmp_for_test
exec { pytest --verbosity=3 -s ../test }
popd

Exit-VEnv
