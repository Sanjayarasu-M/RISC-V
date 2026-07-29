# Security Policy

This repository is RTL, firmware, and FPGA synthesis scripts for a personal
RISC-V core — it does not run as a network service and does not process
untrusted external input. "Security" here mostly means correctness issues
that could cause silent wrong-answer behavior (a bad forwarding path, an
incorrect hazard stall, a UART framing bug) rather than a traditional
vulnerability class.

## Supported Versions

Only the latest commit on `main` is supported; there are no maintained
release branches.

## Reporting an Issue

For a functional bug (wrong results, a hazard not handled, a testbench that
should fail but doesn't), just open a regular GitHub issue with a minimal
reproducing test case — see [CONTRIBUTING.md](CONTRIBUTING.md#reporting-bugs).

If you find something with real security implications (e.g. a flaw in
`fpga/synth.tcl` or the constraints flow that could produce a
misconfigured/unsafe bitstream if someone carries this to real hardware),
please use GitHub's [private vulnerability reporting](../../security/advisories/new)
for this repository instead of a public issue, so it can be assessed before
being disclosed.
