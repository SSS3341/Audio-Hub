# Audio Hub Channel Merge IP Hardware Design Description

**Document version:** v1.0  
**Module name:** `audio_channel_merge`  
---

## 1. Overview

The Channel Merge IP supports merge 8 multiple independent input rx audio streams into 4 channel output streams, each output stream can be merged of any combination of the 8 intput streams. Software needs to config corresponding registers to choose the merge style of each output tx channel.

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

---

## 2. Design Features


| ID | Feature |
|----|---------|
| 1 | Support 8 independent 32-bit input streams |
| 2 | Each input channel has independently rx FIFO |
| 3 | Preserve per-channel sample ordering |
| 4 | Emit samples in a fixed, configurable slot sequence |
| 5 | Maintain slot ordering under downstream backpressure |
| 6 | Support expansion from two channels inputs to 8 channels inputs through parameters |
| 7 | Support routing of the merged stream back to the Audio Hub crossbar |
| 8 | Support tx FIFO to store merged stream data before sending to crossbar |
| 9 | Support chaining with Digital Gain or other processing IPs through the crossbar |
| 10 | Detect FIFO overflow, underflow, and prolonged alignment wait |
| 11 | Support safe flush, disable, and reconfiguration |

---

## 3. System-level Diagram

```text
                           +------------------+
I2S RX0 ------------------>|                  |
I2S RX1 ------------------>|     Crossbar     |
I2S RXn ------------------>|                  |
                           +--------+---------+
                                    |
                                    v
                           +------------------+
                           |  Channel Merge   |
                           +--------+---------+
                                    |
                                    v
                            Crossbar return
                                    |              
                                    v
                   DG / Mixer / I2S/ DMA adapter stream
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
      +------------------+------------------+------------------+
      |                  |                  |                  |
      v                  v                  v                  v
+-----------+      +-----------+      +-----------+      +-----------+
| TX0 Merge |      | TX1 Merge |      | TX2 Merge |      | TX3 Merge |
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

---

## 5. Interface definition

### 5.1 Parameters

parameter DATA_W                = 32;
parameter RX_FIFO_DEPTH         = 4;
parameter TX_FIFO_DEPTH         = 32; 

### 5.2 Clock and reset

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `clk_merge` | Input | 1 | Audio Hub processing clock |
| `rstn_merge` | Input | 1 | Active-low reset |

### 5.3 Input stream interface

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `merge_rx_valid` | Input | `CHANNEL_NUM_MAX` | Per-channel input valid |
| `merge_rx_ready` | Output | `CHANNEL_NUM_MAX` | Per-channel input ready |
| `merge_rx_data` | Input | `CHANNEL_NUM_MAX × 32` | Per-channel input sample |

Transfer condition for channel `i`:

```systemverilog
rx_fire[i] = rx_valid[i] && rx_ready[i];
```

The physical input index identifies the channel.

### 5.4 Output stream toward crossbar

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `merge_tx_valid` | Output | 1 | Merged sample valid |
| `merge_tx_ready` | Input | 1 | Crossbar accepts output sample |
| `merge_tx_data` | Output | 32 | Merged sample data |

## 6 Register Description

### 6.1 Merge Enable Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_merge_en` | 1 | Enable merge operation |
| `cfg_merge_rxen` | 8 | Each bit controls the enable signal of each merge recieve channel respectively, for example:
                        8'b0000_0001 enables channel 1
                        8'b0000_0100 enables channel 3
                        8'b0000_0101 enables channel 1 and channel 3 |
| `cfg_merge_txen` | 1 | Enable merge tx channel |

### 6.2 TX Channel 0 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_channel_src_sel` | 8 | Select rx source FIFO for channel 0 output stream |
| `cfg_tx_0_slot_0` | 3 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_0_slot_1` | 3 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_0_slot_2` | 3 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_0_slot_3` | 3 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_0_slot_4` | 3 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_0_slot_5` | 3 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_0_slot_6` | 3 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_0_slot_7` | 3 | Select which input channel data will be put in slot_7 of each frame |

The output order of channel 0 is as follows, assume all 8 inptut rx channels are selected to be merged and output through tx channel 0:

```text
Merged output:
| slot_0, slot_1, slot_2, slot_3, slot_4, slot_5, slot_6, slot_7, | slot_0, slot_1, slot_2, slot_3, slot_4, slot_5, slot_6, slot_7 ...
|                                                                 |  
Frame 1                                                           Frame 2
```
### 6.3 TX Channel 1 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_channel_src_sel` | 8 | Select rx source FIFO for channel 0 output stream |
| `cfg_tx_1_slot_0` | 3 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_1_slot_1` | 3 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_1_slot_2` | 3 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_1_slot_3` | 3 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_1_slot_4` | 3 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_1_slot_5` | 3 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_1_slot_6` | 3 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_1_slot_7` | 3 | Select which input channel data will be put in slot_7 of each frame |

### 6.4 TX Channel 2 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_2_channel_src_sel` | 8 | Select rx source FIFO for channel 0 output stream |
| `cfg_tx_2_slot_0` | 3 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_2_slot_1` | 3 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_2_slot_2` | 3 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_2_slot_3` | 3 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_2_slot_4` | 3 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_2_slot_5` | 3 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_2_slot_6` | 3 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_2_slot_7` | 3 | Select which input channel data will be put in slot_7 of each frame |

### 6.5 TX Channel 3 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_3_channel_src_sel` | 8 | Select rx source FIFO for channel 0 output stream |
| `cfg_tx_3_slot_0` | 3 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_3_slot_1` | 3 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_3_slot_2` | 3 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_3_slot_3` | 3 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_3_slot_4` | 3 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_3_slot_5` | 3 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_3_slot_6` | 3 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_3_slot_7` | 3 | Select which input channel data will be put in slot_7 of each frame |

### 6.2 TX Channel Frame Setting Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_frame_num` | 3 | Select tx channel 0 merged rx frame number |
| `cfg_tx_1_frame_num` | 3 | Select tx channel 1 merged rx frame number |
| `cfg_tx_2_frame_num` | 3 | Select tx channel 2 merged rx frame number |
| `cfg_tx_3_frame_num` | 3 | Select tx channel 3 merged rx frame number |

### 6.6 RX FIFO Flush Register 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_rx_fifo_flush` | 8 | Each bit provides rx flush signal of each rx channel respectively |
| `RESERVE` | 24 | Reserved |

---

## 7. FSM Design


```text
                         +---------+
                         |  IDLE   |
                         +----+----+
                              |
                              | Merge Enable && TX channel enable
                              v
                     +--------+---------+
                     |                  |
                     |   WAIT_FRAME     |
                     |                  |
                     | TX slot_0 from   |
                     | RX FIFO ready ?  |
                     +--------+---------+
                              |
                              | Yes
                              v
                     +--------+---------+
                     |                  |
                     |  WRITE_FRAME     |
                     |                  |
                     | Write one slot   |
                     | into TX FIFO     |
                     +--------+---------+
                              |
                  Last slot ? |
                     No       | Yes
                      |       |
                      +-------+
                              |
                              v
                        WAIT_FRAME
```

# 8. Future Design Discussion 
The IP does not append `slot_id`, `slot_valid`, or frame metadata to the stream.
