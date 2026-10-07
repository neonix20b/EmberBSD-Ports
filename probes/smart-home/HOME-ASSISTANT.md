# Home Assistant Core 2026.9.4 source gate

The native port is not accepted yet. Use the original source archive from
[sources/home-assistant.tsv](sources/home-assistant.tsv) and the common
Python 3.14.8 candidate. Do not relax the upstream minimum Python 3.14.2 or
install an old interpreter for this application.

## Dependency preparation

`pyproject.toml` alone does not close this application's default runtime.
Bootstrap loads entity platforms even when they have no explicit YAML entry.
The upstream-generated `requirements.txt` and component manifests also matter.
The source inventory includes the UI/API, MQTT, automations, recorder/history,
OTBR, and 45 upstream entity platforms with their declared dependencies.
Camera's stream imports and analytics' Supervisor API client are included;
this does not install or activate a Linux Supervisor.

```sh
node home-assistant-profile.mjs /absolute/prepared-ha/source /absolute/new-profile
cd /absolute/prepared-ha/source
uv pip compile --no-config --no-managed-python --no-python-downloads \
    --python /absolute/common-python/bin/python3.14 --universal \
    --generate-hashes --no-header -o /absolute/new-profile/requirements.lock \
    requirements.txt /absolute/new-profile/profile.in
```

Node is only an inventory tool here, already selected for Zigbee2MQTT.
The profile generator neither executes Home Assistant nor changes its sources.
The generated runtime lock and resolver log belong in the private work area
until the native dependency selection is validated. `requirements.txt`
supplies upstream `homeassistant/package_constraints.txt`; preserve those
constraints and package hashes. Do not install the entire integrations catalog
or silently ignore missing packages.

On 2026-10-07 the inventory found 83 components and 26 explicit integration
requirements. A host universal resolution with the upstream constraints
selected 158 packages; all installed in a temporary macOS/arm64 environment
using the existing Python 3.14.8. This does not prove NetBSD wheel, source,
Rust or native extension support. The resolver was the existing host uv
0.12.23; the application retained its own upstream uv 0.12.5 requirement
inside that temporary validation environment. This is not a permanent
parallel runtime policy for EmberBSD.

## Runtime boundary

The real host application served frontend HTML and onboarding API after the
dependency closure was corrected. No component ERROR remained in the bounded
second startup check. It nevertheless crashed with SIGSEGV during Python
finalization after SIGTERM, so the overall host check failed. Individual
imports of the first examined native modules exited normally; the cause is
not established. Do not hide this failure with `os._exit`, disabled cleanup,
an older interpreter or a claim of successful service operation.

A fresh diagnostic run with `PYTHONMALLOC=debug` reproduces the crash as
SIGBUS while finalizing modules, with a `0xdddddddddddddddd` target address.
Python's [debug allocator](https://docs.python.org/3/c-api/memory.html#debug-hooks-on-the-python-memory-allocators)
fills freed memory with `0xDD`; this supports a use-after-free hypothesis,
but does not identify the responsible package. A separate fresh configuration
still crashes when upstream pure-Python runtime modes for aiohttp, propcache,
multidict, yarl and SQLAlchemy are selected together. These are diagnostic
comparisons, not an accepted fallback configuration or a NetBSD result.

Native acceptance still requires the common interpreter, all required native
extensions and Rust dependencies, an explicit reviewed NetBSD OS adaptation,
real onboarding, MQTT automation, database persistence and clean restart.
The upstream `validate_os()` currently allows Linux and macOS only; bypassing
it alone is not a completed port. Bluetooth, radio firmware operations,
Supervisor, containers and physical devices are separate capabilities.
