# OpenThread Border Router v2026.10.0 candidate

The source preparation pins the OTBR release and its exact recursive
OpenThread, cpp-httplib, MbedTLS and MbedTLS-framework revisions in
[sources/otbr.tsv](sources/otbr.tsv). MbedTLS is the upstream-selected 3.6.5
LTS source. Existing copyright and license files remain in every subtree.

```sh
sh configure-otbr.sh /absolute/new-otbr-work \
    /absolute/shared-mqtt-dependencies /absolute/archive-cache
```

Run on NetBSD/EmberBSD with the common GCC 16.2 candidate, CMake, Ninja,
pkg-config, readline and Curses development files. The second argument is
the shared candidate prefix containing cJSON 1.7.19 from the
[Mosquitto recipe](../mosquitto/README.md). The version check rejects a
missing/different shared cJSON rather than falling back to OTBR's old copy.

## Profile

The first profile uses RCP mode and the REST interface consumed by Home
Assistant's OTBR integration. It enables border routing, backbone routing,
TREL and NAT64 with OpenThread mDNS. The optional D-Bus API and legacy web
interface are disabled. D-Bus was the sole enabled path requiring Protobuf;
the REST client does not need that additional API dependency.

[`otbr-netbsd-curses.patch`](patches/otbr-netbsd-curses.patch) selects NetBSD's
standard Curses libraries for readline. Upstream otherwise looks specifically
for a library named `ncurses`, despite the base system providing Curses.
No readline functionality is removed and no additional curses variant is
installed for this application. The local patch is not submitted upstream.

[`otbr-netbsd-infra.patch`](patches/otbr-netbsd-infra.patch) replaces the
unavailable Apple `IPV6_BOUND_IF` with NetBSD's RFC 3542 `IPV6_PKTINFO`.
One helper serves socket creation and interface rebinding. The existing
receive path still rejects a different incoming interface, a hop limit other
than 255 or a non-link-local source; it is not bypassed by this adaptation.

The pinned OpenThread POSIX implementation includes NetBSD TUN and routing
socket code used by RCP. OTBR's separate Unix NCP netif implementation has
unfinished paths; their existence must not be confused with RCP support or
accepted as successful network operations.

## Verified boundary

On 2026-10-07, NetBSD11/AArch64 in UTM configured successfully using GCC 16.2,
CMake 4.3.3 and shared cJSON 1.7.19. CMake's compiler checks passed and
`ninja -n` produced 563 build actions. A clean repeat of the public recipe
applied both patches without fuzz and passed configuration; its complete
source/configuration tree used 113540 KiB. Separate bounded native checks compiled
the complete `infra_if.cpp` object. `netif.cpp` still calls the removed
`otIp6SetMulticastPromiscuousEnabled` API in its NetBSD multicast path;
repairing its stale instance variable alone does not resolve this.
No agent binary, service, network interface or route
was installed or started.

The socket regression extracts the actual upstream constructor and NetBSD
binding helper, compiles them and exercises real kernel socket options.
It passes creation, sticky interface selection, invalid-index rejection,
rebinding, received packet-info/hop-limit options, both outgoing hop limits,
ICMPv6 checksum offset, ND filter, close and invalid-interface rejection.
The original constructor fails to compile on `IPV6_BOUND_IF`. The wrapper
only supplies the platform socket-opening and fatal-error plumbing; it does
not emulate `setsockopt` or `getsockopt`.

```sh
sh test-otbr-infra.sh /absolute/prepared-otbr/source/third_party/openthread/repo \
    /absolute/new-socket-check
# As root, only for a raw ICMPv6 socket; no packets are transmitted:
/absolute/new-socket-check/test-otbr-infra
```

This socket contract uses `lo0` and changes no interface, route or firewall.
It does not test actual RA reception, forwarding or Thread communication.

NetBSD multicast membership synchronization needs a real current implementation.
The old path disables MLD monitoring and assumes a removed promiscuous API.
Neither disabling multicast nor inventing a successful API stub is accepted.

Upstream generation currently uses the VM's Python 3.13.14; this is an existing
build bootstrap dependency, not a second OTBR runtime. The common Python 3.14.8
migration remains owned by the shared build-tools profile.

Ingress firewall integration is pending. The configure probe disables the
Linux iptables/nftables and Apple-only PF paths instead of claiming that
they work on NetBSD. This is not an accepted production border-router
configuration. Before routing acceptance, implement and verify the appropriate
NetBSD ingress controls, build the native agent, then test a real RCP or an
explicit upstream simulation, IPv6 reachability, discovery and restart.
