# Audio Hub APBM HDD
## High Level Design Document

### Revision
| Version | Description |
|----------|-------------|
| v1.0 | Initial tapeout-oriented HDD |

# 1. Feature List

## Functional Features

| ID | Feature |
|----|---------|
| F01 | DWC_i2s APB Master |
| F02 | RX DMA Request Service |
| F03 | TX DMA Request Service |
| F04 | AXI-Stream Style RX Interface |
| F05 | AXI-Stream Style TX Interface |
| F06 | RX Burst Read via src_msize |
| F07 | rx_last Generation |
| F08 | Backpressure Support |
| F09 | APB Error Detection |
| F10 | Sticky Error Status |
| F11 | RX/TX Arbitration |
| F12 | Skid Buffer Support |
| F13 | Bypass Mode |
| F14 | APBM Mode |
| F15 | Multi-I2S Scalable Architecture |

# 2. Overview

audio_hub_apbm 是 Audio Hub 中面向单个 Synopsys DWC_i2s Controller 的独立模块。

```text
             DWC_i2s
                |
        dma_req/ack
                |
              APBM
                |
      valid/ready/data/last
                |
            Crossbar
                |
       DG / Mixer / Merge
```

APBM负责：

- 接收 DWC_i2s dma_rx_req / dma_tx_req
- APB Read RXDATA
- APB Write TXDATA
- Stream化接口输出到Crossbar
- 支持RX Burst聚合
- 支持Bypass模式

# 3. Architecture

推荐微架构：

```text
audio_hub_apbm
├── rx_fsm
├── tx_fsm
├── apb_arbiter
├── bypass_mux
├── skid_buffer
├── perf_counter
└── error_monitor
```

# 4. Operating Modes

## 4.1 APBM Mode

```text
apbm_en = 1
```

APBM接管DWC_i2s。

RX:

```text
DWC_i2s RXDATA
   ↓
 APBM
   ↓
 Crossbar
```

TX:

```text
Crossbar
   ↓
 APBM
   ↓
DWC_i2s TXDATA
```

## 4.2 Bypass Mode

```text
apbm_en = 0
```

```text
ABUS/DMA
    ↓
Bypass Mux
    ↓
DWC_i2s
```

APBM内部FSM保持Idle。

# 5. Functional Description

## 5.1 RX Path

```text
i2s_dma_rx_req
      ↓
RX Burst Read
      ↓
RX Stream Output
      ↓
i2s_dma_rx_ack
```

## 5.2 TX Path

```text
i2s_dma_tx_req
      ↓
TX Stream Input
      ↓
APB Write TXDATA
      ↓
i2s_dma_tx_ack
```

# 6. RX Burst Mechanism

新增输入：

```verilog
input [4:0] src_msize;
```

定义：

```text
burst_length = 2 ^ src_msize
```

例：

| src_msize | burst_length |
|------------|-------------|
| 0 | 1 |
| 1 | 2 |
| 2 | 4 |
| 3 | 8 |
| 4 | 16 |

收到一次：

```text
i2s_dma_rx_req
```

执行：

```text
burst_length 次 APB Read
```

全部完成后：

```text
i2s_dma_rx_ack
```

# 7. Stream Interface

## RX Stream

| Signal | Dir | Description |
|----------|------|-------------|
| rx_valid | O | RX sample valid |
| rx_ready | I | Destination ready |
| rx_data | O | RX sample |
| rx_last | O | Burst last sample |

## TX Stream

| Signal | Dir | Description |
|----------|------|-------------|
| tx_valid | I | TX sample valid |
| tx_ready | O | APBM ready |
| tx_data | I | TX sample |
| tx_last | I | Reserved |

# 8. Ready/Valid Timing

正常情况：

```text
clk

valid   1 1 1
ready   1 1 1
data    A B C
```

Backpressure：

```text
clk

valid   1 1 1 1
ready   1 0 0 1
data    A B B B
```

当：

```text
valid=1
ready=0
```

APBM保持sample不变。

# 9. RX Ready Source

Crossbar不产生ready。

ready最终来源于目标模块：

```text
APBM
  ↓
Crossbar
  ↓
DG
```

则：

```text
rx_ready = dg_rx_ready
```

同理：

```text
rx_ready = mixer_rx_ready
rx_ready = merge_rx_ready
```

Crossbar负责回传。

# 10. Crossbar Requirements

Crossbar职责：

```text
Route
Arbitrate
Forward
```

Crossbar不负责：

```text
FIFO
Buffer
Cache
```

缓存应位于：

```text
DG
Mixer
Merge
DMA Endpoint
```

# 11. FSM Description

## RX FSM

```text
RX_IDLE
   ↓
RX_LOAD_BURST
   ↓
RX_APB_READ
   ↓
RX_STREAM
   ↓
RX_BURST_DONE ?

 No → RX_APB_READ
 Yes → RX_ACK

RX_ACK
   ↓
RX_IDLE
```

## TX FSM

```text
TX_IDLE
   ↓
TX_WAIT_DATA
   ↓
TX_APB_WRITE
   ↓
TX_ACK
   ↓
TX_IDLE
```

# 12. Parameters

| Parameter | Description |
|------------|-------------|
| APB_ADDR_W | APB Address Width |
| APB_DATA_W | APB Data Width |
| I2S_BASE_ADDR | DWC_i2s Base Address |
| I2S_RXDATA_OFF | RXDATA Offset |
| I2S_TXDATA_OFF | TXDATA Offset |
| RX_FIRST | RX Priority Enable |

# 13. Port Description

## Control

| Port | Dir | Width | Description |
|--------|-----|-------|-------------|
| clk | I | 1 | Clock |
| rst_n | I | 1 | Reset |
| apbm_en | I | 1 | APBM Enable |
| rx_en | I | 1 | RX Enable |
| tx_en | I | 1 | TX Enable |
| src_msize | I | 5 | RX Burst Size |

## DWC_i2s DMA Interface

| Port | Dir |
|--------|-----|
| i2s_dma_rx_req | I |
| i2s_dma_rx_ack | O |
| i2s_dma_tx_req | I |
| i2s_dma_tx_ack | O |

## APB Master Interface

| Port | Dir |
|--------|-----|
| psel | O |
| penable | O |
| pwrite | O |
| paddr | O |
| pwdata | O |
| prdata | I |
| pready | I |
| pslverr | I |

## Bypass Interface

| Port | Dir |
|--------|-----|
| byp_psel | I |
| byp_penable | I |
| byp_pwrite | I |
| byp_paddr | I |
| byp_pwdata | I |
| byp_prdata | O |
| byp_pready | O |
| byp_pslverr | O |

# 14. Error Handling

检测：

```verilog
psel && penable && pready && pslverr
```

置位：

```text
err_sticky
```

# 15. Design Assumptions

1. APBM与DWC_i2s位于同一时钟域。
2. Crossbar与APBM位于同一时钟域。
3. 若跨时钟域需增加Async FIFO。
4. 一个DMA Request对应一个Burst。
5. ACK为单周期Pulse。
6. APB_DATA_W与Sample Container Width一致。

# 16. Future Extensions

- TDM8/TDM16 Support
- Multi-channel Mapper
- Timeout Counter
- Performance Counter
- Interrupt Source
- Dynamic Routing
- Multicast/Broadcast Crossbar Support
