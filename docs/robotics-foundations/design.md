# Current robotics libraries: native validation

Validate OpenCV 5.0.0, Eigen 5.0.1 and gpsd 3.27.5 on EmberBSD AArch64.
These are upstream stable releases checked on 2026-10-06, not the older
OpenCV/Eigen versions in the pinned pkgsrc base.

The deliverable is a reproducible source probe in `probes/robotics-foundations`.
It pins source archives and SHA256 hashes, installs into an unused private
prefix and tests installed libraries. This is not a binary package channel.
Use one selected Eigen version for both its consumer and OpenCV integration.
No project-owned Python; gpsd's upstream SCons requires Python at build time.

OpenCV's CPU profile includes core, imgproc, imgcodecs, features, geometry and
calib and their required modules. Test image round trips, segmentation,
features, geometric recovery, invalid images and Eigen interoperation.
Eigen tests solve residuals, sparse systems, SVD and rigid transforms.
A C gpsd test drives a temporary pseudo-terminal with synthetic NMEA and
checks libgps observations: position, invalid checksum rejection, loss of fix
and recovery. All waits are bounded and only its own child is stopped.

Keep source, builds, binaries and logs outside Git. Preserve licenses and
upstream identities. Record actual results and unsupported scope separately.
No physical camera/GNSS, GPU, SMP or hard real-time support is established.
The shared kernel VM is excluded. Remove the temporary dedicated VM and
unneeded downloaded/build data after saving compact results and install files.
