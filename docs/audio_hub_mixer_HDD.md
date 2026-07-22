# Audio Hub Mixer IP Hardware Design Description

| Item | Value |
| --- | --- |
| Document | Hardware Design Description / IP Databook |
| IP name | Audio Hub Mixer |
| RTL module | `audio_hub_mixer` |
| Version | v1.0 |
| Status | Design baseline |
| Maximum configuration | 8 input streams × 4 output streams |

---

## 1. Introduction

### 1.1 Purpose

This document defines the functional behavior, microarchitecture, interfaces, register map, timing, error handling, programming model, and verification requirements of the Audio Hub Mixer IP.

The Mixer combines selected synchronous input samples by signed addition. It supports up to eight independent input audio streams and four independent output audio streams. Each output has its own selection mask register and may select any subset of the eight inputs. The same input sample may be used by multiple outputs, but is consumed only once per mixing process.

### 1.2 Scope

The IP performs only sample routing and summation:

- 8 input streams.
- 4 output streams.
- Independent input-selection mask for each output.
- Unsigned/Signed parallel accumulation.  TBD
- Configurable saturation or wraparound at the output width.
- Ready/valid flow control with input and output buffering.

### 1.3 Explicit exclusions

The following functions are outside the Mixer:

- Gain, volume, coefficient multiplication, normalization, or gain matrix.
- Sample-rate conversion or asynchronous-rate matching.
- Automatic sample insertion, zero filling, or sample dropping.
- Channel packing, interleave, planar conversion, or slot reordering.
- DMA request generation.
- Clock-domain crossing.

Gain adjustment shall be performed by the Audio Hub Digital Gain IP. Channel packing shall be performed by the Merge IP. Any asynchronous source shall pass through a CDC FIFO or sample-rate conversion block before entering the Mixer.

---

## 2. Features

- Supports 8 inputs and 4 outputs.
- Default 32-bit signed PCM; 16-bit and 24-bit PCM are also supported through `DATA_WIDTH`.
- Four independent 8-input selection masks registers.
- One input may feed any number of outputs without being popped multiple times.
- Balanced signed adder tree for each output.
- Internal accumulator width of `DATA_WIDTH + 3` bits for lossless summation of eight full-scale inputs.
- Output saturation enabled by default; wraparound mode is available for compatibility.
- Per-channel input FIFO and per-channel output FIFO.
- Independent output ready/valid interfaces.

---

## 3. Configurable Parameters

| Parameter | Legal values | Default | Description |
| --- | ---: | ---: | --- |
| `IN_FIFO_DEPTH` | Power of 2, ≥2 | 4 | Depth of each input FIFO. |
| `OUT_FIFO_DEPTH` | Power of 2, ≥2 | 4 | Depth of each output FIFO. |

---

## 4. Functional Description

### 4.1 Mixing equation

For output `o`, input `i`, and mixing slot `n`:

```text
select[o][i] = output_enable[o] & input_enable[i] 

acc[o,n] = sum(input[i,n]) for every i where select[o][i] = 1

output[o,n] = saturate_or_wrap(acc[o,n], DATA_WIDTH)
```

No coefficient multiplication is performed. A selected input contributes exactly its signed PCM value. An unselected input contributes zero.

### 4.2 Sample alignment contract

The Mixer aligns streams by sample order, not by timestamp. The first sample popped from every required FIFO belongs to the same logical sample time, followed by the second sample from each FIFO, and so on.

Therefore:

- The Mixer waits when any required input FIFO is empty.
- Temporary arrival skew is absorbed by the input FIFOs.
- The Mixer reports error when any of the input stream timeout.

Software should disable and flush the Mixer when a matrix change also changes stream alignment membership.

### 4.3 Input acceptance

For a currently required input:

```text
input_ready[i] = mixer_enable & mixer_input_rx_enable[i] !input_fifo_full[i]
```

`input_ready[i]` is low for disabled or FIFO full. The Mixer does not silently discard unused samples. A transfer is accepted only when `input_valid[i] && input_ready[i]` is true.

Each producer shall hold `input_valid` and `input_data` stable until the transfer is accepted.

### 4.4 Slot scheduling

A new calculated slot may begin only when all of the following are true:

- Mixer is enabled.
- Active configuration is valid.
- No previous slot is using the non-overlapped arithmetic pipeline.
- Every required input FIFO is non-empty.
- Every enabled output FIFO has at least one free entry.
- Flush or soft reset is not active.

The scheduler then pops all required inputs in the same clock cycle and captures the samples. All enabled outputs are calculated in parallel.

### 4.5 Output enqueue and backpressure

Results from one slots are written atomically into the noted enabled output FIFOs. Output FIFOs drain independently through their respective ready/valid interfaces.

If one output stalls, other output FIFOs continue draining. All output tx channel has its own independent FIFO. Once asserted, `output_valid[o]` remains asserted and `output_data[o]` remains stable until `output_ready[o]` is observed high.

### 4.6 Disable and flush behavior

- Clearing `CTRL.EN` prevents new slots generation from starting. In-flight arithmetic completes and already queued output data remains available to drain.
- `CTRL.FLUSH` immediately stops acceptance, invalidates in-flight work, clears all input and output FIFOs, and then sets `IRQ_STATUS.FLUSH_DONE`.
- `CTRL.SOFT_RESET` performs a flush, disables the engine, clears active and shadow configuration, status, and counters, and restores reset defaults.

`FLUSH` intentionally discards buffered audio samples and shall be used only when a discontinuity is acceptable or required for realignment.

---

## 5. System Architecture

visio diagram

## 6. Datapath Design

All operands are sign-extended to `ACC_WIDTH` before addition. Intermediate nodes retain `ACC_WIDTH`; this width can represent the exact sum of eight `DATA_WIDTH` signed operands.

### 6.1 Saturation and wraparound

The representable output range is:

```text
MAX =  2^(DATA_WIDTH-1) - 1
MIN = -2^(DATA_WIDTH-1)
```

When `SAT_CTRL.SAT_EN = 1`:

```text
acc > MAX  -> output = MAX
acc < MIN  -> output = MIN
otherwise  -> output = acc[DATA_WIDTH-1:0]
```

When `SAT_EN = 0`, the low `DATA_WIDTH` bits are returned, producing two's-complement wraparound. Overflow detection and counters remain active in both modes.

There is no rounding step because the Mixer performs no scaling and discards no fractional bits.

---

## 7. Interface Description

### 7.1 Clock and reset

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `clk_i` | Input | 1 | Mixer core, stream, and APB clock. |
| `rst_n_i` | Input | 1 | Active-low reset; asynchronous assertion and synchronous deassertion to `clk_i`. |

The baseline IP is single-clock. If APB, producer, or consumer logic uses another clock, CDC shall be implemented outside this IP.

### 7.2 Audio input streams

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `input_valid_i` | Input | `NUM_INPUTS` | Per-input sample-valid vector. |
| `input_ready_o` | Output | `NUM_INPUTS` | Per-input sample-ready vector. |
| `input_data_i` | Input | `NUM_INPUTS × DATA_WIDTH` | Signed PCM samples, one packed element per input. |

### 7.3 Audio output streams

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `output_valid_o` | Output | `NUM_OUTPUTS` | Per-output result-valid vector. |
| `output_ready_i` | Input | `NUM_OUTPUTS` | Per-output result-ready vector. |
| `output_data_o` | Output | `NUM_OUTPUTS × DATA_WIDTH` | Signed mixed PCM result for each output. |

### 7.5 Interrupt

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `irq_o` | Output | 1 | Level interrupt: OR of enabled sticky interrupt status bits. |

---

## 8. Register Map

Derived parameters:

```text
For loseless summation data:
ACC_WIDTH = DATA_WIDTH + ceil(log2(8))
          = DATA_WIDTH + 3
```

### 8.1 Register summary

| Offset | Name | Access | Reset | Description |
| ---: | --- | --- | ---: | --- |
| `0x008` | `CTRL` | RW/WO | `0x00000000` | Enable, flush, soft reset, commit, counter clear. |
| `0x00C` | `STATUS` | RO | `0x00000002` | Runtime state summary. |
| `0x010` | `INPUT_ENABLE` | RW-S | `0x00000000` | Shadow input enable mask. |
| `0x014` | `OUTPUT_ENABLE` | RW-S | `0x00000000` | Shadow output enable mask. |
| `0x018` | `OUT0_MATRIX` | RW-S | `0x00000000` | Shadow source mask for output 0. |
| `0x01C` | `OUT1_MATRIX` | RW-S | `0x00000000` | Shadow source mask for output 1. |
| `0x020` | `OUT2_MATRIX` | RW-S | `0x00000000` | Shadow source mask for output 2. |
| `0x024` | `OUT3_MATRIX` | RW-S | `0x00000000` | Shadow source mask for output 3. |
| `0x028` | `SAT_CTRL` | RW-S | `0x00000001` | Shadow saturation control. |
| `0x02C` | `CFG_STATUS` | RO | `0x00000000` | Commit sequence and configuration validity. |
| `0x030` | `IRQ_ENABLE` | RW | `0x00000000` | Interrupt enable mask. |
| `0x034` | `IRQ_STATUS` | W1C/RO | `0x00000000` | Maskable sticky interrupt status. |
| `0x038` | `ERROR_STATUS` | W1C/RO | `0x00000000` | Sticky configuration error detail. |
| `0x03C` | `STARVE_STATUS` | RO | `0x00000000` | Required empty-input indication. |
| `0x040` | `BLOCK_STATUS` | RO | `0x00000000` | Enabled full-output indication. |
| `0x044` | `IN_FIFO_EMPTY` | RO | implementation | Input FIFO empty bits. |
| `0x048` | `IN_FIFO_FULL` | RO | `0x00000000` | Input FIFO full bits. |
| `0x04C` | `OUT_FIFO_EMPTY` | RO | implementation | Output FIFO empty bits. |
| `0x050` | `OUT_FIFO_FULL` | RO | `0x00000000` | Output FIFO full bits. |
| `0x060`–`0x07C` | `IN_FIFO_LEVEL0`–`7` | RO | `0x0` | Per-input FIFO occupancy. |
| `0x080`–`0x08C` | `OUT_FIFO_LEVEL0`–`3` | RO | `0x0` | Per-output FIFO occupancy. |
| `0x08.` | `MIX_COUNT_LO` | RO | `0x00000000` | Mixing-slot counter bits `[31:0]`. |
| `0x08.` | `MIX_COUNT_HI` | RO | `0x00000000` | Mixing-slot counter bits `[63:32]`. |
| `0x08.`–`0x0A4` | `SAT_COUNT0`–`3` | RO | `0x00000000` | Per-output saturating overflow counters. |
| `0x0B0` | `ACTIVE_INPUT_ENABLE` | RO | `0x00000000` | Active input enable mask. |
| `0x0B4` | `ACTIVE_OUTPUT_ENABLE` | RO | `0x00000000` | Active output enable mask. |
| `0x0B8`–`0x0C4` | `ACTIVE_OUT0_MATRIX`–`3` | RO | `0x00000000` | Active matrix rows. |
| `0x0C8` | `ACTIVE_SAT_CTRL` | RO | `0x00000001` | Active saturation control. |
| `0x0FC` | `SCRATCH` | RW | `0x00000000` | Software scratch register. |

`RW-S` denotes a shadow register. The value affects the datapath only after a successful `CFG_COMMIT`.

### 8.2 `CTRL` — offset `0x008`

| Bits | Name | Access | Reset | Description |
| ---: | --- | --- | ---: | --- |
| `[0]` | `MIXER_EN` | RW | 0 | Enable starting new mixing slots. |
| `[1]` | `FLUSH` | WO | 0 | Write 1 to flush pipeline and all FIFOs; self-clearing. |
| `[2]` | `SOFT_RESET` | WO | 0 | Write 1 for internal reset; self-clearing. |
| `[3]` | `COUNTER_CLEAR` | WO | 0 | Write 1 to clear slot and saturation counters. |
| `[31:5]` | Reserved | — | 0 | Write zero; read zero. |

### 8.3 `STATUS` — offset `0x00C`

| Bits | Name | Description |
| ---: | --- | --- |
| `[0]` | `ACTIVE` | `EN=1`, active configuration valid, and at least one output enabled. |
| `[1]` | `IDLE` | No arithmetic slot is in flight. Output FIFOs may still contain data. |
| `[2]` | `PIPE_BUSY` | Datapath is processing a captured slot. |
| `[3]` | `CFG_PENDING` | A valid commit request is waiting for the next slot boundary. |
| `[4]` | `FLUSH_BUSY` | FIFO and pipeline flush is in progress. |
| `[5]` | `INPUT_STARVED` | At least one required input FIFO is empty. |
| `[6]` | `OUTPUT_BLOCKED` | At least one enabled output FIFO is full. |
| `[7:11]` | `FSM_STATE` | Encoded internal state for debug. |
| `[31:12]` | Reserved | Read zero. |

### 8.4 Enable and matrix registers

#### `INPUT_ENABLE` — offset `0x010`

| Bits | Description |
| ---: | --- |
| `[7:0]` | One bit per input; 1 permits that input to participate. |
| `[31:8]` | Reserved. |

#### `OUTPUT_ENABLE` — offset `0x014`

| Bits | Description |
| ---: | --- |
| `[3:0]` | One bit per output; 1 generates an output result for each slot. |
| `[31:4]` | Reserved. |

#### `OUTn_MATRIX` — offsets `0x018` to `0x024`

| Bits | Description |
| ---: | --- |
| `[7:0]` | `bit i = 1` selects input `i` into output `n`. |
| `[31:8]` | Reserved. |

An enabled output whose effective matrix row is zero causes the commit to fail with `CFG_ZERO_SOURCE`.

### 8.5 `SAT_CTRL` — offset `0x028`

| Bits | Name | Access | Reset | Description |
| ---: | --- | --- | ---: | --- |
| `[0]` | `SAT_EN` | RW-S | 1 | 1: clamp on overflow; 0: two's-complement wrap. |
| `[31:1]` | Reserved | — | 0 | Write zero; read zero. |

### 8.6 `CFG_STATUS` — offset `0x02C`

| Bits | Name | Description |
| ---: | --- | --- |
| `[0]` | `SHADOW_DIRTY` | A shadow register changed after the last successful commit. |
| `[1]` | `COMMIT_PENDING` | Commit accepted and waiting for a safe slot boundary. |
| `[2]` | `ACTIVE_VALID` | Current active configuration is valid. |
| `[3]` | `LAST_COMMIT_OK` | Last completed commit succeeded. Cleared by a new commit request. |
| `[15:8]` | `CFG_SEQ` | Increments after each successful commit. Wraps naturally. |
| `[31:16]` | Reserved | Read zero. |

### 8.7 Interrupt registers

`IRQ_ENABLE` and `IRQ_STATUS` use the same bit assignments:

| Bit | Name | Set condition |
| ---: | --- | --- |
| 0 | `SAT_OUT0` | Output 0 full-precision sum exceeded the output range. |
| 1 | `SAT_OUT1` | Output 1 full-precision sum exceeded the output range. |
| 2 | `SAT_OUT2` | Output 2 full-precision sum exceeded the output range. |
| 3 | `SAT_OUT3` | Output 3 full-precision sum exceeded the output range. |
| 4 | `INPUT_STARVE` | Scheduler first enters a wait caused by a required empty input. |
| 5 | `OUTPUT_BLOCKED` | Scheduler first enters a wait caused by an enabled full output FIFO. |
| 6 | `CFG_DONE` | Shadow configuration was successfully activated. |
| 7 | `CFG_ERROR` | Configuration commit was rejected. |
| 8 | `FLUSH_DONE` | Requested flush completed. |
| 31:8.| Reserved | Read zero. |

`IRQ_STATUS` bits are sticky and cleared by writing 1. Saturation status is set even when wrap mode is selected.

### 8.8 `ERROR_STATUS` — offset `0x038`

| Bit | Name | Meaning |
| ---: | --- | --- |
| 0 | `CFG_ZERO_SOURCE` | At least one enabled output has no effective selected input. |
| 1 | `CFG_INVALID_SEL` | Configuration selected an unimplemented input or output. |
| 2 | `CFG_BUSY` | A commit was requested while another commit was pending. |
| 3 | `CFG_RESERVED` | A reserved configuration bit was written as 1. |
| 31:4 | Reserved | Read zero. |

Errors are sticky W1C. A failed commit does not alter the active configuration.

### 8.8.FIFO status

- `STARVE_STATUS[7:0]`: bit `i` is 1 when input `i` is required and its FIFO is empty.
- `BLOCK_STATUS[3:0]`: bit `o` is 1 when output `o` is enabled and its FIFO is full.
- FIFO empty/full registers contain one bit per implemented FIFO.
- Each FIFO-level register reports occupancy from zero through the configured depth.

### 8.10 Counters

- `MIX_COUNT` increments once when one slot is atomically enqueued.
- `SAT_COUNTn` increments for every overflowing slot on output `n`, regardless of saturation mode.
- Saturation counters stop at `0xFFFF_FFFF` rather than wrapping.
- `CTRL.COUNTER_CLEAR` clears all counters atomically.
- Software should read `MIX_COUNT_HI`, then `MIX_COUNT_LO`, then `MIX_COUNT_HI` again and retry if the high word changed.

---
