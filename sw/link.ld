/* link.ld -- linker script for the QDOT4 RISC-V core's Harvard memories.
 *
 * imem and dmem are two SEPARATE physical arrays in top.v, each addressed
 * from 0 -- there is no datapath from the core to imem except instruction
 * fetch, so anything the C code loads/stores with lw/sw/lb/sb (including
 * .rodata!) must live in DMEM, not IMEM. Only .text goes in IMEM.
 */
ENTRY(_start)

MEMORY
{
    IMEM     (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM     (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
    /* DMEM_LMA exists only so the linker has a non-overlapping address range
     * to assign LMAs from -- IMEM and DMEM are genuinely separate physical
     * memories that both happen to be addressed from 0, which ld's overlap
     * checker doesn't otherwise understand. Nothing ever loads from here;
     * we extract .rodata/.data by section name via objcopy, not by address. */
    DMEM_LMA (rwx) : ORIGIN = 0x00100000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text*)
    } > IMEM

    .rodata : {
        *(.rodata*)
    } > DMEM AT> DMEM_LMA

    .data : {
        *(.data*)
    } > DMEM AT> DMEM_LMA

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > DMEM

    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

    /* Fixed memory-mapped addresses used by the testbenches to read back
     * results -- not a real MMIO device, just an address both the C code
     * and the Verilog testbench agree on. Deliberately placed in the middle
     * of DMEM: _stack_top sits at the very end of DMEM and the stack grows
     * down from there (callee-saved register spills in a function's
     * prologue land immediately below it), while .rodata/.data grow up from
     * address 0 -- this region needs to be clear of both. */
    _result_ok        = 0x0800;
    _result_val       = 0x0804;
    _cycle_count      = 0x0808;
    _result_val_qdot8 = 0x080C;

    /* Phase 3 benchmark checkpoints: bracket each kernel variant so the
     * testbench can measure elapsed cycles by watching for these writes. */
    _ckpt_scalar_start = 0x0810;
    _ckpt_scalar_end   = 0x0814;
    _ckpt_qdot4_start  = 0x0818;
    _ckpt_qdot4_end    = 0x081C;
    /* Phase 5: QDOT8 checkpoints. */
    _ckpt_qdot8_start  = 0x0820;
    _ckpt_qdot8_end    = 0x0824;

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
