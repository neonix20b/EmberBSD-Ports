#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed Python and C/C++ consumer acceptance.
set -eu
[ "$#" = 1 ] || { echo "Usage: $0 NEW_OUTPUT" >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || exit 2
case "$1" in /*) ;; *) exit 2;; esac
case "$1" in *[!a-zA-Z0-9_./-]*) exit 2;; esac
[ ! -e "$1" ] && [ ! -L "$1" ] || exit 2
export PATH=/usr/pkg/gcc16/bin:/usr/pkg/bin:/usr/pkg/sbin:/bin:/usr/bin:/sbin:/usr/sbin
unset LD_LIBRARY_PATH LD_PRELOAD LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH
unset PYTHONHOME PYTHONPATH PYTHONSTARTUP
pkg_info -e python314-3.14.8
pkg_info -e 'gcc16>=16.2.0nb1'
mkdir -p "$1"
cd "$1"
uname -a > platform.txt
pkg_admin check python314 > package-integrity.txt
python3.14 -VV > version.txt
python3.14 -m sysconfig > sysconfig.txt
# CONFIG_ARGS retains build provenance; compiler/linker inputs must be usable
# on the installed target. The C/C++ consumers below exercise their output.
grep -E '^[[:space:]]*(CC|CXX|CFLAGS|CPPFLAGS|LDFLAGS|LDSHARED|BLDSHARED) = ' \
    sysconfig.txt > compiler-settings.txt
if grep -E '/private/|/opt/homebrew/|apple-darwin' compiler-settings.txt; then
    echo 'Installed compiler settings contain build-host paths' >&2; exit 1
fi
python3.14-config --includes > includes.txt
python3.14-config --embed --ldflags > embed-flags.txt
pkg-config --cflags --libs python-3.14-embed > pkgconfig-flags.txt
cat > extension.c <<'C'
#define PY_SSIZE_T_CLEAN
#include <Python.h>
static PyObject *answer(PyObject *self, PyObject *args)
{
    (void)self;
    (void)args;
    return PyLong_FromLong(42);
}
static PyMethodDef methods[] = {
    {"answer", answer, METH_NOARGS, "Return the native extension result."},
    {NULL, NULL, 0, NULL}
};
static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "ember_probe", NULL, -1, methods,
    NULL, NULL, NULL, NULL
};
PyMODINIT_FUNC PyInit_ember_probe(void) { return PyModule_Create(&module); }
C
cat > embed.cc <<'CXX'
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdexcept>
#include <cstdio>
#include <fstream>
#include <sstream>
int main()
{
    Py_Initialize();
    PyObject *directory = PyUnicode_FromString(".");
    if (!directory || PyList_Insert(PySys_GetObject("path"), 0, directory) < 0)
        return 1;
    Py_DECREF(directory);
    PyObject *module = PyImport_ImportModule("ember_probe");
    if (!module) { PyErr_Print(); return 1; }
    PyObject *value = PyObject_CallMethod(module, "answer", NULL);
    if (!value || PyLong_AsLong(value) != 42 || PyErr_Occurred()) {
        PyErr_Print(); return 1;
    }
    Py_DECREF(value);
    Py_DECREF(module);
    const char *modules[] = {"_ctypes", "_ssl", "_hashlib", "_uuid",
        "readline", "_sqlite3", "_decimal", "pyexpat", "_bz2", "_lzma",
        "zlib", "compression.zstd", "_pyrepl.terminfo"};
    for (const char *name : modules) {
        module = PyImport_ImportModule(name);
        if (!module) { std::fprintf(stderr, "%s: ", name); PyErr_Print(); return 1; }
        Py_DECREF(module);
    }
    std::ifstream file("/usr/pkg/lib/python3.14/build-details.json");
    std::stringstream contents;
    contents << file.rdbuf();
    PyObject *json = PyImport_ImportModule("json");
    PyObject *loader = PyImport_ImportModule("importlib.machinery");
    if (!json || !loader || !file.good()) return 1;
    PyObject *details = PyObject_CallMethod(json, "loads", "s", contents.str().c_str());
    PyObject *actual = PyObject_GetAttrString(loader, "EXTENSION_SUFFIXES");
    if (!details || !actual) { PyErr_Print(); return 1; }
    PyObject *suffixes = PyDict_GetItemString(details, "suffixes");
    PyObject *declared = suffixes ? PyDict_GetItemString(suffixes, "extensions") : NULL;
    if (!declared || PyObject_RichCompareBool(declared, actual, Py_EQ) != 1) return 1;
    Py_DECREF(actual);
    PyObject *config = PyImport_ImportModule("sysconfig");
    actual = config ? PyObject_CallMethod(config, "get_platform", NULL) : NULL;
    declared = PyDict_GetItemString(details, "platform");
    if (!actual || !declared || PyObject_RichCompareBool(declared, actual, Py_EQ) != 1)
        return 1;
    Py_DECREF(actual);
    Py_DECREF(config);
    PyObject *language = PyDict_GetItemString(details, "language");
    PyObject *version = language ? PyDict_GetItemString(language, "version_info") : NULL;
    PyObject *implementation = PyDict_GetItemString(details, "implementation");
    PyObject *implementation_version = implementation ?
        PyDict_GetItemString(implementation, "version") : NULL;
    if (!version || !implementation_version ||
        PyObject_RichCompareBool(version, implementation_version, Py_EQ) != 1) return 1;
    const char *fields[] = {"major", "minor", "micro", "releaselevel", "serial"};
    for (const char *field : fields) {
        actual = PyObject_GetAttrString(PySys_GetObject("version_info"), field);
        declared = PyDict_GetItemString(version, field);
        if (!actual || !declared || PyObject_RichCompareBool(declared, actual, Py_EQ) != 1)
            return 1;
        Py_DECREF(actual);
    }
    PyObject *abi = PyDict_GetItemString(details, "abi");
    declared = abi ? PyDict_GetItemString(abi, "flags") : NULL;
    actual = PySequence_List(PySys_GetObject("abiflags"));
    if (!actual || !declared || PyObject_RichCompareBool(declared, actual, Py_EQ) != 1)
        return 1;
    Py_DECREF(actual);
    PyObject *libraries = PyDict_GetItemString(details, "libpython");
    if (!libraries) return 1;
    for (const char *kind : {"static", "dynamic"}) {
        declared = PyDict_GetItemString(libraries, kind);
        const char *path = declared ? PyUnicode_AsUTF8(declared) : NULL;
        if (!path || !std::ifstream(path).good()) return 1;
    }
    Py_DECREF(details);
    Py_DECREF(loader);
    Py_DECREF(json);
    try { throw std::runtime_error("selected C++ runtime"); }
    catch (const std::exception &) { }
    return Py_FinalizeEx() < 0 ? 1 : 0;
}
CXX
# Word splitting is intentional for installed configuration-tool output.
extension_suffix=$(python3.14-config --extension-suffix)
[ "$extension_suffix" = .so ]
gcc -std=c11 -Wall -Wextra -Werror -fPIC -shared \
    $(python3.14-config --includes) extension.c -o "ember_probe$extension_suffix"
g++ -std=c++20 -Wall -Wextra -Werror embed.cc \
    $(python3.14-config --includes --embed --ldflags) \
    -Wl,-R/usr/pkg/lib -Wl,-R/usr/pkg/gcc16/lib -o embed-config
g++ -std=c++20 -Wall -Wextra -Werror embed.cc \
    $(pkg-config --cflags --libs python-3.14-embed) \
    -Wl,-R/usr/pkg/lib -Wl,-R/usr/pkg/gcc16/lib -o embed-pkgconfig
for consumer in embed-config embed-pkgconfig; do
    "./$consumer"
    ldd "./$consumer" | sed 's,/\./,/,g' > "$consumer.linkage"
    grep -q '/usr/pkg/lib/libpython3.14.so' "$consumer.linkage"
    grep -q '/usr/pkg/gcc16/lib/libstdc++.so.7' "$consumer.linkage"
    if grep -E 'not found|libstdc\+\+\.so\.9' "$consumer.linkage"; then
        echo 'Consumer did not resolve the selected runtime' >&2; exit 1
    fi
done
mkdir tagged stable
cp ember_probe.so tagged/ember_probe.cpython-314.so
cp ember_probe.so stable/ember_probe.abi3.so
(cd tagged && ../embed-config)
(cd stable && ../embed-config)
echo 'PASS: installed configuration tools, native extension, embedding and selected runtime'
# Upstream suite with the documented NetBSD packaging assertion in test_sysconfig.
# No external network or optional resources.
python3.14 -m test -j2 --timeout=300 \
    test_ctypes test_ssl test_hashlib test_uuid test_readline test_sqlite3 \
    test_decimal test_pyexpat test_bz2 test_lzma test_zlib test_zstd \
    test_subprocess test_threading test_importlib test_sysconfig test_venv \
    test_faulthandler test_socket test_pty test_repl
echo 'PASS: installed upstream Python consumer tests'
