# Contributing

Thanks for your interest in this project. It's a personal/portfolio-scale
RISC-V core, so the process is intentionally lightweight.

## Before you start

For anything beyond a small fix, please open an issue first to discuss the
change — especially for anything touching `rtl/cpu_core.v`'s pipeline
control logic or the `QDOT4`/`QDOT8` encoding, since both have subtle,
already-debugged timing behavior documented in the header comments (see
`rtl/cpu_core.v` and `rtl/qdot4.v`). Read those comments before changing the
hazard/forwarding logic; two real bugs in that area are recorded there,
along with the specific regression test that caught each one.

## Development setup

You need [Icarus Verilog](https://steveicarus.github.io/iverilog/) to run
the test suite. A RISC-V bare-metal GCC and Python 3 are only needed if
you're changing `sw/kernel.c` and need to regenerate `sw/kernel.hex` /
`sw/kernel_data.hex`. Vivado is only needed if you're changing the FPGA
synthesis flow. See the README's
[Getting started](README.md#getting-started) section for exact versions
this was last verified against.

## Making a change

1. Fork and branch from `main`.
2. Keep changes focused — one logical change per pull request.
3. Match the existing style:
   - Verilog: explicit port directions and widths, `localparam` for
     opcodes/encodings (not magic numbers), and a comment explaining *why*
     for anything non-obvious (timing dependencies, hazard interactions,
     hardware workarounds) — not restating *what* the code does.
   - Assembly (`.s`) test programs: a header comment stating what hazard or
     behavior the test is exercising, and inline comments showing expected
     register/memory values.
   - Everything else: match the surrounding file.
4. **Run the full test suite before opening a PR**: `./scripts/run_tests.sh`
   (the same script [CI](.github/workflows/ci.yml) runs on every push and
   PR) must exit 0. It compiles and runs every testbench in `tests/`, `sw/`,
   and `fpga/` and fails if any of them prints `FAIL` or produces no `PASS`
   output. If you're adding a new instruction, hazard case, or peripheral,
   add a new self-checking testbench for it in the relevant directory
   rather than only testing manually. Note that CI does not run FPGA
   synthesis (Vivado isn't available there) — if you touch `fpga/synth.tcl`
   or `fpga/constraints.xdc`, run that flow locally yourself.
5. If your change affects behavior described in the README (ISA coverage,
   known limitations, benchmark numbers), update the README in the same PR.
   Don't restate invented numbers — if you're changing something that
   affects the benchmark, re-run `sw/tb_benchmark.v` and paste the actual
   output.

## Reporting bugs

Open an issue with: the command you ran, the expected vs. actual
`PASS`/`FAIL` output, and (if applicable) the specific instruction sequence
or `.s` test case that reproduces it. A minimal failing test case is the
most useful thing you can attach.
