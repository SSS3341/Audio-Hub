# Audio Hub Channel Merge IP Hardware Design Description

**Document version:** v2.0  
**Module name:** `audio_channel_merge`  
---

## 1. Introduction

The Channel Merge IP supports merge up to 16 independent input rx audio streams into 4 output streams, each output stream can be merged of any combination of the 16 intput streams. Software needs to config corresponding registers to choose the merge style of each output tx channel. The Merge IP supports 3 output data packing formants for each tx channel:

-Frame interleave
-Block interleave
-Planar

For Frame interleave mode, the output modes are like:
```text
For example, for two input streams:

Input stream 0: A0, A1, A2, A3, ...
Input stream 1: B0, B1, B2, B3, ...
Merged output stream:
A0, B0, A1, B1, A2, B2, A3, B3, ...

For four input streams:
Input stream 0: A0, A1, A2, A3, ...
Input stream 1: B0, B1, B2, B3, ...
Input stream 2: C0, C1, C2, C3, ...
Input stream 3: D0, D1, D2, D3, ...
Merged output stream:
A0, B0, C0, D0, A1, B1, C1, D1, A2, B2, C2, D2, A3, B3, C3, D3 ...
```

For Block interleave mode, the output modes are like:
```text
For example, for two input streams, the block_size is configured as 2:

Input stream 0: A0, A1, A2, A3, ...
Input stream 1: B0, B1, B2, B3, ...
Merged output stream:
A0, A1, B0, B1, A2, A3, B2, B3, ...

For four input streams:
Input stream 0: A0, A1, A2, A3, ...
Input stream 1: B0, B1, B2, B3, ...
Input stream 2: C0, C1, C2, C3, ...
Input stream 3: D0, D1, D2, D3, ...
Merged output stream:
A0, A1, B0, B1, C0, C1, D0, D1, A2, A3, B2, B3, C2, C3, D2, D3 ...
```

For Planar mode, the output modes are like:
```text
For example, for two input streams each has 4 slots in one frame :

Input stream 0: A0, A1, A2, A3, ...
Input stream 1: B0, B1, B2, B3, ...
Merged output stream:
A0, A1, A2, A3, B0, B1, B2, B3, ...

For four input streams:
Input stream 0: A0, A1, A2, A3, ...
Input stream 1: B0, B1, B2, B3, ...
Input stream 2: C0, C1, C2, C3, ...
Input stream 3: D0, D1, D2, D3, ...
Merged output stream:
A0, A1, A2, A3, B0, B1, B2, B3, C0, C1, C2, C3, D0, D1, D2, D3 ...
```


Each input channel is carried on an independent `valid/ready/data` interface. The input port number identifies the source channel. The output remains 32 bits wide and carries one sample per successful transfer(i.e per valid/ready handshake). Output slot identity is therefore represented implicitly by the transfer order.


The slot index of output stream is inferred by a handshake-driven slot counter. The slot counter increments only when `tx_valid && tx_ready`.

---

## 2. Design Features


| ID | Feature |
|----|---------|
| 1 | Support 16 independent 32-bit input streams |
| 2 | Each input channel has independent rx FIFO |
| 3 | Preserve per-channel sample ordering |
| 4 | Emit samples in a fixed, configurable slot sequence |
| 5 | Maintain slot ordering under downstream backpressure |
| 6 | Support merge operation from two channels inputs to 16 channels inputs through reg config |
| 7 | Support routing of the merged stream back to the Audio Hub crossbar |
| 8 | Support tx FIFO to store merged stream data before sending to crossbar for each output port|
| 9 | Support chaining with Digital Gain or other processing IPs through the crossbar |
| 10 | Detect rx/tx FIFO overflow, underflow, and input stream waiting overtime |
| 11 | Support safe flush, disable, and reconfiguration |
| 12 | Support software configurable output frame format |
| 13 | Support software configurable 3 modes output frame format |


---

## 3. System-level Diagram

```text
                           +------------------+
I2S RX0 ------------------>|                  |
I2S RX1 ------------------>|     Crossbar     |
    ... ------------------>|                  |
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

The crossbar treats the merge IP as a multi-port sink on the input side and a multi-port source on the output side. The crossbar shall not modify sample ordering.

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

parameter RX_FIFO_DEPTH         = 4;
parameter TX_FIFO_DEPTH         = 64; 
parameter RX_FIFO_WIDTH         = 32;
parameter TX_FIFO_WIDTH         = 32; 

### 5.2 Clock and reset

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `clk_merge` | Input | 1 | Audio Hub processing clock |
| `rstn_merge` | Input | 1 | Active-low reset |

### 5.3 Input stream interface

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `merge_rx_valid` | Input | `16` | Per-channel input valid |
| `merge_rx_ready` | Output | `16` | Per-channel input ready |
| `merge_rx_data` | Input | `16 × 32` | Per-channel input sample |

Transfer condition for channel `i`:

```systemverilog
rx_fire[i] = rx_valid[i] && rx_ready[i];
```

The physical input index identifies the channel.

### 5.4 Output stream toward crossbar

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `merge_tx_valid` | Output | 4 | Merged sample valid |
| `merge_tx_ready` | Input | 4 | Crossbar accepts output sample |
| `merge_tx_data` | Output | 4 x 32 | Merged sample data |

### 5.5 Interrupt
| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `merge_tx_overflow` | Output | 4 | TX fifo overflow of each output channel, assert if TX FIFO is full but tx_ready of downstream IP is low |
| `merge_rx_overflow` | Output | 16 | RX fifo overflow of each output channel, assert if RX FIFO is full but there is still valid data coming from upstream IP |

## 6 Register Description

### 6.1 Merge Enable Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_merge_en` | 1 | Enable merge IP |
| `cfg_merge_rxen` | 16 | Each bit controls the enable signal of each merge recieve channel respectively, for example:
                        16'b0000_0000_0000_0001 enables channel 1
                        16'b0000_0000_0000_0100 enables channel 3
                        16'b0000_0000_0000_0101 enables channel 1 and channel 3 |
| `cfg_merge_txen` | 4 | Each bit enables corresponding output tx channel respectively, for example:<br>4'b0001 enables channel 1<br>4'b0100 enables channel 3<br>4'b0101 enables channel 1 and channel 3 |

### 6.2 TX Channel 0 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_channel_src_sel` | 16 | Select rx source FIFO for channel 0 output stream |
| `cfg_tx_0_channel_frame_style` | 2 | Select tx channel output frame mode, 0: frame-interleave<br>1: block_interleave<br>2:planar mode |
| `cfg_tx_0_channel_block_size` | 5 | Select tx channel output frame interleaved block size, from 2 to 32 slots. For example: if configured 2, the interleave granularity is 2 slots for each input channel |
| `cfg_tx_0_channel_planar_len` | 5 | Select tx channel merged input channel frame size, from 2 to 32 slots. For example: if configured 2, the merged input frame slots is 2 slots |
| `cfg_tx_0_channel_frame_size` | 5 | Select the tx channel 0 frame size, i.e. cfg_tx_0_channel_frame_size + 1 slots inside each frame: 0x0: 1 slot in a output frame; 0x1: 2 slots in a output frame...<br>0x1f: 32 slots(max slot number of one frame)  |
| `cfg_tx_0_channel_slot_size` | 2 | Select the tx channel 0 slot size, i.e. 0: 8 bits, 1: 16 bits, 2: 24 bits, 3: 32 bits |

### 6.3 TX Channel 0 Frame Enable Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_channel_frame_enable` | 32 | Select slots that are enabled inside one frame for tx channel 0 output stream, for example: 
32'b0000_0000_0000_0011: enable slot0 and slot1 inside one frame
32'b0000_0000_0000_0111: enable slot0, slot1, slot2 inside one frame
Setting bit N to enable slot N inside one frame, tx channel frame enable needs to be consecutive|

### 6.4 TX channel 0 Frame Format 0 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_0` | 4 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_1_slot_1` | 4 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_1_slot_2` | 4 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_1_slot_3` | 4 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_1_slot_4` | 4 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_1_slot_5` | 4 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_1_slot_6` | 4 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_1_slot_7` | 4 | Select which input channel data will be put in slot_7 of each frame |


### 6.5 TX channel 0 Frame Format 1 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_8` | 4 | Select which input channel data will be put in slot_8 of each frame |
| `cfg_tx_1_slot_9` | 4 | Select which input channel data will be put in slot_9 of each frame |
| `cfg_tx_1_slot_10` | 3 | Select which input channel data will be put in slot_10 of each frame |
| `cfg_tx_1_slot_11` | 3 | Select which input channel data will be put in slot_11 of each frame |
| `cfg_tx_1_slot_12` | 3 | Select which input channel data will be put in slot_12 of each frame |
| `cfg_tx_1_slot_13` | 3 | Select which input channel data will be put in slot_13 of each frame |
| `cfg_tx_1_slot_14` | 3 | Select which input channel data will be put in slot_14 of each frame |
| `cfg_tx_1_slot_15` | 3 | Select which input channel data will be put in slot_15 of each frame |

### 6.6 TX channel 0 Frame Format 2 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_16` | 4 | Select which input channel data will be put in slot_16 of each frame |
| `cfg_tx_1_slot_17` | 4 | Select which input channel data will be put in slot_17 of each frame |
| `cfg_tx_1_slot_18` | 3 | Select which input channel data will be put in slot_18 of each frame |
| `cfg_tx_1_slot_19` | 3 | Select which input channel data will be put in slot_19 of each frame |
| `cfg_tx_1_slot_20` | 3 | Select which input channel data will be put in slot_20 of each frame |
| `cfg_tx_1_slot_21` | 3 | Select which input channel data will be put in slot_21 of each frame |
| `cfg_tx_1_slot_22` | 3 | Select which input channel data will be put in slot_22 of each frame |
| `cfg_tx_1_slot_23` | 3 | Select which input channel data will be put in slot_23 of each frame |

### 6.7 TX channel 0 Frame Format 3 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_24` | 4 | Select which input channel data will be put in slot_24 of each frame |
| `cfg_tx_1_slot_25` | 4 | Select which input channel data will be put in slot_25 of each frame |
| `cfg_tx_1_slot_26` | 3 | Select which input channel data will be put in slot_26 of each frame |
| `cfg_tx_1_slot_27` | 3 | Select which input channel data will be put in slot_27 of each frame |
| `cfg_tx_1_slot_28` | 3 | Select which input channel data will be put in slot_28 of each frame |
| `cfg_tx_1_slot_29` | 3 | Select which input channel data will be put in slot_29 of each frame |
| `cfg_tx_1_slot_30` | 3 | Select which input channel data will be put in slot_30 of each frame |
| `cfg_tx_1_slot_31` | 3 | Select which input channel data will be put in slot_31 of each frame |

The output order of tx stream 0 is as follows, assume tx channel frame size is 8, enabling slot 0 to slot 7, slot size is 32 bits, which input stream is connected to each slot dependes on tx channel 0 frame format registers:

```text
Merged output:
| slot_0, slot_1, slot_2, slot_3, slot_4, slot_5, slot_6, slot_7, | slot_0, slot_1, slot_2, slot_3, slot_4, slot_5, slot_6, slot_7 ...
|                                                                 |  
Frame 1                                                           Frame 2
```
### 6.8 TX Channel 1 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_channel_src_sel` | 16 | Select rx source FIFO for channel 1 output stream |
| `cfg_tx_1_channel_frame_style` | 2 | Select tx channel output frame mode, 0: frame-interleave<br>1: block_interleave<br>2:planar mode |
| `cfg_tx_1_channel_block_size` | 5 | Select tx channel output frame interleaved block size, from 2 to 32 slots. For example: if configured 2, the interleave granularity is 2 slots for each input channel |
| `cfg_tx_1_channel_planar_len` | 5 | Select tx channel merged input channel frame size, from 2 to 32 slots. For example: if configured 2, the merged input frame slots is 2 slots |
| `cfg_tx_1_channel_frame_size` | 5 | Select the tx channel 1 frame size, i.e. cfg_tx_1_channel_frame_size + 1 slots inside each frame: 0x0: 1 slot in a output frame; 0x1: 2 slots in a output frame...<br>0x1f: 32 slots(max slot number of one frame)  |
| `cfg_tx_1_channel_slot_size` | 2 | Select the tx channel 1 slot size, i.e. 0: 8 bits, 1: 16 bits, 2: 24 bits, 3: 32 bits |

### 6.9 TX Channel 1 Frame Enable Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_channel_frame_enable` | 32 | Select slots that are enabled inside one frame for tx Channel 1 output stream, for example: 
32'b0000_0000_0000_0011: enable slot0 and slot1 inside one frame
32'b0000_0000_0000_0111: enable slot0, slot1, slot2 inside one frame
Setting bit N to enable slot N inside one frame, tx channel frame enable needs to be consecutive|

### 6.10 TX Channel 1 Frame Format 0 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_0` | 4 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_1_slot_1` | 4 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_1_slot_2` | 4 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_1_slot_3` | 4 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_1_slot_4` | 4 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_1_slot_5` | 4 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_1_slot_6` | 4 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_1_slot_7` | 4 | Select which input channel data will be put in slot_7 of each frame |


### 6.11 TX Channel 1 Frame Format 1 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_8` | 4 | Select which input channel data will be put in slot_8 of each frame |
| `cfg_tx_1_slot_9` | 4 | Select which input channel data will be put in slot_9 of each frame |
| `cfg_tx_1_slot_10` | 3 | Select which input channel data will be put in slot_10 of each frame |
| `cfg_tx_1_slot_11` | 3 | Select which input channel data will be put in slot_11 of each frame |
| `cfg_tx_1_slot_12` | 3 | Select which input channel data will be put in slot_12 of each frame |
| `cfg_tx_1_slot_13` | 3 | Select which input channel data will be put in slot_13 of each frame |
| `cfg_tx_1_slot_14` | 3 | Select which input channel data will be put in slot_14 of each frame |
| `cfg_tx_1_slot_15` | 3 | Select which input channel data will be put in slot_15 of each frame |

### 6.12 TX Channel 1 Frame Format 2 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_16` | 4 | Select which input channel data will be put in slot_16 of each frame |
| `cfg_tx_1_slot_17` | 4 | Select which input channel data will be put in slot_17 of each frame |
| `cfg_tx_1_slot_18` | 3 | Select which input channel data will be put in slot_18 of each frame |
| `cfg_tx_1_slot_19` | 3 | Select which input channel data will be put in slot_19 of each frame |
| `cfg_tx_1_slot_20` | 3 | Select which input channel data will be put in slot_20 of each frame |
| `cfg_tx_1_slot_21` | 3 | Select which input channel data will be put in slot_21 of each frame |
| `cfg_tx_1_slot_22` | 3 | Select which input channel data will be put in slot_22 of each frame |
| `cfg_tx_1_slot_23` | 3 | Select which input channel data will be put in slot_23 of each frame |

### 6.13 TX Channel 1 Frame Format 3 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_24` | 4 | Select which input channel data will be put in slot_24 of each frame |
| `cfg_tx_1_slot_25` | 4 | Select which input channel data will be put in slot_25 of each frame |
| `cfg_tx_1_slot_26` | 3 | Select which input channel data will be put in slot_26 of each frame |
| `cfg_tx_1_slot_27` | 3 | Select which input channel data will be put in slot_27 of each frame |
| `cfg_tx_1_slot_28` | 3 | Select which input channel data will be put in slot_28 of each frame |
| `cfg_tx_1_slot_29` | 3 | Select which input channel data will be put in slot_29 of each frame |
| `cfg_tx_1_slot_30` | 3 | Select which input channel data will be put in slot_30 of each frame |
| `cfg_tx_1_slot_31` | 3 | Select which input channel data will be put in slot_31 of each frame |

### 6.14 TX Channel 2 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_2_channel_src_sel` | 16 | Select rx source FIFO for channel 2 output stream |
| `cfg_tx_2_channel_frame_style` | 2 | Select tx channel output frame mode, 0: frame-interleave<br>1: block_interleave<br>2:planar mode |
| `cfg_tx_2_channel_block_size` | 5 | Select tx channel output frame interleaved block size, from 2 to 32 slots. For example: if configured 2, the interleave granularity is 2 slots for each input channel |
| `cfg_tx_2_channel_planar_len` | 5 | Select tx channel merged input channel frame size, from 2 to 32 slots. For example: if configured 2, the merged input frame slots is 2 slots |
| `cfg_tx_2_channel_frame_size` | 5 | Select the tx channel 2 frame size, i.e. cfg_tx_2_channel_frame_size + 1 slots inside each frame: 0x0: 1 slot in a output frame; 0x1: 2 slots in a output frame...<br>0x1f: 32 slots(max slot number of one frame)  |
| `cfg_tx_2_channel_slot_size` | 2 | Select the tx channel 2 slot size, i.e. 0: 8 bits, 1: 16 bits, 2: 24 bits, 3: 32 bits |

### 6.15 TX Channel 2 Frame Enable Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_channel_frame_enable` | 32 | Select slots that are enabled inside one frame for tx Channel 2 output stream, for example: 
32'b0000_0000_0000_0011: enable slot0 and slot1 inside one frame
32'b0000_0000_0000_0111: enable slot0, slot1, slot2 inside one frame
Setting bit N to enable slot N inside one frame, tx channel frame enable needs to be consecutive|

### 6.16 TX Channel 2 Frame Format 0 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_0` | 4 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_1_slot_1` | 4 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_1_slot_2` | 4 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_1_slot_3` | 4 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_1_slot_4` | 4 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_1_slot_5` | 4 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_1_slot_6` | 4 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_1_slot_7` | 4 | Select which input channel data will be put in slot_7 of each frame |


### 6.17 TX Channel 2 Frame Format 1 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_8` | 4 | Select which input channel data will be put in slot_8 of each frame |
| `cfg_tx_1_slot_9` | 4 | Select which input channel data will be put in slot_9 of each frame |
| `cfg_tx_1_slot_10` | 3 | Select which input channel data will be put in slot_10 of each frame |
| `cfg_tx_1_slot_11` | 3 | Select which input channel data will be put in slot_11 of each frame |
| `cfg_tx_1_slot_12` | 3 | Select which input channel data will be put in slot_12 of each frame |
| `cfg_tx_1_slot_13` | 3 | Select which input channel data will be put in slot_13 of each frame |
| `cfg_tx_1_slot_14` | 3 | Select which input channel data will be put in slot_14 of each frame |
| `cfg_tx_1_slot_15` | 3 | Select which input channel data will be put in slot_15 of each frame |

### 6.18 TX Channel 2 Frame Format 2 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_16` | 4 | Select which input channel data will be put in slot_16 of each frame |
| `cfg_tx_1_slot_17` | 4 | Select which input channel data will be put in slot_17 of each frame |
| `cfg_tx_1_slot_18` | 3 | Select which input channel data will be put in slot_18 of each frame |
| `cfg_tx_1_slot_19` | 3 | Select which input channel data will be put in slot_19 of each frame |
| `cfg_tx_1_slot_20` | 3 | Select which input channel data will be put in slot_20 of each frame |
| `cfg_tx_1_slot_21` | 3 | Select which input channel data will be put in slot_21 of each frame |
| `cfg_tx_1_slot_22` | 3 | Select which input channel data will be put in slot_22 of each frame |
| `cfg_tx_1_slot_23` | 3 | Select which input channel data will be put in slot_23 of each frame |

### 6.19 TX Channel 2 Frame Format 3 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_24` | 4 | Select which input channel data will be put in slot_24 of each frame |
| `cfg_tx_1_slot_25` | 4 | Select which input channel data will be put in slot_25 of each frame |
| `cfg_tx_1_slot_26` | 3 | Select which input channel data will be put in slot_26 of each frame |
| `cfg_tx_1_slot_27` | 3 | Select which input channel data will be put in slot_27 of each frame |
| `cfg_tx_1_slot_28` | 3 | Select which input channel data will be put in slot_28 of each frame |
| `cfg_tx_1_slot_29` | 3 | Select which input channel data will be put in slot_29 of each frame |
| `cfg_tx_1_slot_30` | 3 | Select which input channel data will be put in slot_30 of each frame |
| `cfg_tx_1_slot_31` | 3 | Select which input channel data will be put in slot_31 of each frame |

### 6.20 TX Channel 3 Merge Format Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_3_channel_src_sel` | 16 | Select rx source FIFO for channel 3 output stream |
| `cfg_tx_3_channel_frame_style` | 2 | Select tx channel output frame mode, 0: frame-interleave<br>1: block_interleave<br>2:planar mode |
| `cfg_tx_3_channel_block_size` | 5 | Select tx channel output frame interleaved block size, from 2 to 32 slots. For example: if configured 2, the interleave granularity is 2 slots for each input channel |
| `cfg_tx_3_channel_planar_len` | 5 | Select tx channel merged input channel frame size, from 2 to 32 slots. For example: if configured 2, the merged input frame slots is 2 slots |
| `cfg_tx_3_channel_frame_size` | 5 | Select the tx channel 3 frame size, i.e. cfg_tx_3_channel_frame_size + 1 slots inside each frame: 0x0: 1 slot in a output frame; 0x1: 2 slots in a output frame...<br>0x1f: 32 slots(max slot number of one frame)  |
| `cfg_tx_3_channel_slot_size` | 2 | Select the tx channel 3 slot size, i.e. 0: 8 bits, 1: 16 bits, 2: 24 bits, 3: 32 bits |

### 6.21 TX Channel 3 Frame Enable Register
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_0_channel_frame_enable` | 32 | Select slots that are enabled inside one frame for tx Channel 3 output stream, for example: 
32'b0000_0000_0000_0011: enable slot0 and slot1 inside one frame
32'b0000_0000_0000_0111: enable slot0, slot1, slot2 inside one frame
Setting bit N to enable slot N inside one frame, tx channel frame enable needs to be consecutive|

### 6.22 TX Channel 3 Frame Format 0 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_0` | 4 | Select which input channel data will be put in slot_0 of each frame |
| `cfg_tx_1_slot_1` | 4 | Select which input channel data will be put in slot_1 of each frame |
| `cfg_tx_1_slot_2` | 4 | Select which input channel data will be put in slot_2 of each frame |
| `cfg_tx_1_slot_3` | 4 | Select which input channel data will be put in slot_3 of each frame |
| `cfg_tx_1_slot_4` | 4 | Select which input channel data will be put in slot_4 of each frame |
| `cfg_tx_1_slot_5` | 4 | Select which input channel data will be put in slot_5 of each frame |
| `cfg_tx_1_slot_6` | 4 | Select which input channel data will be put in slot_6 of each frame |
| `cfg_tx_1_slot_7` | 4 | Select which input channel data will be put in slot_7 of each frame |


### 6.23 TX Channel 3 Frame Format 1 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_8` | 4 | Select which input channel data will be put in slot_8 of each frame |
| `cfg_tx_1_slot_9` | 4 | Select which input channel data will be put in slot_9 of each frame |
| `cfg_tx_1_slot_10` | 3 | Select which input channel data will be put in slot_10 of each frame |
| `cfg_tx_1_slot_11` | 3 | Select which input channel data will be put in slot_11 of each frame |
| `cfg_tx_1_slot_12` | 3 | Select which input channel data will be put in slot_12 of each frame |
| `cfg_tx_1_slot_13` | 3 | Select which input channel data will be put in slot_13 of each frame |
| `cfg_tx_1_slot_14` | 3 | Select which input channel data will be put in slot_14 of each frame |
| `cfg_tx_1_slot_15` | 3 | Select which input channel data will be put in slot_15 of each frame |

### 6.24 TX Channel 3 Frame Format 2 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_16` | 4 | Select which input channel data will be put in slot_16 of each frame |
| `cfg_tx_1_slot_17` | 4 | Select which input channel data will be put in slot_17 of each frame |
| `cfg_tx_1_slot_18` | 3 | Select which input channel data will be put in slot_18 of each frame |
| `cfg_tx_1_slot_19` | 3 | Select which input channel data will be put in slot_19 of each frame |
| `cfg_tx_1_slot_20` | 3 | Select which input channel data will be put in slot_20 of each frame |
| `cfg_tx_1_slot_21` | 3 | Select which input channel data will be put in slot_21 of each frame |
| `cfg_tx_1_slot_22` | 3 | Select which input channel data will be put in slot_22 of each frame |
| `cfg_tx_1_slot_23` | 3 | Select which input channel data will be put in slot_23 of each frame |

### 6.25 TX Channel 3 Frame Format 3 Regeister 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_tx_1_slot_24` | 4 | Select which input channel data will be put in slot_24 of each frame |
| `cfg_tx_1_slot_25` | 4 | Select which input channel data will be put in slot_25 of each frame |
| `cfg_tx_1_slot_26` | 3 | Select which input channel data will be put in slot_26 of each frame |
| `cfg_tx_1_slot_27` | 3 | Select which input channel data will be put in slot_27 of each frame |
| `cfg_tx_1_slot_28` | 3 | Select which input channel data will be put in slot_28 of each frame |
| `cfg_tx_1_slot_29` | 3 | Select which input channel data will be put in slot_29 of each frame |
| `cfg_tx_1_slot_30` | 3 | Select which input channel data will be put in slot_30 of each frame |
| `cfg_tx_1_slot_31` | 3 | Select which input channel data will be put in slot_31 of each frame |

### 6.26 RX FIFO Flush Register 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_rx_fifo_flush` | 16 | Each bit provides rx flush signal of each rx channel respectively |

### 6.27 RX FIFO Overflow Register 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_rx_fifo_overflow` | 16 | Each bit represents rx FIFO overflow each rx channel respectively |

### 6.28 TX FIFO Overflow Register 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_rx_fifo_overflow` | 4 | Each bit represents tx FIFO overflow each tx channel respectively |

### 6.29 TX FIFO Flush Register 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_rx_fifo_flush` | 4 | Each bit provides tx FIFO Flush for each tx channel respectively |

### 6.30 RX channal 0 IDLE Count Register 
| Sigal | Width | Description |
|---|---:|---|
| `cfg_rx_0_idle_count` | 32 | When RX channel 0 is enabled, if RX channel 0 does not receive valid data for cfg_rx_0_idle_count merge_clk cycles, assert rx channel 0 timeout interrupt |

---

## 7. FSM Design
refer to merge.draw.io

# 8. Future Design Discussion 
The IP does not append `slot_id`, `slot_valid`, or frame metadata to the stream.
