#!/usr/bin/env python
import os
import sys

from methods import print_error

import platform
if 'arch' not in ARGUMENTS:
    machine = platform.machine()
    if machine in ('arm64', 'aarch64'):
        ARGUMENTS['arch'] = 'arm64'
    elif machine == 'x86_64':
        ARGUMENTS['arch'] = 'x86_64'


libname = "dicomviewer"
projectdir = "demo"

localEnv = Environment(tools=["default"], PLATFORM="")

# Build profiles can be used to decrease compile times.
# You can either specify "disabled_classes", OR
# explicitly specify "enabled_classes" which disables all other classes.
# Modify the example file as needed and uncomment the line below or
# manually specify the build_profile parameter when running SCons.

# localEnv["build_profile"] = "build_profile.json"

customs = ["custom.py"]
customs = [os.path.abspath(path) for path in customs]

opts = Variables(customs, ARGUMENTS)
opts.Update(localEnv)

Help(opts.GenerateHelpText(localEnv))

env = localEnv.Clone()

if not (os.path.isdir("godot-cpp") and os.listdir("godot-cpp")):
    print_error("""godot-cpp is not available within this folder, as Git submodules haven't been initialized.
Run the following command to download godot-cpp:

    git submodule update --init --recursive""")
    sys.exit(1)

env = SConscript("godot-cpp/SConstruct", {"env": env, "customs": customs})

# Optional DCMTK support:
use_dcmtk = ARGUMENTS.get('use_dcmtk', '0').lower() in ('1', 'yes', 'true')
if use_dcmtk:
    env.Append(CPPDEFINES=['USE_DCMTK'])
    # ensure exceptions are enabled for DCMTK (DCMTK uses C++ exceptions)
    env.Append(CCFLAGS=['-fexceptions'])
    env.Append(CXXFLAGS=['-fexceptions'])
    # Try common Homebrew and /usr include/lib locations; override with custom vars if needed:
    dcmtk_inc = ARGUMENTS.get('dcmtk_inc', '/opt/homebrew/include:/usr/local/include:/usr/include')
    dcmtk_lib = ARGUMENTS.get('dcmtk_lib', '/opt/homebrew/lib:/usr/local/lib:/usr/lib')
    # Split and append
    for p in dcmtk_inc.split(':'):
        if p and os.path.isdir(p):
            env.Append(CPPPATH=[p])
    for p in dcmtk_lib.split(':'):
        if p and os.path.isdir(p):
            env.Append(LIBPATH=[p])
    # Common DCMTK libs (may vary on your system)
    env.Append(LIBS=['dcmimgle', 'dcmdata', 'oflog', 'ofstd'])
    print("SCons: Building with DCMTK support (use_dcmtk=1). If DCMTK is in a custom location, pass dcmtk_inc and dcmtk_lib arguments.")

env.Append(CPPPATH=["src/"])
sources = Glob("src/*.cpp")

if env["target"] in ["editor", "template_debug"]:
    try:
        doc_data = env.GodotCPPDocData("src/gen/doc_data.gen.cpp", source=Glob("doc_classes/*.xml"))
        sources.append(doc_data)
    except AttributeError:
        print("Not including class reference as we're targeting a pre-4.3 baseline.")

# .dev doesn't inhibit compatibility, so we don't need to key it.
# .universal just means "compatible with all relevant arches" so we don't need to key it.
suffix = env['suffix'].replace(".dev", "").replace(".universal", "")

lib_filename = "{}{}{}{}".format(env.subst('$SHLIBPREFIX'), libname, suffix, env.subst('$SHLIBSUFFIX'))

library = env.SharedLibrary(
    "bin/{}/{}".format(env['platform'], lib_filename),
    source=sources,
)

copy = env.Install("{}/bin/{}/".format(projectdir, env["platform"]), library)

default_args = [library, copy]
Default(*default_args)