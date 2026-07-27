# Audio Hub Digital Gain IP Hardware Design Description (HDD)

**Document version:** v1.0  
**Module name:** `audio_digital_gain`  
**Target subsystem:** Audio Hub  
**Data interface:** 32-bit `valid / ready / data` audio stream  
**Primary function:** Apply a programmable fixed-point gain independently to each logical audio slot while preserving stream ordering and frame alignment.

---

## Revision History

| Version | Date | Description |
|---|---|---|
| v1.0 | 2026-07-27 | Initial IP-level Digital Gain HDD aligned with the Audio Hub Merge architecture |

---

# 1. Introduction

The Audio Hub Digital Gain IP is a programmable PCM amplitude-processing endpoint. It receives one ordered 32-bit audio stream, identifies the logical slot of each transferred sample from the stream sequence, applies the active gain coefficient for that slot, and sends the processed sample back to the Audio Hub crossbar.

The IP supports:

- Signed 32-bit PCM input and output.
- One 32-bit sample per stream transfer.
- Up to eight logical audio slots by default.
- One independent gain coefficient per slot.
- Optional common-gain mode.
- Per-slot mute.
- Unity-gain bypass.
- Signed fixed-point multiplication.
- Selectable rounding or truncation.
- Selectable saturation or wrap behavior.
- Double-buffered gain configuration.
- Atomic coefficient update at a logical frame boundary.
- Standard ready/valid backpressure.
- Sticky error and saturation status.
- Interrupt generation and debug counters.
- Composition with Merge, Mixer, I2S/TDM, DMA adapter, and Audio Hub crossbar blocks.

The IP does **not** perform:

- Stream mixing or sample addition.
- Channel merge, split, or reorder.
- Sample-rate conversion.
- I2S/TDM serialization or deserialization.
- BCLK, WS, or frame-sync generation.
- Dynamic-range compression.
- Automatic gain control.
- Gain ramping in the v1.0 baseline.
- Cross-clock-domain synchronization.

---

# 2. Position in the Audio Hub

Digital Gain is both a crossbar sink and a crossbar source.

```text
 I2S RX / DMA / Merge / Mixer
              |
              v
      +----------------+
      | Audio Crossbar |
      +--------+-------+
               |
               v
      +----------------+
      | Digital Gain   |
      | slot tracking  |
      | multiply       |
      | round/saturate |
      +--------+-------+
               |
               v
      +----------------+
      | Audio Crossbar |
      +--+--------+----+
         |        |
         v        v
      I2S TX    DMA / other processing IP
```

Typical legal chains include:

```text
I2S RX -> Crossbar -> DG -> Crossbar -> I2S TX
Merge  -> Crossbar -> DG -> Crossbar -> I2S/TDM TX
Mixer  -> Crossbar -> DG -> Crossbar -> Merge
DG     -> Crossbar -> Mixer
DMA    -> Crossbar -> DG -> Crossbar -> I2S TX
```

The crossbar routes complete stream transactions. It does not modify sample data, infer slot position, or update the Digital Gain slot counter.

Unintended feedback loops, such as `DG output -> crossbar -> same DG input`, must be rejected by firmware or crossbar route-legality checking.

---

# 3. Main Use Cases

## 3.1 Mono volume control

```text
ACTIVE_SLOT_NUM = 1
GAIN[0]         = 0.5

input : A0, A1, A2, ...
output: 0.5A0, 0.5A1, 0.5A2, ...
```

## 3.2 Independent stereo gain after Merge

```text
Merge output: L0, R0, L1, R1, ...
GAIN[0] = 0.5
GAIN[1] = 0.25

DG output: 0.5L0, 0.25R0, 0.5L1, 0.25R1, ...
```

The DG slot sequence must match the upstream Merge sequence:

```text
slot0 = Left
slot1 = Right
```

## 3.3 Common gain for a TDM stream

```text
ACTIVE_SLOT_NUM = 4
COMMON_GAIN_EN  = 1
COMMON_GAIN     = 2.0

input : A0, B0, C0, D0, A1, B1, C1, D1, ...
output: 2A0, 2B0, 2C0, 2D0, 2A1, 2B1, 2C1, 2D1, ...
```

## 3.4 Per-slot mute

```text
ACTIVE_SLOT_NUM = 4
SLOT_MUTE       = 4'b0100

input : A0, B0, C0, D0, ...
output: A0', B0', 0, D0', ...
```

Muted samples still participate in the ready/valid handshake and still advance the logical slot counter. Muting must never delete a stream transfer.

## 3.5 Gain update during playback

Software writes shadow coefficients while the stream is running, then issues `GAIN_COMMIT`.

The active bank changes only at the next frame boundary:

```text
frame N:     all slots use old gain bank
frame N + 1: all slots use new gain bank
```

This prevents left/right or multi-channel coefficient tearing within one frame.

---

# 4. Design Assumptions

1. All datapath ports use the Audio Hub processing clock.
2. Input PCM is signed two's-complement.
3. One transfer contains one 32-bit sample.
4. Logical slot identity is implicit in successful transfer order.
5. The first sample after reset, flush, or enable is slot 0.
6. One logical frame contains `ACTIVE_SLOT_NUM` successful output transfers.
7. Input and output frame order are identical.
8. Upstream route or frame configuration does not change in the middle of an active frame.
9. Clock-domain crossing is completed before a stream reaches this IP.
10. The baseline implementation processes one sample per clock at full throughput.

---

# 5. Features

| Feature | Baseline support |
|---|---|
| Input/output sample width | 32-bit signed PCM |
| Maximum logical slots | 8, parameterized |
| Gain control | Independent per slot |
| Common-gain mode | Supported |
| Gain coefficient | Signed 32-bit Q7.24 |
| Unity gain | `0x0100_0000` |
| Zero gain | `0x0000_0000` |
| Negative gain / polarity inversion | Supported |
| Per-slot mute | Supported |
| Bypass | Supported |
| Rounding | Truncate or round-to-nearest, ties away from zero |
| Overflow | Saturate or wrap |
| Coefficient shadow bank | Supported |
| Frame-boundary commit | Supported |
| Immediate active write | Not supported while enabled |
| Gain ramp | Not included in v1.0 |
| Stream backpressure | Supported |
| Saturation reporting | Per-slot sticky flags and counters |
| Register interface | Decoded regbank configuration; APB-compatible register map |

---

# 6. Data and Coefficient Formats

## 6.1 Stream interface

```systemverilog
in_valid
in_ready
in_data[31:0]

out_valid
out_ready
out_data[31:0]
```

An input transfer occurs on:

```text
in_fire = in_valid && in_ready
```

An output transfer occurs on:

```text
out_fire = out_valid && out_ready
```

`in_data` and `out_data` are signed two's-complement PCM samples:

```text
minimum = -2^31     = 0x8000_0000
maximum =  2^31 - 1 = 0x7FFF_FFFF
```

## 6.2 Gain coefficient

The baseline coefficient is signed Q7.24:

```text
GAIN_W      = 32
GAIN_FRAC_W = 24
```

The real gain is:

```text
gain_real = signed(GAIN_COEF) / 2^24
```

Representative values:

| Real gain | Coefficient |
|---:|---:|
| `-1.0` | `0xFF00_0000` |
| `0.0` | `0x0000_0000` |
| `0.25` | `0x0040_0000` |
| `0.5` | `0x0080_0000` |
| `1.0` | `0x0100_0000` |
| `2.0` | `0x0200_0000` |
| `4.0` | `0x0400_0000` |

The representable coefficient range is approximately:

```text
-128.0 to +127.99999994
```

Software that uses decibels shall calculate:

```text
gain_linear = 10^(gain_dB / 20)
GAIN_COEF   = round(gain_linear * 2^24)
```

The hardware stores and applies only the linear fixed-point coefficient.

## 6.3 Full-precision product

```text
sample:  signed 32 bits
gain:    signed 32 bits
product: signed 64 bits
```

```systemverilog
product_full = $signed(sample_in) * $signed(gain_coef);
```

After rounding or truncation, the product is arithmetically shifted right by `GAIN_FRAC_W`.

---

# 7. Parameterization

```systemverilog
parameter int unsigned SLOT_NUM_MAX      = 8;
parameter int unsigned SAMPLE_W          = 32;
parameter int unsigned GAIN_W            = 32;
parameter int unsigned GAIN_FRAC_W       = 24;
parameter int unsigned OUT_FIFO_DEPTH    = 2;
parameter int unsigned SAT_CNT_W         = 32;
parameter int unsigned SAMPLE_CNT_W      = 32;
parameter bit          SUPPORT_NEG_GAIN  = 1'b1;
parameter bit          SUPPORT_ROUNDING  = 1'b1;
parameter bit          SUPPORT_SAT       = 1'b1;
parameter bit          SUPPORT_SHADOW    = 1'b1;

localparam int unsigned SLOT_ID_W =
    (SLOT_NUM_MAX <= 1) ? 1 : $clog2(SLOT_NUM_MAX);
```

| Parameter | Meaning |
|---|---|
| `SLOT_NUM_MAX` | Maximum logical slots in the input sequence |
| `SAMPLE_W` | PCM sample width; baseline is 32 |
| `GAIN_W` | Gain coefficient width; baseline is 32 |
| `GAIN_FRAC_W` | Fractional coefficient bits; baseline is 24 |
| `OUT_FIFO_DEPTH` | Output elastic-buffer depth |
| `SAT_CNT_W` | Saturation-counter width |
| `SAMPLE_CNT_W` | Sample/frame-counter width |
| `SUPPORT_NEG_GAIN` | Negative coefficients are implemented |
| `SUPPORT_ROUNDING` | Rounding logic is implemented |
| `SUPPORT_SAT` | Saturation logic is implemented |
| `SUPPORT_SHADOW` | Shadow/active coefficient banks are implemented |

All slot-dependent masks, arrays, registers, and counters must derive from `SLOT_NUM_MAX`.

---

# 8. Top-Level Interface

```systemverilog
module audio_digital_gain #(
    parameter int unsigned SLOT_NUM_MAX   = 8,
    parameter int unsigned SAMPLE_W       = 32,
    parameter int unsigned GAIN_W         = 32,
    parameter int unsigned GAIN_FRAC_W    = 24,
    parameter int unsigned OUT_FIFO_DEPTH = 2
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         in_valid,
    output logic                         in_ready,
    input  logic [SAMPLE_W-1:0]          in_data,

    output logic                         out_valid,
    input  logic                         out_ready,
    output logic [SAMPLE_W-1:0]          out_data,

    input  digital_gain_cfg_t            cfg,
    output digital_gain_status_t         status,
    output logic                         irq
);
```

The register transport may be APB, AHB, AXI-Lite, or a central Audio Hub regbank. The datapath consumes a decoded and clock-synchronous configuration structure.

## 8.1 Port List

| Port | Direction | Width | Description |
|---|---|---:|---|
| `clk` | Input | 1 | Audio Hub processing clock |
| `rst_n` | Input | 1 | Active-low reset; deassert synchronously |
| `in_valid` | Input | 1 | Input sample valid |
| `in_ready` | Output | 1 | Input sample ready |
| `in_data` | Input | `SAMPLE_W` | Signed PCM input sample |
| `out_valid` | Output | 1 | Output sample valid |
| `out_ready` | Input | 1 | Downstream ready |
| `out_data` | Output | `SAMPLE_W` | Processed signed PCM sample |
| `cfg` | Input | implementation | Decoded active/shadow configuration |
| `status` | Output | implementation | Status and debug information |
| `irq` | Output | 1 | Combined interrupt |

No slot ID sideband is required in the baseline interface. Slot identity is derived from the internal slot counter.

---

# 9. Internal Architecture

```text
                    +----------------------+
in_valid/data ----->| Input accept /       |
                    | slot tag capture     |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Gain bank select     |
                    | common/per-slot/mute |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Signed multiplier    |
                    | 32 x 32 -> 64        |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Round / shift        |
                    | saturate or wrap     |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Elastic output FIFO  |----> out_valid/data
                    +----------------------+

       shadow gain bank ---- commit ----> active gain bank
                                     frame-boundary controlled
```

## 9.1 Active configuration snapshot

When `DG_EN` changes from 0 to 1, the implementation snapshots:

- `ACTIVE_SLOT_NUM`
- Processing mode bits
- Common-gain selection
- Active gain bank
- Active mute mask

Fields that affect slot sequencing or datapath interpretation must remain stable until disable, flush, or an allowed frame-boundary commit.

## 9.2 Slot tracker

The slot tracker represents the slot associated with the next accepted input sample:

```text
0, 1, ... ACTIVE_SLOT_NUM-1, 0, 1, ...
```

The slot ID is captured with the sample when the sample enters the processing pipeline.

## 9.3 Gain selection

```systemverilog
if (slot_mute[slot_id])
    selected_gain = '0;
else if (common_gain_en)
    selected_gain = active_gain[0];
else
    selected_gain = active_gain[slot_id];
```

Bypass takes precedence over gain multiplication:

```systemverilog
if (bypass)
    result = sample_in;
else
    result = gain_process(sample_in, selected_gain);
```

## 9.4 Pipeline metadata

The following metadata must remain aligned with each sample through all pipeline stages:

- Slot ID.
- Bypass decision.
- Mute decision.
- Saturation event.
- Frame-end indication.

---

# 10. Datapath Operation

## 10.1 Multiplication

```systemverilog
logic signed [63:0] product_full;

product_full =
    $signed(sample_q) *
    $signed(selected_gain_q);
```

## 10.2 Truncation mode

```systemverilog
scaled_full = product_full >>> GAIN_FRAC_W;
```

Arithmetic right shift is mandatory.

## 10.3 Rounding mode

The baseline rounding mode is round-to-nearest with midpoint ties away from zero.

Let:

```text
ROUND_BIAS = 2^(GAIN_FRAC_W - 1)
```

Because an arithmetic right shift rounds a negative two's-complement value
toward negative infinity, the positive and negative biases are intentionally
different:

```text
positive product: adjusted = product + ROUND_BIAS
negative product: adjusted = product + ROUND_BIAS - 1
scaled:            adjusted >>> GAIN_FRAC_W
```

The RTL must be reviewed for exact negative-number behavior. Verification shall use a bit-accurate reference model rather than relying on language-level integer division.

## 10.4 Overflow detection

After scaling, overflow occurs when the result cannot be represented by signed `SAMPLE_W` bits:

```text
MAX_PCM =  2^(SAMPLE_W-1) - 1
MIN_PCM = -2^(SAMPLE_W-1)
```

## 10.5 Saturation mode

```text
scaled > MAX_PCM -> output = MAX_PCM
scaled < MIN_PCM -> output = MIN_PCM
otherwise        -> output = scaled[SAMPLE_W-1:0]
```

## 10.6 Wrap mode

When saturation is disabled:

```text
output = scaled[SAMPLE_W-1:0]
```

An overflow event must still set saturation/overflow status and increment the corresponding counter. `SAT_EN` controls output clipping, not event detection.

## 10.7 Mute behavior

Mute forces output data to zero:

```text
out_sample = 0
```

The muted transaction is still transferred normally. Slot and frame counters advance exactly as they do for a non-muted sample.

## 10.8 Bypass behavior

In bypass mode:

- Input sample bits pass unchanged to the output.
- No multiplication, rounding, or saturation is applied.
- Slot and frame counters remain active.
- Frame-boundary commit remains functional.
- Backpressure behavior is unchanged.

Bypass is not a combinational short circuit from input to output. The registered output path is retained.

---

# 11. Stream Control and Backpressure

## 11.1 Acceptance rule

```systemverilog
in_ready = cfg_dg_en &&
           cfg_valid &&
           pipeline_can_accept &&
           !flush_active &&
           !fatal_error;
```

```text
sample_accept = in_valid && in_ready
```

## 11.2 Output rule

```systemverilog
out_valid = !out_fifo_empty;
out_data  = out_fifo_rdata;
out_pop   = out_valid && out_ready;
```

`out_valid` and `out_data` must remain stable while:

```text
out_valid == 1 && out_ready == 0
```

## 11.3 Slot-counter rule

The input-side slot counter advances only when an input sample is accepted:

```systemverilog
if (sample_accept) begin
    if (slot_cnt == active_slot_num - 1)
        slot_cnt <= '0;
    else
        slot_cnt <= slot_cnt + 1'b1;
end
```

The accepted slot ID is carried with the sample. It must not be reconstructed later from output timing because pipeline latency and backpressure can differ.

## 11.4 Frame completion

Input frame acceptance:

```text
in_frame_accept = sample_accept &&
                  slot_cnt == active_slot_num - 1
```

Output frame completion:

```text
out_frame_done = out_fire &&
                 out_slot_id == active_slot_num - 1
```

The output frame counter increments on `out_frame_done`.

## 11.5 Full-throughput target

With a pipelined multiplier and available output storage:

```text
one accepted sample per clock
one produced sample per clock
```

The pipeline may contain multiple samples from adjacent frames. Each sample must carry its own slot and bank metadata.

## 11.6 Backpressure propagation

```text
downstream stall
-> output FIFO fills
-> processing pipeline stalls
-> in_ready deasserts
```

There shall be no long combinational path from `out_ready` directly to `in_ready`. An elastic output stage is required.

---

# 12. Gain-Bank Update Mechanism

## 12.1 Shadow and active banks

Two logical coefficient banks are provided:

```text
GAIN_SHADOW[slot]
GAIN_ACTIVE[slot]
```

Software writes only the shadow bank while `DG_EN=1`. The multiplier reads only the active bank.

The same policy applies to:

- Per-slot gain coefficients.
- Slot mute mask.
- Common gain selection when marked as synchronized.

## 12.2 Commit request

Software issues a self-clearing `GAIN_COMMIT` command after programming the shadow bank.

```text
GAIN_COMMIT write
-> COMMIT_PENDING = 1
-> wait for safe frame boundary
-> copy/swap shadow bank into active bank
-> COMMIT_PENDING = 0
-> COMMIT_DONE sticky status = 1
```

## 12.3 Safe commit point

The preferred safe point is after accepting the final slot of the current input frame and before accepting slot 0 of the next frame.

If the pipeline captures the coefficient value with each accepted sample, already accepted samples may complete using the old bank while the next frame uses the new bank.

If `DG_EN=0` or the block is idle, commit occurs immediately.

## 12.4 Commit under output stall

An output stall does not prevent a commit if:

- The final input sample of the old frame has already been accepted.
- Every old-frame sample carries its captured coefficient or bank tag.
- The next accepted slot-0 sample will use the new bank.

If the implementation reads active coefficients after acceptance, it must instead drain the processing pipeline before swapping banks.

## 12.5 Multiple commit requests

The baseline permits only one pending commit.

If software issues another `GAIN_COMMIT` while `COMMIT_PENDING=1`:

- Ignore the new command.
- Set `COMMIT_OVERWRITE_ERR`.
- Raise an interrupt if enabled.

## 12.6 Active configuration restrictions

While enabled, software shall not directly change:

- `ACTIVE_SLOT_NUM`
- Coefficient numeric format
- Pipeline mode
- Slot sequence interpretation

Changing `ACTIVE_SLOT_NUM` requires disable/idle or flush because it changes frame tracking.

---

# 13. State Machine

The control FSM is:

```text
IDLE
  | DG_EN && CFG_VALID
  v
RUN
  | FLUSH or SOFT_RESET
  v
FLUSH
  | clear complete
  v
IDLE

RUN
  | fatal configuration/protocol error
  v
ERROR
  | FLUSH or SOFT_RESET
  v
IDLE
```

## 13.1 `IDLE`

- `in_ready=0`.
- No new sample is accepted.
- Slot counter is 0.
- Output pipeline is empty.
- A pending commit may complete immediately.

## 13.2 `RUN`

- Accept and process stream samples.
- Track logical slot and frame position.
- Execute a pending commit at a frame boundary.
- Propagate backpressure through the elastic pipeline.

## 13.3 `FLUSH`

- Stop input acceptance.
- Invalidate all pipeline and output FIFO entries.
- Reset slot counter to 0.
- Clear partial-frame state.
- Return to `IDLE`.

Flush discards buffered samples and therefore breaks the active stream sequence. The upstream and downstream route must be stopped or flushed consistently.

## 13.4 `ERROR`

- Stop input acceptance.
- Preserve diagnostic status.
- Do not emit new processed samples.
- Recover only through soft reset or flush.

Normal numerical saturation is not a fatal error and does not enter `ERROR`.

## 13.5 Datapath pipeline control

Multiplier pipeline valid bits may use elastic stage control rather than separate global FSM states. A sample advances only when the next stage can accept it.

---

# 14. Clocking, Reset, and Reconfiguration

## 14.1 Clocking

All stream and configuration signals operate in `clk`.

I2S/TDM controllers shall complete BCLK/WS-domain crossing before sending data into the Audio Hub processing crossbar.

## 14.2 Hardware reset

Hardware reset shall:

- Enter `IDLE`.
- Clear pipeline and output valid state.
- Set slot counter to 0.
- Clear active and shadow coefficient banks to unity gain.
- Clear mute masks.
- Clear counters and sticky status.
- Clear pending commit state.
- Deassert `irq`.

## 14.3 Soft reset

Soft reset shall:

- Stop input acceptance.
- Clear the pipeline and output FIFO.
- Reset slot/frame tracking.
- Clear pending commit state.
- Return to `IDLE`.
- Preserve programmed shadow coefficients unless the implementation specification explicitly chooses otherwise.

## 14.4 Flush

Flush clears buffered datapath state and resets frame tracking while preserving gain configuration.

## 14.5 Safe programming sequence

Initial configuration:

```text
1. Clear DG_EN.
2. Wait for IDLE or issue FLUSH.
3. Program ACTIVE_SLOT_NUM.
4. Program mode, rounding, and saturation control.
5. Program shadow gain coefficients and mute mask.
6. Issue GAIN_COMMIT; it completes immediately while idle.
7. Clear stale interrupt status.
8. Configure the crossbar route.
9. Set DG_EN.
```

Runtime gain update:

```text
1. Write all required shadow coefficients.
2. Write shadow mute mask if required.
3. Issue GAIN_COMMIT.
4. Poll COMMIT_PENDING or wait for COMMIT_DONE interrupt.
```

Route or slot-count update:

```text
1. Stop the source.
2. Clear DG_EN.
3. Wait for IDLE or issue FLUSH.
4. Update route and ACTIVE_SLOT_NUM.
5. Reset dependent downstream slot counters.
6. Re-enable the processing chain.
```

---

# 15. Error and Corner-Case Behavior

## 15.1 Configuration errors

Configuration is invalid when:

- `DG_EN=1` and `ACTIVE_SLOT_NUM=0`.
- `ACTIVE_SLOT_NUM > SLOT_NUM_MAX`.
- An unsupported rounding mode is selected.
- Saturation is enabled when saturation hardware is not implemented.
- Negative gain is written when negative gain is unsupported.
- A sequence-affecting field is written while active.

A fatal configuration error prevents sample acceptance.

## 15.2 Input/output overflow

Correct ready/valid behavior prevents overflow. A detected write to a full internal FIFO or overwrite of a valid pipeline stage indicates an implementation or protocol error.

## 15.3 Numerical overflow

Numerical overflow:

- Sets per-slot sticky saturation status.
- Increments the per-slot saturation counter.
- Optionally raises an interrupt.
- Produces saturated or wrapped output according to `SAT_EN`.
- Does not stop the stream.

## 15.4 Minimum PCM multiplied by negative unity

```text
0x8000_0000 * -1.0 = +2147483648
```

This is outside signed 32-bit range.

With saturation enabled:

```text
output = 0x7FFF_FFFF
```

With saturation disabled:

```text
output = 0x8000_0000
```

The saturation event is reported in both modes.

## 15.5 Zero and unity gain

- Zero gain produces exact zero.
- Positive unity gain produces bit-exact input in truncation mode.
- Bypass always produces bit-exact input.

## 15.6 Disabled slot

The Digital Gain IP does not delete inactive slots. `ACTIVE_SLOT_NUM` defines the actual cyclic stream length. Within that length, every transfer is a valid logical slot.

## 15.7 Mid-frame enable or route change

The first accepted sample after enable is interpreted as slot 0. Therefore the source must also begin at slot 0. Enabling DG in the middle of an upstream frame is illegal system behavior and may cause persistent channel-to-gain misalignment.

## 15.8 Flush while stalled

Flush invalidates any held output sample. Software must treat the current logical frame as discarded and re-establish frame alignment across the complete route.

---

# 16. Performance Targets

| Metric | Target |
|---|---|
| Sustained throughput | 1 sample/clock |
| Initiation interval | 1 clock |
| Datapath latency | Implementation-dependent, typically 2–5 clocks |
| Backpressure | Lossless while protocol is obeyed |
| Frame throughput | `clk / ACTIVE_SLOT_NUM` frames per second at full rate |
| Coefficient commit | Next input-frame boundary |

The multiplier may be inferred or instantiated using an approved arithmetic macro. Pipeline depth may change for timing closure without changing functional behavior.

For lower-throughput or area-constrained implementations, a multi-cycle multiplier is allowed only if `in_ready` correctly throttles the source and the advertised capability register reports the reduced initiation interval.

---

# 17. Register Map

All registers are 32 bits. Offsets are relative to the Digital Gain IP base address.

## 17.1 Register Summary

| Offset | Register | Access | Description |
|---:|---|---|---|
| `0x000` | `DG_ID` | RO | IP identifier and revision |
| `0x004` | `DG_CAP` | RO | Hardware capabilities |
| `0x008` | `DG_CTRL` | RW | Enable, bypass, reset, flush |
| `0x00C` | `DG_SLOT_CFG` | RW | Active slot count and common-gain mode |
| `0x010` | `DG_PROC_CFG` | RW | Rounding and saturation controls |
| `0x014` | `DG_UPDATE` | RW/WO | Shadow-bank commit control |
| `0x018` | `DG_STATUS` | RO | Current operating status |
| `0x01C` | `DG_ERR_STATUS` | W1C | Sticky error status |
| `0x020` | `DG_INT_EN` | RW | Interrupt enables |
| `0x024` | `DG_INT_STATUS` | W1C | Interrupt status |
| `0x028` | `DG_SLOT_MUTE_SHADOW` | RW | Shadow per-slot mute mask |
| `0x02C` | `DG_SLOT_MUTE_ACTIVE` | RO | Active per-slot mute mask |
| `0x030` | `DG_SAMPLE_CNT` | RO | Completed output sample count |
| `0x034` | `DG_FRAME_CNT` | RO | Completed output frame count |
| `0x038` | `DG_STALL_CNT` | RO | Output stall-cycle count |
| `0x03C` | `DG_DEBUG_CTRL` | RW | Counter clear/debug control |
| `0x040`–`0x05C` | `DG_GAIN_SHADOW0..7` | RW | Shadow slot gain coefficients |
| `0x080`–`0x09C` | `DG_GAIN_ACTIVE0..7` | RO | Active slot gain coefficients |
| `0x0C0`–`0x0DC` | `DG_SAT_COUNT0..7` | RO | Per-slot saturation counters |

Registers above slot `SLOT_NUM_MAX-1` may be omitted or read as zero.

---

# 18. Register Details

## 18.1 `DG_ID` — `0x000`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[15:0]` | `IP_ID` | RO | implementation | Digital Gain IP identifier |
| `[23:16]` | `MINOR_REV` | RO | `0` | Minor revision |
| `[31:24]` | `MAJOR_REV` | RO | `1` | Major revision |

## 18.2 `DG_CAP` — `0x004`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[7:0]` | `SLOT_NUM_MAX` | RO | parameter | Maximum logical slots |
| `[13:8]` | `SAMPLE_W` | RO | `32` | PCM width |
| `[19:14]` | `GAIN_W` | RO | `32` | Gain coefficient width |
| `[24:20]` | `GAIN_FRAC_W` | RO | `24` | Fractional coefficient bits |
| `[25]` | `NEG_GAIN_SUP` | RO | parameter | Negative gain support |
| `[26]` | `ROUND_SUP` | RO | parameter | Rounding support |
| `[27]` | `SAT_SUP` | RO | parameter | Saturation support |
| `[28]` | `SHADOW_SUP` | RO | parameter | Shadow-bank support |
| `[31:29]` | `RSVD` | RO | 0 | Reserved |

## 18.3 `DG_CTRL` — `0x008`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `DG_EN` | RW | 0 | Enable Digital Gain |
| `[1]` | `BYPASS` | RW | 0 | Registered bit-exact bypass |
| `[2]` | `SOFT_RESET` | WO/SC | 0 | Soft-reset command |
| `[3]` | `FLUSH` | WO/SC | 0 | Flush datapath command |
| `[4]` | `CFG_LOCK` | RW | 1 | Reject illegal active configuration writes |
| `[5]` | `HALT_ON_CFG_ERR` | RW | 1 | Enter ERROR on fatal configuration error |
| `[31:6]` | `RSVD` | RW | 0 | Reserved |

`SOFT_RESET` and `FLUSH` are write-one command bits and self-clear.

## 18.4 `DG_SLOT_CFG` — `0x00C`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[7:0]` | `ACTIVE_SLOT_NUM` | RW | 1 | Logical samples per frame |
| `[8]` | `COMMON_GAIN_EN` | RW | 0 | Use gain slot 0 for all slots |
| `[9]` | `FRAME_COUNTER_EN` | RW | 1 | Enable frame counter |
| `[31:10]` | `RSVD` | RW | 0 | Reserved |

`ACTIVE_SLOT_NUM` may change only while disabled and idle.

## 18.5 `DG_PROC_CFG` — `0x010`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `SAT_EN` | RW | 1 | Clip numerical overflow to PCM min/max |
| `[2:1]` | `ROUND_MODE` | RW | 1 | `00` truncate, `01` nearest/ties away, others reserved |
| `[3]` | `SAT_STATUS_EN` | RW | 1 | Enable saturation event tracking |
| `[4]` | `MUTE_BEFORE_MULT` | RO | 1 | Muted slot suppresses multiply activity |
| `[31:5]` | `RSVD` | RW | 0 | Reserved |

## 18.6 `DG_UPDATE` — `0x014`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `GAIN_COMMIT` | WO/SC | 0 | Request shadow-to-active commit |
| `[1]` | `COMMIT_PENDING` | RO | 0 | Commit waiting for safe boundary |
| `[2]` | `COMMIT_DONE` | W1C | 0 | Commit completed |
| `[3]` | `SHADOW_DIRTY` | RO | 0 | Shadow bank differs from last committed bank |
| `[7:4]` | `ACTIVE_BANK_TAG` | RO | 0 | Debug generation tag; increments on commit |
| `[31:8]` | `RSVD` | RO | 0 | Reserved |

## 18.7 `DG_STATUS` — `0x018`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `IDLE` | RO | 1 | Block is idle |
| `[1]` | `BUSY` | RO | 0 | Block is enabled/processing |
| `[2]` | `IN_STALL` | RO | 0 | Input valid while input not ready |
| `[3]` | `OUT_STALL` | RO | 0 | Output valid while output not ready |
| `[4]` | `FLUSH_ACTIVE` | RO | 0 | Flush in progress |
| `[5]` | `ERROR_STATE` | RO | 0 | FSM is in ERROR |
| `[6]` | `CFG_VALID` | RO | 1 | Current configuration is valid |
| `[7]` | `PIPE_NONEMPTY` | RO | 0 | Pipeline/output FIFO contains data |
| `[15:8]` | `NEXT_IN_SLOT` | RO | 0 | Slot ID assigned to next accepted input |
| `[23:16]` | `LAST_OUT_SLOT` | RO | 0 | Slot ID of most recent output transfer |
| `[31:24]` | `PIPE_LEVEL` | RO | 0 | Implementation-defined pipeline occupancy |

## 18.8 `DG_ERR_STATUS` — `0x01C`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `CFG_ERR` | W1C | 0 | Invalid configuration |
| `[1]` | `ACTIVE_CFG_WRITE` | W1C | 0 | Illegal active write |
| `[2]` | `COMMIT_OVERWRITE_ERR` | W1C | 0 | Commit issued while one is pending |
| `[3]` | `PIPE_OVERFLOW` | W1C | 0 | Internal valid entry overwritten |
| `[4]` | `PIPE_UNDERFLOW` | W1C | 0 | Illegal empty pop |
| `[5]` | `PROTOCOL_ERR` | W1C | 0 | Stream protocol violation detected |
| `[6]` | `FRAME_SYNC_ERR` | W1C | 0 | Internal slot/frame tracking error |
| `[15:8]` | `SAT_SLOT` | W1C | 0 | Per-slot numerical overflow sticky flags |
| `[31:16]` | `RSVD` | W1C | 0 | Reserved |

For `SLOT_NUM_MAX < 8`, unused `SAT_SLOT` bits read as zero.

## 18.9 `DG_INT_EN` — `0x020`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[6:0]` | `ERR_INT_EN` | RW | 0 | Enable corresponding error interrupts |
| `[7]` | `COMMIT_DONE_INT_EN` | RW | 0 | Enable commit-complete interrupt |
| `[15:8]` | `SAT_INT_EN` | RW | 0 | Enable per-slot saturation interrupts |
| `[31:16]` | `RSVD` | RW | 0 | Reserved |

## 18.10 `DG_INT_STATUS` — `0x024`

Interrupt status is W1C and follows the layout of `DG_INT_EN`.

```systemverilog
irq = |(dg_int_status & dg_int_en);
```

## 18.11 `DG_SLOT_MUTE_SHADOW` — `0x028`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[SLOT_NUM_MAX-1:0]` | `MUTE_SHADOW` | RW | 0 | Shadow slot mute mask |
| Remaining | `RSVD` | RW | 0 | Reserved |

## 18.12 `DG_SLOT_MUTE_ACTIVE` — `0x02C`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[SLOT_NUM_MAX-1:0]` | `MUTE_ACTIVE` | RO | 0 | Active slot mute mask |
| Remaining | `RSVD` | RO | 0 | Reserved |

## 18.13 Counter registers

- `DG_SAMPLE_CNT` increments on every `out_valid && out_ready`.
- `DG_FRAME_CNT` increments when the final logical slot transfers.
- `DG_STALL_CNT` increments every cycle with `out_valid && !out_ready`.
- `DG_SAT_COUNTn` increments when slot `n` produces an out-of-range scaled result.
- Counters saturate at all ones rather than wrapping.

## 18.14 `DG_DEBUG_CTRL` — `0x03C`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `CLR_SAMPLE_CNT` | WO/SC | 0 | Clear sample counter |
| `[1]` | `CLR_FRAME_CNT` | WO/SC | 0 | Clear frame counter |
| `[2]` | `CLR_STALL_CNT` | WO/SC | 0 | Clear stall counter |
| `[3]` | `CLR_SAT_CNT_ALL` | WO/SC | 0 | Clear all saturation counters |
| `[31:4]` | `RSVD` | RW | 0 | Reserved |

## 18.15 Gain registers

```text
DG_GAIN_SHADOWn = signed Q7.24 coefficient for logical slot n
DG_GAIN_ACTIVEn = active read-only coefficient for logical slot n
```

Reset value:

```text
0x0100_0000 = +1.0
```

Shadow writes are always allowed unless a register-bus access policy says otherwise. Active registers are changed only by reset or a successful commit.

---

# 19. Register Programming Examples

## 19.1 Stereo attenuation

Target:

```text
Left  = 0.5
Right = 0.25
```

Programming:

```text
DG_EN                = 0
ACTIVE_SLOT_NUM      = 2
COMMON_GAIN_EN       = 0
DG_GAIN_SHADOW0      = 0x0080_0000
DG_GAIN_SHADOW1      = 0x0040_0000
GAIN_COMMIT          = 1
SAT_EN               = 1
ROUND_MODE           = 1
DG_EN                = 1
```

## 19.2 Four-slot common +6.02 dB gain

```text
ACTIVE_SLOT_NUM      = 4
COMMON_GAIN_EN       = 1
DG_GAIN_SHADOW0      = 0x0200_0000
GAIN_COMMIT          = 1
```

## 19.3 Mute slot 2

```text
DG_SLOT_MUTE_SHADOW  = 0x0000_0004
GAIN_COMMIT          = 1
```

## 19.4 Polarity inversion

```text
DG_GAIN_SHADOW0      = 0xFF00_0000
GAIN_COMMIT          = 1
```

This applies a gain of `-1.0`.

## 19.5 Runtime stereo update

```text
// Stream remains active
write DG_GAIN_SHADOW0 = new_left_gain
write DG_GAIN_SHADOW1 = new_right_gain
write DG_UPDATE.GAIN_COMMIT = 1

wait until:
DG_UPDATE.COMMIT_PENDING == 0
or COMMIT_DONE interrupt
```

Both channels change gain on the same logical frame boundary.

---

# 20. Numerical Examples

## 20.1 Unity gain

```text
input        = 0x1234_5678
gain         = 0x0100_0000
output       = 0x1234_5678
```

## 20.2 Half gain

```text
input        = 0x4000_0000
gain         = 0x0080_0000
scaled       = 0x2000_0000
output       = 0x2000_0000
```

## 20.3 Positive saturation

```text
input        = 0x6000_0000
gain         = 0x0200_0000
ideal result = 0xC000_0000 as an unsigned magnitude representation
signed value = +3221225472, outside 32-bit signed range

SAT_EN = 1 -> output = 0x7FFF_FFFF
SAT_EN = 0 -> output = 0xC000_0000
```

The corresponding slot saturation flag and counter update in both modes.

## 20.4 Negative saturation

```text
input        = 0xA000_0000  // -1610612736
gain         = 0x0200_0000  // 2.0
ideal result = -3221225472

SAT_EN = 1 -> output = 0x8000_0000
SAT_EN = 0 -> output = 0x4000_0000
```

## 20.5 Negative unity corner case

```text
input        = 0x8000_0000
gain         = 0xFF00_0000
ideal result = +2147483648

SAT_EN = 1 -> output = 0x7FFF_FFFF
SAT_EN = 0 -> output = 0x8000_0000
```

---

# 21. RTL Pseudocode

## 21.1 Input acceptance and slot capture

```systemverilog
sample_accept = in_valid && in_ready;

if (sample_accept) begin
    pipe_valid_q <= 1'b1;
    pipe_data_q  <= in_data;
    pipe_slot_q  <= slot_cnt;

    if (slot_cnt == active_slot_num - 1)
        slot_cnt <= '0;
    else
        slot_cnt <= slot_cnt + 1'b1;
end
```

## 21.2 Gain selection

```systemverilog
if (active_mute[pipe_slot_q])
    gain_sel = '0;
else if (common_gain_en)
    gain_sel = active_gain[0];
else
    gain_sel = active_gain[pipe_slot_q];
```

## 21.3 Multiply and scale

```systemverilog
product_full = $signed(pipe_data_q) * $signed(gain_sel);

if (round_mode == ROUND_NEAREST_AWAY) begin
    if (product_full >= 0)
        product_adjusted = product_full + ROUND_BIAS;
    else
        product_adjusted = product_full + ROUND_BIAS - 1;
end else begin
    product_adjusted = product_full;
end

scaled_full = product_adjusted >>> GAIN_FRAC_W;
```

## 21.4 Saturation

```systemverilog
overflow_hi = scaled_full > PCM_MAX;
overflow_lo = scaled_full < PCM_MIN;

if (sat_en && overflow_hi)
    result = PCM_MAX;
else if (sat_en && overflow_lo)
    result = PCM_MIN;
else
    result = scaled_full[SAMPLE_W-1:0];
```

## 21.5 Output holding

```systemverilog
out_valid = out_valid_q;
out_data  = out_data_q;

out_stage_ready = !out_valid_q || out_ready;

if (out_stage_ready) begin
    out_valid_q <= result_valid;
    if (result_valid) begin
        out_data_q <= result;
        out_slot_q <= result_slot;
    end
end
```

## 21.6 Frame-boundary commit

```systemverilog
input_frame_end =
    sample_accept &&
    (slot_cnt == active_slot_num - 1);

commit_safe =
    !dg_en ||
    idle ||
    input_frame_end;

if (commit_pending && commit_safe) begin
    active_gain       <= shadow_gain;
    active_mute       <= shadow_mute;
    active_bank_tag   <= active_bank_tag + 1'b1;
    commit_pending    <= 1'b0;
    commit_done       <= 1'b1;
end
```

The real implementation must ensure the just-accepted final old-frame sample has already captured its old coefficient before active-bank replacement.

---

# 22. Verification Plan

## 22.1 Functional tests

Verification shall cover:

- Mono, stereo, four-slot, and maximum-slot configurations.
- Zero, fractional, unity, greater-than-unity, and negative gain.
- Common-gain and per-slot gain modes.
- Per-slot mute.
- Bypass.
- Truncation and supported rounding modes.
- Positive and negative saturation.
- Wrap behavior with saturation disabled.
- Minimum and maximum PCM corner cases.
- Random coefficients and samples against a bit-accurate model.
- Continuous one-sample-per-clock traffic.
- Random input gaps.
- Long random output backpressure.
- Reset, soft reset, and flush in every pipeline condition.
- Commit while idle.
- Commit during an active frame.
- Commit coincident with the final frame sample.
- Commit while output is stalled.
- Illegal second commit while pending.
- Active illegal writes.
- Counter saturation.
- Interrupt mask and W1C behavior.

## 22.2 Scoreboard model

For each accepted input:

```text
slot = accepted_sample_count % ACTIVE_SLOT_NUM
gain = MUTE[slot] ? 0 :
       COMMON_GAIN_EN ? ACTIVE_GAIN[0] :
                        ACTIVE_GAIN[slot]

expected = quantize_and_saturate(input * gain)
```

The model must snapshot the active coefficient generation for every accepted sample.

## 22.3 Required assertions

- No pipeline/FIFO write while full.
- No pop while empty.
- `out_data` remains stable while `out_valid && !out_ready`.
- Input slot counter changes only on `in_valid && in_ready`.
- Output frame counter changes only on final-slot output handshake.
- Slot counter resets on reset and flush.
- Output samples preserve input order.
- Bypass output is bit-exact.
- Muted slots produce zero without removing a transfer.
- Active gain bank changes only at a legal commit point.
- No frame contains samples captured from two coefficient generations.
- A pending commit is not silently overwritten.
- Numerical overflow is reported independently of `SAT_EN`.
- No sample is accepted with invalid configuration.

## 22.4 Formal properties

Recommended formal checks:

- Accepted sample count minus completed sample count equals pipeline occupancy.
- Every accepted sample eventually appears at the output under fair `out_ready`.
- No duplication or loss without reset/flush.
- Slot order is cyclic and monotonic.
- A bank tag is constant for all samples of a logical frame.

---

# 23. Synthesis, Timing, and Low-Power Considerations

1. Use a pipelined signed multiplier suitable for the target library.
2. Register the crossbar-facing output.
3. Insert an elastic stage after the multiplier/quantizer.
4. Do not create a direct long `out_ready -> in_ready` path.
5. Keep coefficient RAM/register read timing compatible with one sample per clock.
6. For eight coefficients, flops are generally simpler than SRAM.
7. Capture coefficient and slot metadata before a bank swap.
8. Clock-gate the multiplier with an approved ICG when no valid sample is present.
9. Suppress multiplier toggling for bypass and mute where the implementation permits.
10. Keep reset deassertion synchronous.
11. Pipeline 32x32 multiplication and saturation compare paths as required by STA.
12. Constrain multiplier, coefficient-select mux, and output paths explicitly.
13. Avoid asynchronous control signals in the datapath.
14. Use scan-safe reset and clock-gating structures.
15. Do not infer latches in gain-bank or pipeline control logic.

The coefficient-bank commit may be implemented as:

- Copying shadow flops into active flops at the boundary; or
- Swapping an active-bank select bit when two complete banks are implemented.

A bank-select swap is preferred for clean atomic timing and lower commit fanout.

---

# 24. Recommended Baseline Implementation

```text
SLOT_NUM_MAX       = 8
SAMPLE_W           = 32
GAIN_W             = 32
GAIN_FRAC_W        = 24
GAIN_FORMAT        = signed Q7.24
OUT_FIFO_DEPTH     = 2

One 32-bit sample per stream transfer
Implicit cyclic slot identity
One pipelined 32x32 signed multiplier
One sample per clock initiation interval
Per-slot independent gain
Per-slot mute
Common-gain mode
Round-to-nearest/ties-away and truncate
Optional saturation; overflow always reported
Shadow and active gain banks
Frame-boundary atomic commit
No gain ramp in v1.0
Configuration update only through defined idle/commit sequences
```

---

# 25. Key Design Conclusions

- Digital Gain must use the same 32-bit ready/valid stream convention as the current Audio Hub Merge path.
- Slot identity is implicit in transfer order, so `ACTIVE_SLOT_NUM` and slot-0 alignment must match across the complete processing chain.
- The slot counter advances only on a successful input handshake.
- Each accepted sample must carry its slot ID and coefficient generation through the pipeline.
- A frame-boundary shadow-to-active commit prevents multi-channel coefficient tearing.
- Backpressure must never change sample order, slot order, or coefficient association.
- Muting changes sample value, not stream structure.
- Saturation status must be detected even when wrap output mode is selected.
- The baseline single pipelined multiplier achieves one 32-bit sample per clock and naturally supports per-slot gain without eight parallel multipliers.
- Gain ramp, AGC, mixing, channel routing, sample-rate conversion, and clock-domain crossing remain outside this IP.
