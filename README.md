# WarpForge

## An Educational SIMT GPU Compute Core Implemented in Verilog RTL

![Language](https://img.shields.io/badge/RTL-Verilog-blue)
![Toolchain](https://img.shields.io/badge/Verified-Vivado-green)
![Status](https://img.shields.io/badge/Project-Educational-orange)

WarpForge is a simplified **SIMT (Single Instruction, Multiple Thread) GPU compute core** written in synthesizable Verilog RTL. It implements the fundamental execution mechanisms used inside modern GPUs—warp scheduling, vector execution across SIMD lanes, interleaved multithreaded latency hiding, register dependency tracking via scoreboard, and a custom instruction set—while keeping the design small enough to study directly at RTL level.

The project is designed as an **educational compute unit**, not a full GPU. It represents one simplified GPU execution block: conceptually similar to a single Streaming Multiprocessor (SM) or Compute Unit (CU), stripped down to the essential architectural mechanisms that make GPU execution distinct from scalar CPU pipelines.

**Current Implementation Status:** Core pipeline operational with scoreboard-based RAW hazard detection. All 4 warps × 4 lanes execute correctly with proper instruction dependency tracking and interleaved scheduling.

WarpForge is intended for:

* computer architecture learning
* RTL experimentation
* GPU microarchitecture exploration
* FPGA-oriented architectural study
* academic demonstration of SIMT execution
* hands-on study of hazard detection and scoreboard design

---

# Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Architectural Philosophy](#architectural-philosophy)
- [Top-Level Architecture](#top-level-architecture)
- [Pipeline](#pipeline)
- [Compute Unit Configuration](#compute-unit-configuration)
- [Warp Scheduling](#warp-scheduling)
- [Special Registers](#special-registers)
- [ISA](#isa)
- [Branch Model](#branch-model)
- [Memory Model](#memory-model)
- [Scoreboard & Hazard Detection](#scoreboard--hazard-detection)
- [Key Design Decisions](#key-design-decisions)
- [RTL File Structure](#rtl-file-structure)
- [Verified Programs](#verified-programs)
- [Simulation Output](#simulation-output)
- [How to Simulate](#how-to-simulate)
- [Synthesis Results](#synthesis-results-vivado-xilinx-7-series)
- [Concepts Demonstrated](#concepts-demonstrated)
- [Future Work](#future-work)
- [Educational Goal](#educational-goal)

---

# Overview

Modern GPUs execute thousands of threads by grouping them into lockstep execution units called **warps** (or wavefronts). WarpForge reproduces this core idea using:

* **4 independent warps**
* **4 SIMD lanes per warp**
* **5-stage in-order pipeline**
* **Per-warp vector register storage**
* **Round-robin warp scheduler**
* **Uniform branch execution**
* **Shared word-addressed memory**

Each warp maintains its own program counter and register context, while a scheduler interleaves warp issue to hide instruction latency.

The design includes **per-warp scoreboard** for register dependency tracking and deliberately avoids unnecessary complexity such as caches and divergence stacks, maintaining transparency in the execution model while supporting realistic hazard detection.

---

# Repository Structure

```text
warpforge-simt-gpu-core/
├── docs/
├── rtl/
│   ├── alu/
│   │   └── vector_ALU.v
│   ├── core/
│   │   ├── compute_unit.v
│   │   └── top.v
│   ├── include/
│   │   └── cu_defs.vh
│   ├── memory/
│   │   ├── data_memory.v
│   │   └── instruction_memory.v
│   ├── pipeline/
│   │   ├── decode_unit.v
│   │   ├── execute_stage.v
│   │   ├── IFU.v
│   │   ├── mem_stage.v
│   │   └── writeback_stage.v
│   ├── register_file/
│   │   └── vector_register_file.v
│   └── warp/
│       ├── scoreboard.v        ← Per-warp register dependency tracking
│       └── warp_manager.v
├── sim/
│   ├── programs/
│   │   ├── data.mem
│   │   └── program.mem
│   └── run/
│       ├── run_icarus.bat      ← Windows simulation script
│       └── run_icarus.sh       ← Linux/macOS simulation script
├── tb/
│   └── unit/
│       └── tb_compute_unit.v
├── .gitignore
├── DIVERGENCE_PLAN.md          ← Future divergence implementation roadmap
└── README.md
```

---

# Architectural Philosophy

WarpForge uses a deliberately clean execution model:

* issue one warp
* stall that warp until writeback
* let other warps occupy pipeline slots

This turns the scheduler itself into the hazard avoidance mechanism.

No forwarding network.
No scoreboard.
No dependency matrix the size of a small nervous system.

That simplicity is educational gold because every moving part remains visible.

---

# Top-Level Architecture

```text
top.v
├── compute_unit.v
│   ├── warp_manager.v
│   ├── IFU.v
│   ├── decode_unit.v
│   ├── execute_stage.v
│   ├── mem_stage.v
│   ├── writeback_stage.v
│   └── vector_register_file.v
├── instruction_memory.v
└── data_memory.v
```

---

# Pipeline

WarpForge uses a classic 5-stage in-order pipeline:

```text
IF → ID → EX → MEM → WB
```

## Stage Description

| Stage | Function                                 |
| ----- | ---------------------------------------- |
| IF    | Fetch instruction for selected warp      |
| ID    | Decode instruction and prepare operands  |
| EX    | SIMD ALU execution and branch resolution |
| MEM   | Shared memory access                     |
| WB    | Register writeback and warp commit       |

---

# Compute Unit Configuration

| Parameter             | Value               |
| --------------------- | ------------------- |
| Number of warps       | 4                   |
| Warp size             | 4 lanes             |
| Lane width            | 32 bits             |
| Registers per warp    | 32 vector registers |
| Total logical threads | 16                  |

---

# Warp Scheduling

Warp scheduling is handled by `warp_manager.v`.

## Scheduling Policy

* round-robin selection
* only READY warps eligible
* STALL warps excluded
* DONE warps removed permanently

## Warp States

```text
READY = 00
STALL = 01
DONE  = 10
```

## Warp Lifecycle

```text
READY → STALL → READY
READY → DONE
```

## Issue Rule

The moment a warp issues:

```text
READY → STALL
```

This prevents any second instruction from that warp entering pipeline before current instruction commits.

That single decision eliminates all data hazards.

---

# Two-Cycle Scheduler Guard

A subtle but important scheduler safeguard is included:

After commit, a warp cannot be immediately reissued in the same cycle.

This prevents:

* scheduler race conditions
* duplicate issue
* same-cycle re-selection artifacts

Without this guard, round-robin scheduling starts behaving like a caffeinated squirrel.

---

# Special Registers

## r0 — Hardwired Zero

```text
reads always return 0
writes silently discarded
```

## r1 — Thread ID Register

Initialized automatically during reset.

## Thread ID Mapping

```text
Warp 0: [0, 1, 2, 3]
Warp 1: [4, 5, 6, 7]
Warp 2: [8, 9, 10, 11]
Warp 3: [12, 13, 14, 15]
```

This allows thread-indexed programs without software setup.

---

# ISA

WarpForge uses a fixed-width 32-bit custom ISA inspired by MIPS encoding.

---

# Instruction Formats

## R-Type

```text
opcode rs rt rd 0 func
```

## I-Type

```text
opcode rs rt imm16
```

---

# Supported Instructions

| Opcode | Mnemonic   | Operation          |
| ------ | ---------- | ------------------ |
| 000000 | ALU R-type | rd = rs OP rt      |
| 000001 | ADDI       | rt = rs + imm      |
| 001000 | LOAD       | rt = mem[rs + imm] |
| 001001 | STORE      | mem[rs + imm] = rt |
| 010000 | BEQ        | if rs == rt branch |
| 010001 | BNE        | if rs != rt branch |
| 011000 | EXIT       | warp → DONE        |

---

# ALU Functions

| Function | Code |
| -------- | ---- |
| ADD      | 0    |
| SUB      | 1    |
| AND      | 2    |
| OR       | 3    |
| XOR      | 4    |
| SLT      | 5    |

---

# Branch Model

WarpForge currently supports **uniform branching**.

A branch is taken only if **all SIMD lanes agree**.

## Branch Rule

```text
taken = AND(all lane comparisons)
```

This means all lanes must evaluate branch condition identically.

## BNE Handling

A dedicated decode signal fixes branch inversion:

```text
taken = equality XOR branch_inv
```

This allows:

* BEQ = direct equality
* BNE = inverted equality

---

# Memory Model

WarpForge uses **word-addressed shared memory**.

## Address Rule

```text
mem[address]
```

No byte shifting.

No address scaling.

Register contents directly select word locations.

This keeps simulation easy to inspect.

---

# Scoreboard & Hazard Detection

WarpForge implements a **per-warp scoreboard** for real-time register dependency tracking.

## Scoreboard Architecture

Each warp maintains a busy table tracking in-flight destination registers:

* Set: when instruction with `reg_write` is issued from decode
* Clear: when instruction commits to writeback
* Query: combinational stall check during decode

## RAW Hazard Prevention

```text
Instruction N: ADD r2, r3, r4        ← Sets r2 busy
Instruction N+1: SUB r5, r2, r6      ← Queries r2 dependency
                                       → STALL if r2 still busy
```

## Stall Behavior

When a source register is marked busy:

1. Instruction cannot leave decode
2. Issuing warp transits to STALL state
3. Warp skips scheduler until register clears
4. Writeback clears register, warp returns to READY

## Design Benefits

* **No forwarding network** — Simpler than data forwarding paths
* **Transparent timing** — Stalls are visible and predictable
* **Correct by construction** — Single in-flight instruction per warp guarantees safety
* **Educational clarity** — Scoreboard logic is small enough to inspect at RTL level

---

# Key Design Decisions

---

# 1. Scoreboard-Based Dependency Tracking

WarpForge implements a per-warp scoreboard to detect RAW hazards while maintaining clarity of execution flow.

## Why Not Just Interleave?

Early design avoided scoreboards by strict issue-stall discipline:
* Issue warp → immediately stall it
* Only one instruction per warp in flight
* No dependency checking needed

**Decision Update (v1.1):** Added scoreboard to support:
* Realistic hazard detection
* Educational study of dependency tracking
* Foundation for future divergence support
* Measurable stall behavior

## How It Works

```text
Scoreboard tracks which registers are "busy"
(i.e., destination of in-flight instruction)

On decode:
1. Check if source registers are busy → STALL if true
2. Check if destination register is ALU_ZERO → never mark busy
3. Query is combinational (cycle-accurate results)

On writeback:
1. Destination register cleared from busy table
2. Warp returns to READY state
```

This keeps the design educational—every stall is visible, traceable, and deterministic.

---

# 2. Single In-Flight Instruction Eliminates Wrong-Path Execution

Branch target is resolved in EX but committed in WB.

Normally this risks wrong-path fetch.

WarpForge avoids that because issuing warp is already stalled.

Therefore:

* no second instruction from same warp enters IF
* no wrong-path instruction exists

Result:

```text
no flush logic needed
```

That removes one of the nastiest pieces of beginner pipeline design.

---

# 3. Combinational Writeback, Commit, and Scoreboard Clear

Warp commit and register cleanup occur in same cycle as VRF write.

## Current Behavior

```text
WB:
VRF write
warp state update
PC commit
```

Earlier registered commit caused:

* one phantom idle cycle
* missed round-robin slot
* visible throughput loss

Removing that extra register fixed scheduler rhythm completely.

Additionally, clearing the scoreboard entry combinationally allows the next warp issue in the same cycle—critical for maintaining round-robin interleaving efficiency.

---

# 4. Word-Addressed Memory Simplicity

Address values directly match simulation addresses.

This makes stores easy to verify:

```text
STORE r4, r1, 0
```

directly means:

```text
mem[tid] = value
```

---

# 5. Uniform Branching (Current Design Point)

All SIMD lanes must agree on branch outcome.

```text
taken = AND(all lane comparisons)
```

**Limitation:** Lanes that disagree still execute both paths sequentially, wasting cycles.

**Planned Enhancement:** Divergence stack (see DIVERGENCE_PLAN.md) will enable per-lane masking and selective execution, allowing individual lanes to take different paths while tracking reconvergence points.

---

# RTL File Structure

| File                   | Description                             |
| ---------------------- | --------------------------------------- |
| cu_defs.vh             | Parameters and ISA definitions          |
| top.v                  | Top wrapper                             |
| compute_unit.v         | Pipeline integration                    |
| warp_manager.v         | Warp scheduler & state machine          |
| scoreboard.v           | Per-warp register busy tracking         |
| IFU.v                  | Instruction fetch                       |
| decode_unit.v          | Decode stage & scoreboard query         |
| execute_stage.v        | SIMD ALU and branch resolution          |
| mem_stage.v            | Memory stage                            |
| writeback_stage.v      | Writeback, commit & scoreboard clear    |
| vector_register_file.v | Register storage (4 warps × 32 regs)    |
| vector_ALU.v           | Lane arithmetic (ADD, SUB, AND, OR)     |
| instruction_memory.v   | Program ROM                             |
| data_memory.v          | Shared RAM (16 words)                   |
| program.mem            | Test program                            |
| tb_compute_unit.v      | Testbench                               |

---

# Verified Programs

---

# Program 1 — Basic Arithmetic and Store

```text
ADDI r2, r0, 10
ADDI r3, r1, 0
ADD  r4, r2, r3
STORE r4, r1, 0
EXIT
```

## Result

```text
mem[i] = 10 + i
```

---

# Program 2 — Counted Loop with BNE

```text
ADDI r2, r0, 0
ADDI r3, r0, 4
ADD  r4, r2, r1
ADDI r2, r2, 1
BNE  r2, r3, -8
STORE r4, r1, 0
EXIT
```

## Result

```text
mem[i] = 3 + i
```

---

# Simulation Output

WarpForge prints execution events directly.

## Commit Example

```text
[COMMIT] T=355000 | Warp 0 | PC=0010 | --> READY next_pc=0008
```

Warp committed instruction and returned READY.

---

## Branch Example

```text
[BRANCH] T=335000 | Warp 0 | PC=0010 | TAKEN → target=0008
```

Branch detected in EX stage.

---

## Store Example

```text
[STORE] T=1035000 | lane0 | addr=0 | data=3
```

Lane 0 writes memory.

---

# Final Memory Dump

```text
mem[00]=3  mem[01]=4  mem[02]=5  mem[03]=6
mem[04]=7  mem[05]=8  mem[06]=9  mem[07]=10
mem[08]=11 mem[09]=12 mem[10]=13 mem[11]=14
mem[12]=15 mem[13]=16 mem[14]=17 mem[15]=18
```

All 16 logical threads complete correctly.

---

# How to Simulate

## Prerequisites

Install one of the following simulators:

* **Icarus Verilog** — [http://iverilog.icarus.com](http://iverilog.icarus.com) (free, cross-platform)
* **Vivado Simulator** — included with Xilinx Vivado (recommended for FPGA synthesis flow)

Make sure `iverilog` and `vvp` are added to your system PATH after installation.

---

## Icarus Verilog — Windows

Navigate to the `sim/run/` folder and run:

```bat
.\run_icarus.bat
```

The script compiles all RTL sources and launches the simulation automatically.

To run manually from the `sim/run/` directory:

```bat
iverilog -o sim.out -I ..\..\rtl\include ..\..\rtl\core\top.v ..\..\rtl\core\compute_unit.v ..\..\rtl\warp\warp_manager.v ..\..\rtl\pipeline\IFU.v ..\..\rtl\pipeline\decode_unit.v ..\..\rtl\pipeline\execute_stage.v ..\..\rtl\pipeline\mem_stage.v ..\..\rtl\pipeline\writeback_stage.v ..\..\rtl\alu\vector_alu.v ..\..\rtl\register_file\vector_register_file.v ..\..\rtl\memory\instruction_memory.v ..\..\rtl\memory\data_memory.v ..\..\tb\unit\tb_compute_unit.v
cd ..
vvp run\sim.out
```

> **Note:** `vvp` must be run from the `sim/` directory so that `$readmemh` can locate `programs/program.mem` and `programs/data.mem` correctly.

---

## Icarus Verilog — Linux / macOS

Navigate to the `sim/run/` folder and run:

```bash
chmod +x run_icarus.sh
./run_icarus.sh
```

To run manually from the `sim/run/` directory:

```bash
iverilog -o sim.out -I ../../rtl/include \
  ../../rtl/core/top.v \
  ../../rtl/core/compute_unit.v \
  ../../rtl/warp/warp_manager.v \
  ../../rtl/pipeline/IFU.v \
  ../../rtl/pipeline/decode_unit.v \
  ../../rtl/pipeline/execute_stage.v \
  ../../rtl/pipeline/mem_stage.v \
  ../../rtl/pipeline/writeback_stage.v \
  ../../rtl/alu/vector_alu.v \
  ../../rtl/register_file/vector_register_file.v \
  ../../rtl/memory/instruction_memory.v \
  ../../rtl/memory/data_memory.v \
  ../../tb/unit/tb_compute_unit.v

cd ..
vvp run/sim.out
```

---

## Vivado

1. Create a new RTL project in Vivado
2. Add all `.v` files from the `rtl/` directory as design sources
3. Add `sim/programs/program.mem` and `sim/programs/data.mem` as simulation sources
4. Set `tb/unit/tb_compute_unit.v` as the simulation top module
5. Run behavioral simulation

---

## Changing the Test Program

Edit `sim/programs/program.mem` to load a different instruction sequence.

Refer to the [ISA](#isa) section for instruction encoding.

The `sim/programs/data.mem` file pre-initializes the data memory. Clear it or modify it as needed for your program.

---

# Synthesis Results (Vivado, Xilinx 7-Series)

| Module               | Slice LUTs | Slice Registers |
| -------------------- | ---------- | --------------- |
| compute_unit         | 13,476     | 16,735          |
| decode_unit          | 13,069     | 129             |
| execute_stage        | 9          | 416             |
| mem_stage            | 328        | 166             |
| vector_register_file | 0          | 15,872          |
| warp_manager         | 43         | 89              |

---

# Interpretation

## Register Dominance

Vector register file dominates FF usage:

```text
4 × 32 × 4 × 32 = 16,384 bits
```

That is expected.

Registers are expensive little silicon bricks.

## Decode LUT Inflation

Vivado moved logic aggressively across boundaries.

The reported decode LUT cost is optimization artifact, not true decode complexity.

## IOB Overflow

IOBs exceed FPGA package limits.

Expected because WarpForge is a core, not a deployable top-level chip.

---

# Concepts Demonstrated

WarpForge teaches:

* SIMT execution
* warp scheduling
* latency hiding
* vector register organization
* SIMD ALU design
* branch commit mechanics
* pipeline register design
* RTL microarchitecture partitioning

---

# Implementation Roadmap

## Completed
- ✅ Core 5-stage pipeline (IF/ID/EX/MEM/WB)
- ✅ Per-warp scoreboard for RAW hazard detection
- ✅ Round-robin warp scheduling
- ✅ Vector register file (4 warps, 32 regs each, 32-bit lanes)
- ✅ SIMD ALU (4 lanes wide)
- ✅ Uniform branch execution
- ✅ Word-addressed shared memory

## Future Enhancements (Educational Value)

Possible next architectural steps:

* branch Divergence Support
* predication support (alternative to divergence)
* scalar co-processor unit
* instruction cache with prefetch
* data cache with coherency
* wider warp sizes (8 or 16 lanes)
* multi-compute-unit scaling
* vectorized memory operations (gather/scatter)

That is where the little teaching machine begins to mutate toward something suspiciously industrial.

---

# Educational Goal

WarpForge exists to make GPU execution understandable at RTL level.

Real GPUs hide these ideas behind millions of gates, proprietary schedulers, and documentation that often reads like a treaty negotiated by cautious ghosts.

WarpForge keeps the machinery visible:

* every warp state
* every pipeline transition
* every register write
* every branch decision

Because architecture becomes real only when you can point at the wire and explain why it exists.