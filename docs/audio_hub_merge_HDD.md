# Audio Hub Channel Merge IP Hardware Design Description

**Document version:** v1.0  
**Module name:** `audio_channel_merge`  
---

## 1. Overview

The Channel Merge IP combines multiple independent audio streams into one-channel time-interleaved stream.

Each input channel is carried on an independent `valid/ready/data` interface. The input port number identifies the source channel. The output remains 32 bits wide and carries one sample per successful transfer(i.e per valid/ready handshake). Output slot identity is therefore represented implicitly by the transfer order.

For example, for two channels:

```text
Input channel 0: A0, A1, A2, A3, ...
Input channel 1: B0, B1, B2, B3, ...

Merged output:
A0, B0, A1, B1, A2, B2, A3, B3, ...
```

For four input channels:

```text
Input channel 0: A0, A1, A2, A3, ...
Input channel 1: B0, B1, B2, B3, ...
Input channel 2: C0, C1, C2, C3, ...
Input channel 3: D0, D1, D2, D3, ...

Merged output:
A0, B0, C0, D0, A1, B1, C1, D1, A2, B2, C2, D2, A3, B3, C3, D3 ...
```

The slot index of output channel is inferred by a handshake-driven slot counter. The slot counter increments only when `tx_valid && tx_ready`.

The IP does not append `slot_id`, `slot_valid`, or frame metadata to the stream.

---

## 2. Design objectives

The merge IP shall:

1. Accept multiple independent 32-bit mono input streams.
2. Buffer each input channel independently.
3. Preserve per-channel sample ordering.
4. Emit samples in a fixed, configurable slot sequence.
5. Maintain slot ordering under downstream backpressure.
6. Support expansion from two channels to more channels through parameters.
7. Support routing of the merged stream back to the Audio Hub crossbar.
8. Support routing of the merged stream toward a regbank/PIO or DMA adapter path.
9. Support chaining with Digital Gain and other processing IPs through the crossbar.
10. Avoid a combinational ready path from output to all input interfaces.
11. Detect configuration errors, FIFO overflow, starvation, and prolonged alignment wait.
12. Support safe flush, disable, and reconfiguration.

The merge IP shall not:

- Perform arithmetic mixing.
- Perform sample-rate conversion.
- Generate I2S or TDM serial timing.
- Generate Synopsys DMA handshake directly.
- Correct long-term drift between asynchronous audio sources.
- Reconstruct a missing sample automatically in the baseline design.

---

## 3. System-level position

Recommended Audio Hub connection:

```text
                           +------------------+
I2S RX0 ------------------>|                  |
I2S RX1 ------------------>|     Crossbar     |
DG output ---------------->|                  |
                           +--------+---------+
                                    |
                                    v
                           +------------------+
                           |  Channel Merge   |
                           +--------+---------+
                                    |
                         +----------+----------+
                         |                     |
                         v                     v
                  Crossbar return       Regbank/PIO or
                         |              DMA adapter stream
                         v
                 DG / Mixer / TX
```

The crossbar treats the merge IP as a multi-port sink on the input side and a single-stream source on the output side. The crossbar shall not modify sample ordering.

---

## 4. Architecture

The architecture consists of receive stream control, a per-channel FIFO bank, merge scheduling/output control, and output selection/status logic.

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
                            +----------------------+
                            |     Merge Logic      |
                            |  Slot Scheduler/FSM  |
                            +----------+-----------+
                                       |
                              tx_valid/ready/data
                                       |
                           +-----------+-----------+
                           |                       |
                           v                       v
                     Crossbar output        Regbank/DMA-
                                            adapter output
```

---

## 5. Interface definition

### 5.1 Parameters

```systemverilog
parameter int unsigned CHANNEL_NUM_MAX       = 8;
parameter int unsigned DATA_W                = 32;
parameter int unsigned RX_FIFO_DEPTH         = 4;
parameter int unsigned TX_FIFO_DEPTH         = 2;
parameter int unsigned ALIGN_TIMEOUT_CNT_W   = 16;
parameter int unsigned SAMPLE_CNT_W          = 32;

localparam int unsigned CHANNEL_ID_W =
    (CHANNEL_NUM_MAX <= 1) ? 1 : $clog2(CHANNEL_NUM_MAX);

localparam int unsigned FIFO_LEVEL_W =
    $clog2(RX_FIFO_DEPTH + 1);
```

### 5.2 Clock and reset

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `clk` | Input | 1 | Audio Hub processing clock |
| `rst_n` | Input | 1 | Active-low reset |

All input streams shall already be synchronized to `clk`. If an I2S controller operates in another clock domain, CDC shall be completed before the stream enters this IP.

### 5.3 Input stream interface

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `rx_valid` | Input | `CHANNEL_NUM_MAX` | Per-channel input valid |
| `rx_ready` | Output | `CHANNEL_NUM_MAX` | Per-channel input ready |
| `rx_data` | Input | `CHANNEL_NUM_MAX × 32` | Per-channel input sample |

Transfer condition for channel `i`:

```systemverilog
rx_fire[i] = rx_valid[i] && rx_ready[i];
```

The physical input index identifies the channel.

### 5.4 Output stream toward crossbar

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `xbar_tx_valid` | Output | 1 | Merged sample valid |
| `xbar_tx_ready` | Input | 1 | Crossbar accepts output sample |
| `xbar_tx_data` | Output | 32 | Merged sample data |

### 5.5 Output stream toward regbank/DMA adapter

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `rb_tx_valid` | Output | 1 | Merged sample valid |
| `rb_tx_ready` | Input | 1 | Destination accepts output sample |
| `rb_tx_data` | Output | 32 | Merged sample data |

The merge IP shall not generate Synopsys DMA request/acknowledge signals. The `rb_tx_*` stream shall connect to an independent DMA adapter or PIO FIFO.

### 5.6 Configuration interface

| Signal | Width | Description |
|---|---:|---|
| `cfg_merge_en` | 1 | Enable merge operation |
| `cfg_channel_en` | `CHANNEL_NUM_MAX` | Enable input channels |
| `cfg_active_channel_num` | `CHANNEL_ID_W+1` | Number of active slots |
| `cfg_slot_src_sel[]` | Per slot | Select source FIFO for each output slot |
| `cfg_out_sel` | 2 | Output destination selection |
| `cfg_align_timeout_en` | 1 | Enable alignment timeout |
| `cfg_align_timeout_th` | `ALIGN_TIMEOUT_CNT_W` | Timeout threshold |
| `cfg_flush` | 1 | Flush command |
| `cfg_soft_reset` | 1 | Soft-reset command |

---

## 6. Data ordering and slot identification

### 6.1 Input ordering

```text
FIFO0: A0, A1, A2, A3, ...
FIFO1: B0, B1, B2, B3, ...
FIFO2: C0, C1, C2, C3, ...
```

### 6.2 Output ordering

For the sequence `slot0->input0`, `slot1->input1`, `slot2->input2`, `slot3->input3`:

```text
A0, B0, C0, D0,
A1, B1, C1, D1,
A2, B2, C2, D2, ...
```

Because `data` is fixed at 32 bits, each successful output transfer carries exactly one slot sample.

### 6.3 Slot counter

```systemverilog
if (tx_valid && tx_ready) begin
    if (slot_cnt == active_slot_num - 1)
        slot_cnt <= '0;
    else
        slot_cnt <= slot_cnt + 1'b1;
end
```

Requirements:

- The counter advances only on handshake.
- Reset and flush return the counter to slot 0.
- Routing shall not switch in the middle of a frame.
- Active slot count and slot mapping shall not change while merge is running.
- Every downstream block that interprets slot order shall use the same configuration or a synchronized frame reset.

### 6.4 Frame boundary

```text
frame_done = tx_fire && slot_cnt == active_slot_num - 1
```

No explicit `frame_start` or `frame_end` sideband is present.

---

## 7. RX stream control

For each channel `i`:

```systemverilog
rx_ready[i] =
    cfg_merge_en &&
    cfg_channel_en[i] &&
    !rx_fifo_full[i] &&
    !flush_active &&
    !fatal_error;

rx_fifo_wr_en[i] = rx_valid[i] && rx_ready[i];
rx_fifo_wdata[i] = rx_data[i];
```

A complex independent FSM per channel is not mandatory. The block shown as `RX_stream_FSM` may be implemented as common state control plus generated per-channel handshake logic.

Recommended common state model:

```text
RX_IDLE -> RX_RUN -> RX_FLUSH -> RX_IDLE
              |
              +-> RX_ERROR
```

One full FIFO shall not directly prevent another non-full FIFO from accepting data.

---

## 8. RX FIFO bank

Instantiate one FIFO per supported input channel.

```systemverilog
for (genvar i = 0; i < CHANNEL_NUM_MAX; i++) begin
    audio_sync_fifo #(
        .DATA_W (32),
        .DEPTH  (RX_FIFO_DEPTH)
    ) u_rx_fifo (...);
end
```

Each FIFO exposes write enable/data, read/pop, head data, full, empty, and occupancy count.

The FIFO bank decouples input handshakes, absorbs short arrival skew and output stalls, and prevents a direct combinational path from `tx_ready` to `rx_ready`. It does not solve persistent source-rate mismatch.

A show-ahead/FWFT FIFO is recommended. If a registered-read FIFO is used, the merge FSM needs an explicit read-request and read-data-valid stage.

---

## 9. Merge logic

### 9.1 Responsibilities

The merge logic shall:

1. Maintain the current output slot counter.
2. Select the source FIFO configured for that slot.
3. Check source FIFO availability.
4. Present the selected sample on the output.
5. Hold data stable during backpressure.
6. Pop the source FIFO only after output transfer.
7. Advance slot count only after output transfer.
8. Generate frame and sample counters.
9. Detect prolonged wait for a required channel.

### 9.2 Source selection

```systemverilog
current_src    = cfg_slot_src_sel[slot_cnt];
selected_empty = rx_fifo_empty[current_src];
selected_data  = rx_fifo_rdata[current_src];
```

### 9.3 Recommended registered output stage

Add a one-entry output holding register or small TX FIFO:

```text
RX FIFO bank -> source mux -> output holding register -> destination
```

This provides stable output under backpressure and registers the crossbar interface.

### 9.4 Merge FSM

Recommended states:

```text
M_IDLE
M_WAIT_SAMPLE
M_LOAD
M_SEND
M_FLUSH
M_ERROR
```

- `M_IDLE`: wait for enable and valid configuration; set `slot_cnt=0`.
- `M_WAIT_SAMPLE`: wait until the selected FIFO is non-empty; run timeout detection.
- `M_LOAD`: copy FIFO head into output holding register.
- `M_SEND`: assert output valid and hold data until ready. On handshake, pop source FIFO and advance slot.
- `M_FLUSH`: clear FIFOs/output state and reset slot count.
- `M_ERROR`: stop traffic until soft reset or flush.

For a show-ahead FIFO, `M_LOAD` and `M_SEND` may be combined.

### 9.5 Throughput optimization

A one-entry elastic register supporting simultaneous consume/refill allows one 32-bit sample per clock when source FIFOs are non-empty and downstream is ready.

---

## 10. Alignment policy

The merge logic processes slots strictly in configured order. It shall not skip an empty slot to send another channel early.

Example:

```text
slot0 FIFO has A0
slot1 FIFO is empty
slot2 FIFO has C0
```

After `A0`, the merge waits for slot1. It shall not send `C0` early.

Alignment timeout starts when the current required FIFO is empty while another active FIFO has data. On expiration, the IP sets sticky timeout status and raises an interrupt if enabled. The baseline behavior is to continue waiting unless `HALT_ON_TIMEOUT=1`.

If different I2S controllers use unrelated sample clocks, FIFO occupancy will drift. This IP cannot correct the drift; a common sample clock, SRC, or higher-level timestamp/frame alignment is required.

---

## 11. Output destination selection

Recommended encoding:

```text
00: output disabled
01: regbank/DMA-adapter path
10: crossbar return path
11: both destinations, optional
```

For one destination, only the selected valid is asserted and the selected ready drives the internal transfer.

If both destinations are required, use independent output FIFOs. Do not connect one valid to two unrelated ready signals without storage. The first implementation should preferably support one destination at a time.

---

## 12. Crossbar and Digital Gain cascading

### 12.1 Merge followed by DG

```text
Merge output -> Crossbar -> DG input
```

Because the stream is 32-bit and one-sample-per-transfer, DG must maintain a synchronized slot counter, incrementing only on `valid && ready`, and use the same active slot sequence.

### 12.2 DG followed by Merge

When each DG instance processes one mono stream:

```text
I2S_RX0 -> DG0 -> Merge input0
I2S_RX1 -> DG1 -> Merge input1
```

No slot counter is needed at the merge input because the physical port identifies the channel.

### 12.3 Route-update restriction

The crossbar shall not change the route of an active multi-slot stream in the middle of a logical frame.

Recommended update sequence:

```text
disable stream
wait for idle or flush
update route
reset downstream slot counters
enable stream
```

---

## 13. DMA adapter integration

The merge IP outputs only the standard 32-bit stream. A standalone DMA adapter shall provide:

- Capture/playback FIFO.
- Synopsys DMA request generation.
- Burst-watermark control.
- Width adaptation where needed.
- Overflow/underflow reporting.
- Optional PIO access.

For capture, request is based on enough available DMA beats. For playback, request is based on enough free FIFO space.

---

## 14. Configuration validation

Configuration is valid only when:

1. At least one channel is enabled.
2. `active_channel_num` is non-zero and not greater than `CHANNEL_NUM_MAX`.
3. Every active slot source index is in range.
4. Every selected source channel is enabled.
5. Output destination is not disabled while merge is enabled.
6. Both-output mode is not selected unless implemented.
7. No prohibited active configuration update is pending.

Duplicate source mappings require an explicit policy. If true same-sample duplication is required, the design must replay one FIFO head across multiple slots and pop only after the last duplicate slot.

---

## 15. Reset, flush, and reconfiguration

Hardware reset clears all FIFOs, output state, counters, slot counter, and sticky status, then enters IDLE.

Soft reset stops input acceptance, clears all buffering and timeout state, resets the slot counter, and returns to IDLE.

Flush discards buffered samples, clears output state, resets slot count, and preserves configuration. Sticky errors may optionally be preserved.

Recommended software sequence:

```text
1. Clear MERGE_EN.
2. Wait for IDLE or issue FLUSH.
3. Program channel enable.
4. Program active slot count.
5. Program slot source sequence.
6. Program output destination.
7. Clear stale status.
8. Set MERGE_EN.
```

---

## 16. Status and error behavior

- **RX FIFO overflow:** normally prevented by ready/valid; sticky error on illegal full write.
- **RX FIFO underflow:** sticky error on illegal empty pop.
- **Alignment timeout:** current slot unavailable beyond threshold.
- **Output overflow:** internal output FIFO/register protocol error.
- **Active configuration write:** slot/channel/output settings changed while active and locked.
- **Output stall:** not an error; data and valid remain stable until ready.

---

## 17. Performance targets

Maximum target throughput is one 32-bit sample per processing clock.

For `N` active channels, one logical frame requires `N` successful output transfers. With no stalls:

```text
frame throughput = processing_clock / N
```

Typical minimum latency is two to four clocks depending on FIFO and output-register implementation.

Backpressure propagates through output buffering and input FIFOs; there shall be no long direct combinational chain from destination ready to all input ready signals.

---

# 18. Register map

All registers are 32 bits and offsets are relative to the merge register base.

## 18.1 Register summary

| Offset | Register | Access | Description |
|---:|---|---|---|
| `0x000` | `MERGE_ID` | RO | IP ID and revision |
| `0x004` | `MERGE_CAP` | RO | Hardware capabilities |
| `0x008` | `MERGE_CTRL` | RW | Enable, reset, flush, output selection |
| `0x00C` | `MERGE_CHANNEL_EN` | RW | Input-channel enable mask |
| `0x010` | `MERGE_SLOT_CFG` | RW | Active slot count and mode |
| `0x014` | `MERGE_TIMEOUT_CFG` | RW | Alignment timeout control |
| `0x018` | `MERGE_STATUS` | RO | Current operating status |
| `0x01C` | `MERGE_ERR_STATUS` | W1C | Sticky errors |
| `0x020` | `MERGE_INT_EN` | RW | Interrupt enables |
| `0x024` | `MERGE_INT_STATUS` | W1C | Interrupt status |
| `0x028` | `MERGE_FRAME_CNT` | RO | Completed logical frame count |
| `0x02C` | `MERGE_SAMPLE_CNT` | RO | Output transfer count |
| `0x030` | `MERGE_STALL_CNT` | RO | Output stall cycles |
| `0x034` | `MERGE_DEBUG_CTRL` | RW | Counter clear and debug controls |
| `0x040` | `MERGE_SLOT_SRC_SEL0` | RW | Source selection for slots |
| `...` | `MERGE_SLOT_SRC_SELn` | RW | Additional source selections |
| `0x080` | `MERGE_FIFO_LEVEL0` | RO | Packed input FIFO levels |
| `...` | `MERGE_FIFO_LEVELn` | RO | Additional FIFO levels |
| `0x0C0` | `MERGE_IN_SAMPLE_CNT0` | RO | Input accepted sample counter 0 |
| `...` | `MERGE_IN_SAMPLE_CNTn` | RO | Additional input sample counters |

## 18.2 `MERGE_ID` — `0x000`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[15:0]` | `IP_ID` | RO | implementation | Merge IP identifier |
| `[23:16]` | `MINOR_REV` | RO | implementation | Minor revision |
| `[31:24]` | `MAJOR_REV` | RO | implementation | Major revision |

## 18.3 `MERGE_CAP` — `0x004`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[7:0]` | `CHANNEL_NUM_MAX` | RO | parameter | Maximum input channels |
| `[15:8]` | `FIFO_DEPTH` | RO | parameter | Per-channel FIFO depth |
| `[21:16]` | `DATA_WIDTH` | RO | 32 | Stream data width |
| `[22]` | `BOTH_OUT_SUP` | RO | implementation | Both-output support |
| `[23]` | `TIMEOUT_SUP` | RO | implementation | Alignment-timeout support |
| `[24]` | `DUP_REPLAY_SUP` | RO | implementation | Same-sample duplicate replay support |
| `[31:25]` | `RSVD` | RO | 0 | Reserved |

## 18.4 `MERGE_CTRL` — `0x008`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `MERGE_EN` | RW | 0 | Enable merge |
| `[1]` | `SOFT_RESET` | WO/SC | 0 | Soft reset command |
| `[2]` | `FLUSH` | WO/SC | 0 | Flush command |
| `[4:3]` | `OUT_SEL` | RW | 0 | `00` disabled, `01` regbank/DMA adapter, `10` crossbar, `11` both |
| `[5]` | `CFG_LOCK` | RW | 0 | Reject active configuration writes |
| `[6]` | `HALT_ON_CFG_ERR` | RW | 1 | Enter ERROR on configuration error |
| `[7]` | `HALT_ON_TIMEOUT` | RW | 0 | Enter ERROR on timeout |
| `[31:8]` | `RSVD` | RW | 0 | Reserved |

## 18.5 `MERGE_CHANNEL_EN` — `0x00C`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[CHANNEL_NUM_MAX-1:0]` | `CHANNEL_EN` | RW | 0 | Input channel enable |
| Remaining | `RSVD` | RW | 0 | Reserved |

## 18.6 `MERGE_SLOT_CFG` — `0x010`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[7:0]` | `ACTIVE_SLOT_NUM` | RW | 0 | Number of output slots per logical frame |
| `[8]` | `FIXED_SEQUENCE_EN` | RW | 1 | Use configured cyclic slot order |
| `[9]` | `DUP_REPLAY_EN` | RW | 0 | Reuse one FIFO head for duplicate slots |
| `[10]` | `FRAME_COUNTER_EN` | RW | 1 | Enable frame counter |
| `[31:11]` | `RSVD` | RW | 0 | Reserved |

## 18.7 `MERGE_TIMEOUT_CFG` — `0x014`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `TIMEOUT_EN` | RW | 0 | Enable timeout |
| `[1]` | `PRESERVE_ERR_ON_FLUSH` | RW | 1 | Preserve sticky errors on flush |
| `[31:2]` | `TIMEOUT_TH` | RW | 0 | Timeout threshold in processing clocks |

## 18.8 `MERGE_STATUS` — `0x018`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `IDLE` | RO | 1 | Module idle |
| `[1]` | `BUSY` | RO | 0 | Merge active |
| `[2]` | `WAIT_SAMPLE` | RO | 0 | Waiting for current slot FIFO |
| `[3]` | `TX_STALL` | RO | 0 | Output valid and not ready |
| `[4]` | `FLUSH_ACTIVE` | RO | 0 | Flush active |
| `[5]` | `ERROR_STATE` | RO | 0 | FSM in error |
| `[6]` | `CFG_VALID` | RO | 0 | Configuration valid |
| `[7]` | `OUT_HOLD_VALID` | RO | 0 | Output holding register occupied |
| `[15:8]` | `CURRENT_SLOT` | RO | 0 | Current implicit output slot |
| `[23:16]` | `CURRENT_SRC` | RO | 0 | Current source FIFO index |
| `[31:24]` | `RSVD` | RO | 0 | Reserved |

## 18.9 `MERGE_ERR_STATUS` — `0x01C`

| Bits | Field | Access | Reset | Description |
|---|---|---|---:|---|
| `[0]` | `CFG_ERR` | W1C | 0 | Invalid configuration |
| `[1]` | `RX_FIFO_OVERFLOW` | W1C | 0 | Any input FIFO overflow |
| `[2]` | `RX_FIFO_UNDERFLOW` | W1C | 0 | Illegal empty FIFO pop |
| `[3]` | `ALIGN_TIMEOUT` | W1C | 0 | Alignment timeout |
| `[4]` | `OUT_OVERFLOW` | W1C | 0 | Output FIFO/register overflow |
| `[5]` | `ACTIVE_CFG_WRITE` | W1C | 0 | Illegal active configuration write |
| `[6]` | `PROTOCOL_ERR` | W1C | 0 | Handshake protocol violation |
| `[7]` | `ROUTE_SYNC_ERR` | W1C | 0 | Route or slot-counter synchronization error |
| `[31:8]` | `RSVD` | W1C | 0 | Reserved |

## 18.10 `MERGE_INT_EN` — `0x020`

Interrupt-enable bits correspond one-to-one with `MERGE_ERR_STATUS[7:0]`.

## 18.11 `MERGE_INT_STATUS` — `0x024`

Interrupt-status bits correspond one-to-one with `MERGE_ERR_STATUS[7:0]` and are W1C.

```systemverilog
irq = |(merge_int_status & merge_int_en);
```

## 18.12 Counters

- `MERGE_FRAME_CNT`: increments when the final active slot transfers.
- `MERGE_SAMPLE_CNT`: increments on each committed output transfer.
- `MERGE_STALL_CNT`: increments while selected output is valid and not ready.
- Per-input sample counters increment on `rx_valid[i] && rx_ready[i]`.

## 18.13 Slot source selection registers

Each slot source field width is:

```text
SRC_ID_W = ceil(log2(CHANNEL_NUM_MAX))
```

Fields are packed into as many 32-bit registers as required.

## 18.14 FIFO level registers

Each FIFO occupancy field width is:

```text
FIFO_LEVEL_W = ceil(log2(RX_FIFO_DEPTH + 1))
```

Fields are packed into repeated registers.

---

# 19. Example configurations

## 19.1 Two-channel merge

```text
CHANNEL_EN      = 0x3
ACTIVE_SLOT_NUM = 2
SLOT0_SRC       = 0
SLOT1_SRC       = 1
OUT_SEL         = CROSSBAR
MERGE_EN        = 1
```

Output:

```text
A0, B0, A1, B1, A2, B2, ...
```

## 19.2 Four-channel merge

```text
CHANNEL_EN      = 0xF
ACTIVE_SLOT_NUM = 4
SLOT0_SRC       = 0
SLOT1_SRC       = 1
SLOT2_SRC       = 2
SLOT3_SRC       = 3
OUT_SEL         = CROSSBAR
MERGE_EN        = 1
```

Output:

```text
A0, B0, C0, D0,
A1, B1, C1, D1, ...
```

## 19.3 Channel reorder

```text
SLOT0_SRC = 2
SLOT1_SRC = 0
SLOT2_SRC = 3
SLOT3_SRC = 1
```

Output:

```text
C0, A0, D0, B0,
C1, A1, D1, B1, ...
```

## 19.4 Merge to DMA adapter

```text
OUT_SEL = REGBANK_DMA_ADAPTER
```

The DMA adapter receives the same ordered 32-bit stream and independently generates Synopsys DMA handshakes.

---

# 20. RTL pseudocode

## 20.1 Input FIFO writes

```systemverilog
for (int i = 0; i < CHANNEL_NUM_MAX; i++) begin
    rx_ready[i] = cfg_merge_en &&
                  cfg_channel_en[i] &&
                  !rx_fifo_full[i] &&
                  !flush_active &&
                  !fatal_error;

    rx_fifo_wr_en[i] = rx_valid[i] && rx_ready[i];
    rx_fifo_wdata[i] = rx_data[i];
end
```

## 20.2 Current source

```systemverilog
current_src    = active_slot_src[slot_cnt];
selected_empty = rx_fifo_empty[current_src];
selected_data  = rx_fifo_rdata[current_src];
```

## 20.3 Output holding register

```systemverilog
load_out = !out_valid_q &&
           cfg_merge_en &&
           cfg_valid &&
           !selected_empty &&
           !flush_active;

if (load_out) begin
    out_data_q  <= selected_data;
    out_valid_q <= 1'b1;
    out_src_q   <= current_src;
end
```

## 20.4 Output transfer

```systemverilog
tx_fire = out_valid_q && selected_tx_ready;

if (tx_fire) begin
    rx_fifo_rd[out_src_q] <= 1'b1;
    out_valid_q <= 1'b0;

    if (slot_cnt == active_slot_num - 1)
        slot_cnt <= '0;
    else
        slot_cnt <= slot_cnt + 1'b1;
end
```

---

# 21. Verification plan

Functional tests shall cover:

- Two-channel and four-channel merge.
- Arbitrary slot reorder.
- Random input arrival skew.
- Long output backpressure.
- Missing channel and timeout.
- Flush/reset while active or stalled.
- Crossbar output and DMA-adapter output.
- Maximum parameterized channel count.

Ordering scoreboard rule:

```text
expected_slot = output_transfer_count % active_slot_num
expected_src  = slot_src_sel[expected_slot]
```

Recommended assertions:

- No FIFO write while full.
- No FIFO pop while empty.
- Output stable while `valid && !ready`.
- Slot counter changes only on output handshake.
- Slot counter resets on reset and flush.
- Output source matches configured source for current slot.
- Input FIFO pop occurs only for a committed output sample.
- No input is consumed while configuration is invalid.
- Active slot count is non-zero and in range while enabled.

---

# 22. Synthesis, timing, and low-power considerations

1. Register the crossbar-facing output.
2. Avoid direct `tx_ready -> rx_ready` combinational propagation.
3. Use generate loops for FIFO-bank construction.
4. Register active slot mapping when enabling merge.
5. Consider one-hot source decode for large channel counts.
6. Pipeline source muxing if timing requires it.
7. Use approved ICG cells for optional clock gating.
8. Keep reset deassertion synchronous to `clk`.
9. Use verified common FIFO primitives.
10. Implement CDC outside the merge IP for asynchronous sources.
11. Explicitly constrain source-select mux and output paths in STA.

---

# 23. Recommended baseline implementation

```text
CHANNEL_NUM_MAX     = 8
DATA_W              = 32
RX_FIFO_DEPTH       = 4
TX_FIFO_DEPTH       = 1 or 2
ALIGN_TIMEOUT_CNT_W = 16

One output destination at a time
Fixed cyclic slot order
No slot sideband
No automatic sample drop
No automatic zero fill for a missing channel
No internal DMA handshake
No sample-rate conversion
Configuration update only while idle
```

---

# 24. Key design conclusions

- With fixed 32-bit data and no sideband, slot identity is implicit in transfer order.
- The slot counter must advance only on `valid && ready`.
- Every stateful downstream block must remain synchronized to the same logical frame sequence.
- Per-channel FIFOs absorb short arrival skew and decouple handshakes.
- Merge waits for the currently required channel rather than skipping slots.
- Crossbar route changes and merge configuration changes require idle/flush handling.
- Synopsys DMA handshake generation belongs in a standalone DMA adapter.
- The architecture scales through parameterized input count, FIFO depth, slot mapping, and counters.
