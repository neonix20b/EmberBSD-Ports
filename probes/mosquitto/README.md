# Eclipse Mosquitto on EmberBSD

Mosquitto 2.1.2 provides the MQTT broker and client library for the smart-home
ports. The selected release is the current upstream stable source release,
verified on 2026-10-07 against https://mosquitto.org/download/ and tag
`v2.1.2` (`99fa50f30e325609394c324c8ff71cfbbe95d8ab`). The pinned pkgsrc also
contains this release; this probe validates the common GCC16 runtime before
package integration rather than inventing a separate package manager.

## Build and verify

Prerequisites: native EmberBSD/NetBSD, common GCC/G++ 16.2, CMake 4, Ninja,
GNU make, curl, pkg-config, tar and base OpenSSL 3.5 LTS development files.
Run as an ordinary user with one worker and enough free build space:

```sh
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/usr/sbin:/bin:/sbin
sh probes/mosquitto/build.sh /absolute/new-work /absolute/archive-cache
sh probes/mosquitto/test.sh /absolute/new-work/install /absolute/new-test
```

Omit the cache argument to fetch the original upstream archives. All source
hashes are verified before extraction. Existing work/test directories are
rejected. `CC` and `CXX` may select another location of the common GCC16.2
pair. The probe installs into its disposable work directory; it does not
alter system packages, rc.conf, listeners or an existing broker.

The build uses cJSON 1.7.19 and the SQLite 3.53.4 source selection from
the [SQLite probe](../sqlite/README.md). These are shared dependency candidates,
not permanent per-application versions. Later consumers should use the same
accepted libraries. cJSON's original CMake 3.0 minimum needs the explicit
`CMAKE_POLICY_VERSION_MINIMUM=3.5` compatibility setting with CMake 4;
its 19 upstream tests run before installation.

TLS, threading, MQTT clients, the C++ wrapper, built-in WebSockets, bridges,
ACL/password/dynamic-security and SQLite persistence plugins are built.
The optional HTTP management API and interactive control shell are disabled;
they require additional dependencies. Documentation generation, example plugins,
LTO and the full upstream Python-based test suite are outside this probe.
No Python is used by the EmberBSD build helper or application checks.

## Verified boundary

On 2026-10-07 the source build and installed workflow passed in an
EmberBSD EMBER64 / NetBSD 11.0 AArch64 VM with GCC16.2, CMake4.3.3 and
base OpenSSL3.5.7. The broker, clients, libraries and selected plugins install
successfully. The C++ library resolves one GCC16 libstdc++.so.7.

The 12 installed cases cover MQTT3.1.1 and MQTT5 retained delivery at QoS0/1/2,
anonymous rejection, incorrect-password rejection, read-only ACL denial,
certificate-verified TLS delivery, retained-state recovery after restart,
and a second clean shutdown. ACL denial checks both MQTT5's negative PUBACK
and the absence of retained data: upstream `mosquitto_pub` can return zero
after warning about a rejected publication.

Tests use private loopback listeners, generated one-day certificates and
disposable fixture credentials. Client configuration uses a new empty XDG
directory, so saved user credentials or `--insecure` cannot alter the checks.
A native before/after regression with conflicting user defaults confirms this.
Override `MQTT_TEST_PORT`/`MQTT_TEST_TLS_PORT`
if 28883/28884 are already occupied. Only the test's own broker process is
stopped; a bind failure does not replace another service.

The pinned pkgsrc already provides the current Mosquitto recipe and rc.d
script; a duplicate recipe is unnecessary. Its original rc.d script also
passes four native lifecycle cases with this candidate: start/status,
authenticated MQTT, restart with a new process and restored retained data,
and stop/stopped status. Run as an ordinary user:

```sh
sh probes/mosquitto/test-rc-service.sh /absolute/work/install \
    /absolute/pinned-pkgsrc /absolute/new-rc-check
```

The check verifies the original script's SHA256, substitutes private package
paths, and executes the actual NetBSD rc.subr. It neither installs an rc.d
file nor edits system rc.conf. A system per-service override causes refusal;
the default test listener is 127.0.0.1:28885 (`MQTT_RC_TEST_PORT` can change it).
This verifies the service lifecycle, not package installation or boot ordering.
`test-stopped-process.sh NEW_WORK` exercises the verifier's actual PID gate:
a live owned process must fail even if a pidfile/status check says otherwise.
It also accepts an already reaped process; native and host checks pass.

These results do not yet establish the full upstream test suite, WebSockets,
dynamic-security/SQLite plugin runtime, remote clients, long-duration load,
or package installation/boot-service integration. Other smart-home projects are separate
ports; MQTT success does not establish their compatibility.

## Provenance

Mosquitto retains its EPL2.0/BSD3-Clause licensing and upstream authorship;
cJSON retains its MIT licence. SQLite is public domain; the existing SQLite
probe records its build-system provenance. See [sources.tsv](sources.tsv).
No upstream Mosquitto source change is currently required. The build and
workflow helpers are AI-assisted EmberBSD work under BSD2-Clause.
Nothing here is claimed as submitted to or accepted by upstream.
