// kernel.c -- quantized int8 dot-product kernel, computed three ways:
//   1) scalar_dot16   -- plain RV32I loop (Phase 3 baseline)
//   2) qdot4_dot16    -- accelerated with the QDOT4 custom instruction,
//                        issued via the .insn directive exactly as it
//                        would be from any C project without needing a
//                        patched assembler:
//                          asm volatile (".insn r 0x0B, 0, 0, %0, %1, %2"
//                                        : "+r"(acc) : "r"(a), "r"(b));
//   3) qdot8_dot16    -- Phase 5: QDOT8 (funct3=1, same opcode), widened to
//                        8 int8 lanes via the register-pair trick: rs1/rs2
//                        only encode 2 of the 4 source registers the
//                        hardware actually reads (see cpu_core.v) -- the
//                        other two lanes come from whatever physical
//                        register is one above rs1/rs2. A generic "r"
//                        constraint can't express "the very next register",
//                        so qdot8_step pins its four source operands to
//                        specific adjacent hardware registers (a0/a1 and
//                        a2/a3) with GCC's local register-variable
//                        extension, guaranteeing the pairing the hardware
//                        assumes regardless of what the register allocator
//                        would otherwise pick.
//
// All three run on the same input vectors and cross-check their results,
// which are written to fixed memory-mapped addresses (_result_ok/_result_val*,
// defined in link.ld) for the testbench to verify.
//
// Phase 3: checkpoint stores (_ckpt_*) bracket each variant's call so the
// testbench can measure elapsed cycles for each one -- this core has no
// CSR/rdcycle support, so cycle counting happens at the testbench level by
// watching for these specific memory-mapped writes.
#include <stdint.h>

#define N 64           // signed int8 elements per vector
#define NGROUPS4 (N/4) // QDOT4 processes 4 lanes at a time
#define NGROUPS8 (N/8) // QDOT8 processes 8 lanes at a time

extern volatile uint32_t _result_ok;
extern volatile uint32_t _result_val;
extern volatile uint32_t _result_val_qdot8;
extern volatile uint32_t _ckpt_scalar_start;
extern volatile uint32_t _ckpt_scalar_end;
extern volatile uint32_t _ckpt_qdot4_start;
extern volatile uint32_t _ckpt_qdot4_end;
extern volatile uint32_t _ckpt_qdot8_start;
extern volatile uint32_t _ckpt_qdot8_end;

static inline int32_t qdot4(int32_t acc, uint32_t a, uint32_t b) {
    int32_t result = acc;
    asm volatile (".insn r 0x0B, 0, 0, %0, %1, %2" : "+r"(result) : "r"(a), "r"(b));
    return result;
}

// rs1 = a_lo's register, rs1+1 = a_hi's register (a0/a1); rs2 = b_lo's
// register, rs2+1 = b_hi's register (a2/a3). rd is pinned off to the side
// (a4) so it can't collide with either pair.
static inline int32_t qdot8_step(int32_t acc, uint32_t a_lo, uint32_t a_hi, uint32_t b_lo, uint32_t b_hi) {
    register int32_t  rd_   asm("a4") = acc;
    register uint32_t rs1_  asm("a0") = a_lo;
    register uint32_t rs1h_ asm("a1") = a_hi;
    register uint32_t rs2_  asm("a2") = b_lo;
    register uint32_t rs2h_ asm("a3") = b_hi;
    asm volatile (".insn r 0x0B, 1, 0, %0, %1, %2"
                  : "+r"(rd_)
                  : "r"(rs1_), "r"(rs2_), "r"(rs1h_), "r"(rs2h_));
    return rd_;
}

int32_t scalar_dot16(const int8_t *a, const int8_t *b, int n) {
    int32_t acc = 0;
    for (int i = 0; i < n; i++) {
        acc += (int32_t)a[i] * (int32_t)b[i];
    }
    return acc;
}

int32_t qdot4_dot16(const uint32_t *a_packed, const uint32_t *b_packed, int ngroups) {
    int32_t acc = 0;
    for (int i = 0; i < ngroups; i++) {
        acc = qdot4(acc, a_packed[i], b_packed[i]);
    }
    return acc;
}

// a_packed/b_packed are viewed 2 words at a time: word[2*i] supplies lanes
// 0-3, word[2*i+1] supplies lanes 4-7 -- the same memory layout as
// qdot4_dot16, just consumed in pairs instead of singly.
int32_t qdot8_dot16(const uint32_t *a_packed, const uint32_t *b_packed, int ngroups8) {
    int32_t acc = 0;
    for (int i = 0; i < ngroups8; i++) {
        acc = qdot8_step(acc, a_packed[2*i], a_packed[2*i+1], b_packed[2*i], b_packed[2*i+1]);
    }
    return acc;
}

// int8 values, little-endian byte order == QDOT4 lane order (lane0 = byte0).
// Pattern 1..16 repeated 4x so both loops process the same 64 elements;
// expected dot product = 4 * sum(1..16) = 4 * 136 = 544.
static const int8_t a_bytes[N] = {
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
};
static const int8_t b_bytes[N] = {
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
};

int main(void) {
    _ckpt_scalar_start = 1;
    int32_t r_scalar = scalar_dot16(a_bytes, b_bytes, N);
    _ckpt_scalar_end = 1;

    _ckpt_qdot4_start = 1;
    int32_t r_qdot4 = qdot4_dot16((const uint32_t *)a_bytes, (const uint32_t *)b_bytes, NGROUPS4);
    _ckpt_qdot4_end = 1;

    _ckpt_qdot8_start = 1;
    int32_t r_qdot8 = qdot8_dot16((const uint32_t *)a_bytes, (const uint32_t *)b_bytes, NGROUPS8);
    _ckpt_qdot8_end = 1;

    _result_val       = (uint32_t)r_qdot4;
    _result_val_qdot8 = (uint32_t)r_qdot8;
    _result_ok        = (r_scalar == r_qdot4 && r_scalar == r_qdot8) ? 1u : 0u;

    while (1) { }
    return 0;
}
