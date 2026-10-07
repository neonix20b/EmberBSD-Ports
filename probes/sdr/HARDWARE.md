# Continue on PlutoSky 7020 AD9361 over Ethernet

The prepared stack targets the user-selected PlutoSky 7020 AD9361 board over
Ethernet. No board address, firmware revision or hardware RX result has been
recorded. A separate developer owns the next native and hardware validation.
This document is a handoff, not a claim that the board already works.

## Establish the native software baseline

Use the [common libxml2 provider](../libxml2/README.md) and then follow the
[SDR build and installed tests](README.md#build-and-test) on EmberBSD.
Both recipe directories are required. Preserve source hashes, compiler/runtime
versions, selected XML/Zstandard paths, build logs and installed ELF linkage.
The existing macOS checks do not replace this native step.

One libiio 1.0.0 runtime supplies both its new API and its official ABI 0 shim.
Keep the isolated legacy declaration header only for AD9361 and SoapyPluto;
do not replace the runtime with an older libiio installation.
The software suite must pass before attributing a failure to the radio.

## Inspect the explicitly selected endpoint

Record the board model/revision, firmware and `iiod` versions, transport,
power supply and the chosen sample format/rate. Keep private addresses and
serial numbers in local evidence. Obtain the Ethernet endpoint from its owner;
the profile does not need network discovery.

```sh
export SDR_PREFIX=/absolute/native-sdr-work/install
export XML_PREFIX=/absolute/native-xml-work/install
export SOAPY_SDR_ROOT="$SDR_PREFIX"
export SOAPY_SDR_PLUGIN_PATH="$SDR_PREFIX/lib/SoapySDR/modules0.8"
export LD_LIBRARY_PATH="$SDR_PREFIX/lib:$XML_PREFIX/lib:/usr/pkg/lib"
export SDR_URI=ip:BOARD_ADDRESS

"$SDR_PREFIX/bin/SoapySDRUtil" --info
"$SDR_PREFIX/bin/iio_info" -u "$SDR_URI"
"$SDR_PREFIX/bin/SoapySDRUtil" --probe="driver=plutosdr,uri=$SDR_URI"
```

Replace `BOARD_ADDRESS` with the supplied endpoint. Inspect command output and
exit status separately. Enumeration/probing does not establish an RX sample
stream, signal fidelity or throughput. No firmware change is prescribed.

## Qualify RX and report its limits

Start with one RX channel and an explicitly selected rate supported by the
reported firmware. Collect a bounded sample count, retain actual sample and
byte counts, elapsed time, format conversion, stream errors and overflow data.
Compare a known received signal with an independent expected frequency/amplitude
where a suitable signal source is available. Test stop/restart and disconnect
recovery before extending the duration or rate. Do not enable a TX stream as
part of this RX validation.

The current SoapyPluto plugin ignores per-call `readStream(timeoutUs)`.
Its untimed lock and backend refill also prevent claiming a deadline merely
by setting an IIO context timeout. Use an external process deadline for initial
bounded experiments; application-level deadlines and cancellation need their
own implementation and tests. See [the audited paths](PROVENANCE.md).

Upstream `SoapySDRUtil --rate` is an interactive diagnostic, not the acceptance
test: in the pinned 0.8.1 source it returns failure even after its normal loop
ends. Do not turn that status into an unconditional pass or use printed rate
alone as proof of successful capture.

Publish the reproducible RX consumer in EmberBSD-Examples, portability changes
here, and update the public overview only with the verified native/board scope.
USB, RF transmission, calibration, sustained operation and real-time behavior
remain separate validation boundaries.
