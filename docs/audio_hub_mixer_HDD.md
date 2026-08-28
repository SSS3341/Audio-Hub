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

The Mixer combines selected synchronous input samples by signed or unsigned addition. It supports up to eight independent input audio streams and four independent output audio streams. Each output has its own selection mask register and may select any subset of the eight inputs. The same input sample may be used by multiple outputs, but is consumed only once per mixing process.

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
- Supports 32-bit PCM; 16-bit and 24-bit data configured through register.
- Supports 4 independent 8-input selection registers for each output channel.
- Supports signed or unsigned input mixing configured by registers.
- Supports unsigned input to signed output mixing result conversion.
- Internal accumulator width of `DATA_WIDTH + 3` bits for lossless summation for debugging .
- Supports output saturation with a overflow status flag.
- Supports per-channel input FIFO and per-channel output FIFO.
- Independent input/output ready/valid interfaces.

---

## 3. Configurable Parameters

| Parameter | Legal values | Default | Description |
| --- | ---: | ---: | --- |
| `IN_FIFO_DEPTH` | Power of 2, ≥2 | 4 | Depth of each input FIFO. |
| `OUT_FIFO_DEPTH` | Power of 2, ≥2 | 4 | Depth of each output FIFO. |

---

## 4. Functional Description

### 4.1 Mixing equation

For output `o`, if choose input `i,j,k` , and mixing slot `n`:

```text
output_o_slot[n] = input_i_slot[n] + input_j_slot[n] + input_k_slot[n]
```

No coefficient multiplication is performed. A selected input contributes exactly its signed PCM value. An unselected input contributes zero.

### 4.2 Sample alignment contract

The Mixer aligns streams by sample order. The first sample popped from every required FIFO belongs to the same logical sample time, followed by the second sample from each FIFO, and so on.

Therefore:

- The Mixer waits when any required input FIFO is empty.
- Temporary arrival skew is absorbed by the input FIFOs.
- The Mixer reports error when any of the input stream timeout.

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

---

## 5. System Architecture

The architecture consists of receive stream control, a per-channel FIFO bank, mixer scheduling/output control, and output selection/status logic.

```text
                            +----------------------+
rx_valid[N-1:0] ----------->|                      |
rx_data[N-1:0][31:0] ------>|    RX Stream FSM     |
rx_ready[N-1:0] <-----------|                      |
                            +----------+-----------+
                                       |
                wr_en[N-1:0]           |
                wdata[N-1:0][31:0]     |
                                       v
                +------------------------------------------+
                |            RX FIFO Bank                  |
                | +---------+ +---------+        +--------+|
                | | FIFO 0  | | FIFO 1  |  ...   | FIFO N ||
                | +---------+ +---------+        +--------+|
                +--------------------+---------------------+
                                     |
                rdata[N-1:0][31:0]   |
                empty[N-1:0]         |
                word_cnt[N-1:0]      |
                                     v
      +------------------+------------------+------------------+
      |                  |                  |                  |
      v                  v                  v                  v
+-----------+      +-----------+      +-----------+      +-----------+
| TX0 Mixer |      | TX1 Mixer |      | TX2 Mixer |      | TX3 Mixer |
| Scheduler |      | Scheduler |      | Scheduler |      | Scheduler |
+-----+-----+      +-----+-----+      +-----+-----+      +-----+-----+
      |                  |                  |                  |
      v                  v                  v                  v
+-----------+      +-----------+      +-----------+      +-----------+
| TX FIFO 0 |      | TX FIFO 1 |      | TX FIFO 2 |      | TX FIFO 3 |
+-----+-----+      +-----+-----+      +-----+-----+      +-----+-----+
      |                  |                  |                  |
 valid/ready/data   valid/ready/data   valid/ready/data   valid/ready/data
      |                  |                  |                  |
      +---------------- Crossbar sources ---------------------+

                                       |
                              tx_valid/ready/data
                                       |
                                       |               
                                       v               
                                Crossbar output     
                                         
```


## 6. Datapath Design

All operands are sign-extended or unsign-extended to `ACC_WIDTH` (32 bits) before addition. Intermediate nodes retain `ACC_WIDTH`; this width can represent the exact sum of eight `DATA_WIDTH` signed operands.

### 6.1 Saturation

The representable output range is:

```text
MAX =  2^(DATA_WIDTH-1) - 1
MIN = -2^(DATA_WIDTH-1)
```

When saturation happens:

```text
acc > MAX  -> output = MAX
acc < MIN  -> output = MIN
otherwise  -> output = acc[DATA_WIDTH-1:0]
```

There is no rounding step because the Mixer performs no scaling and discards no fractional bits.

---

## 7. Interface Description

### 7.1 Clock and reset

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `clk_i` | Input | 1 | Mixer core, stream, and APB clock. |
| `rst_n_i` | Input | 1 | Active-low reset; asynchronous assertion and synchronous deassertion to `clk_i`. |

### 7.2 Audio input streams

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `input_valid_i` | Input | `NUM_INPUTS` | Per-input sample-valid vector. |
| `input_ready_o` | Output | `NUM_INPUTS` | Per-input sample-ready vector. |
| `input_data_i` | Input | `NUM_INPUTS × DATA_WIDTH` | sample data of per input channel. |

### 7.3 Audio output streams

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `output_valid_o` | Output | `NUM_OUTPUTS` | Per-output result-valid vector. |
| `output_ready_i` | Input | `NUM_OUTPUTS` | Per-output result-ready vector. |
| `output_data_o` | Output | `NUM_OUTPUTS × DATA_WIDTH` | mixed result for each output. |

### 7.4 APB slave 
Standard APB-4 slave port for register configuration.

### 7.5 Interrupt

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `irq_o` | Output | 1 | Level interrupt: OR of enabled sticky interrupt status bits. |

---

## 8. Register Map

### 8.1 CTRL register 

| Bits | Name | Access | Description |
| ---: | --- | ---: | --- |
| `[0]` | `MIXER_EN` | RW |  Enable starting new mixing slots. |
| `[1]` | `FLUSH` | WO |  Write 1 to flush pipeline and all FIFOs; self-clearing. |
| `[2]` | `SOFT_RESET` | WO |  Write 1 for internal reset; self-clearing. |
| `[3]` | `COUNTER_CLEAR` | WO |  Write 1 to clear slot timeout counters. |
| `[31:4]` | Reserved | — |  Write zero; read zero. |

### 8.2 STATUS register

| Bits | Name | Description |
| ---: | --- | --- |
| `[0]` | `ACTIVE` | `EN=1`, active configuration valid, and at least one output enabled. |
| `[1]` | `IDLE` | No arithmetic slot is in flight. Output FIFOs may still contain data. |
| `[2]` | `FLUSH_BUSY` | FIFO and pipeline flush is in progress. |
| `[3]` | `INPUT_STARVED` | At least one required input FIFO is empty. |
| `[4]` | `OUTPUT_BLOCKED` | At least one enabled output FIFO is full. |
| `[5:11]` | `FSM_STATE` | Encoded internal state for debug. |
| `[31:12]` | Reserved | Read zero. |

### 8.3 Channel control registers

| Bits | Name | Description |
| ---: | --- | --- |
| `[7:0]` | `RX_ENABLE` | 8 input rx channel enable signals, each bit represent 1 rx channel enable control, for example: set bit0=1 enables input channel 0. |
| `[15:8]` | `SIGNED` | Each bit corresponds to one input channel, setting 1 means the channel inputs signed data, otherwise unsigned |
| `[31:16]` | Reserved | Read zero. |

### 8.4 Output channel control registers

| Bits | Name | Description |
| ---: | --- | --- |
| `[3:0]` | `TX_ENABLE` | 4 output tx channel enable signals, each bit represent 1 tx channel enable control, for example: set bit0=1 enables output channel 0. |
| `[7:4]` | `SATURATION` | Each bit corresponds to one output channel, setting 1 means the channel output addition is saturated |
| `[31:8]` | Reserved | Read zero. |

### 8.5 Output channel source select registers

| Bits | Name | Description |
| ---: | --- | --- |
| `[7:0]` | `TX_0_SRC` | For output channel 0, select which input channels to be mixed, each bit controls 1 input channel. |
| `[15:8]` | `TX_1_SRC` | For output channel 1, select which input channels to be mixed, each bit controls 1 input channel. |
| `[23:16]` | `TX_2_SRC` | For output channel 2, select which input channels to be mixed, each bit controls 1 input channel. |
| `[31:24]` | `TX_3_SRC` | For output channel 3, select which input channels to be mixed, each bit controls 1 input channel. |

### 8.7 Interrupt registers

| Bit | Name | Set condition |
| ---: | --- | --- |
| `[7:0]` | `INPUT_STARVE` | Scheduler first enters a wait caused by a required empty input. |
| `[11:8]` | `OUTPUT_BLOCKED` | Scheduler first enters a wait caused by an enabled full output FIFO. |
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
