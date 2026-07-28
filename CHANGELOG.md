# Changelog

This project did not keep a formal changelog prior to its first public
release; the entry below is reconstructed from development-phase markers
left in the source comments (`sw/kernel.c`, `sw/link.ld`, `fpga/*`) rather
than from a commit history, since the repository was not under version
control before this release. Dates are not claimed for individual phases —
only for the release itself.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-07-28

Initial public release. Development had proceeded through the following
internal milestones, all present in this snapshot:

### Added

- **Single-cycle RV32I core** (`rtl/cpu_core_singlecycle.v`) with a custom
  `QDOT4` instruction — the original implementation, kept for reference.
- **5-stage pipelined RV32I core** (`rtl/cpu_core.v`): full EX/MEM and
  MEM/WB forwarding, load-use hazard stalling, predict-not-taken branch
  resolution in EX, JAL resolution in ID. `QDOT4` re-integrated into the
  pipeline with the same hazard/forwarding treatment as a load.
- **Bare-metal firmware and benchmarking** (`sw/`): `crt0.S` startup,
  linker script, and a kernel comparing a plain RV32I dot-product loop
  against the `QDOT4`-accelerated version, cross-checked for correctness.
  A cycle-accurate testbench (`sw/tb_benchmark.v`) measures both via
  memory-mapped checkpoint writes (the core has no CSR/cycle-counter
  support).
- **FPGA deployment target** (`fpga/`): `fpga_top.v` (core + BRAM + UART
  TX), a UART transmitter/receiver pair, a Vivado batch-mode synthesis and
  timing-closure script targeting a Zynq UltraScale+ part, and an
  end-to-end simulation test that decodes the UART bitstream to confirm
  correct output.
- **`QDOT8` extension**: widens the dot-product instruction to 8 signed
  int8 lanes via a register-pair operand trick (`rs1+1`/`rs2+1`), sharing
  the custom-0 opcode and pipeline treatment with `QDOT4`. Added dedicated
  hazard regression tests, including the `rs1_hi`/`rs2_hi` forwarding and
  stall paths.

### Fixed (during pipeline development, prior to this release)

- A BRAM-timing bug where a stall could silently drop the next real fetched
  instruction because the IF-stage buffering register was not held during
  the stall (caught by the back-to-back `QDOT4` hazard test).
- A related bug where a control-flow redirect (branch/JALR) could still
  consume a second, already-in-flight wrong-path instruction one cycle
  after the primary squash, because the redirect was only asserted for one
  cycle (caught by the branch hazard test against `sw/kernel.hex`).

### Repository organization (this release)

- Reorganized core RTL modules into `rtl/`.
- Removed all build artifacts and tool-generated files from version control
  (Vivado synthesis outputs and logs, compiled Icarus Verilog binaries,
  GCC object/ELF/map files) — see `.gitignore`. Pre-built simulation memory
  images (`*.hex`) were kept since they are required inputs for the
  testbenches to run without a full toolchain installed.
- Added `README.md`, `LICENSE` (MIT), `CONTRIBUTING.md`, and this changelog.
