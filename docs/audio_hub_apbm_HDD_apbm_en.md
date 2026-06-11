# Audio Hub APBM HDD

## 1. 模块概述

`audio_hub_i2s_apbm` 是 Audio Hub 中面向单个 `DWC_i2s / DW_i2s` Controller 的独立 APB Master 模块。

该模块位于：

```text
Crossbar / Audio Processing Blocks
        ↕
audio_hub_i2s_apbm
        ↕
DWC_i2s Controller APB Slave
```

APBM 的核心职责是将 `DWC_i2s` 的 DMA handshake 语义转换成 Audio Hub 内部的 streaming 接口。

## 2. 功能描述

### 2.1 RX 方向

RX 方向表示从 I2S Controller 接收数据，并送入 Audio Hub Crossbar。

数据流：

```text
DWC_i2s RX FIFO
    ↓ APB read RXDATA
APBM
    ↓ rx_valid / rx_ready / rx_data
Crossbar
    ↓
DG / Mixer / Merge / DMA endpoint
```

流程：

1. `DWC_i2s` 拉起 `i2s_dma_rx_req`。
2. APBM 发起 APB Read，从 `I2S_RXDATA_ADDR` 读取一个 sample。
3. APBM 将读取到的数据保存到内部寄存器。
4. APBM 通过 `rx_valid` / `rx_data` 向 Crossbar 发送数据。
5. Crossbar 通过 `rx_ready` 接收数据。
6. APBM 向 `DWC_i2s` 返回 `i2s_dma_rx_ack`。

### 2.2 TX 方向

TX 方向表示从 Audio Hub Crossbar 取数据，并写入 I2S Controller。

数据流：

```text
Crossbar
    ↓ tx_valid / tx_ready / tx_data
APBM
    ↓ APB write TXDATA
DWC_i2s TX FIFO
```

流程：

1. `DWC_i2s` 拉起 `i2s_dma_tx_req`。
2. APBM 向 Crossbar 拉起 `tx_ready`。
3. Crossbar 通过 `tx_valid` / `tx_data` 返回一个 sample。
4. APBM 将 sample 写入 `I2S_TXDATA_ADDR`。
5. APB write 完成后，APBM 向 `DWC_i2s` 返回 `i2s_dma_tx_ack`。

### 2.3 Bypass 支持

系统级架构中 APBM 可支持 bypass 模式：

```text
apbm_en = 0:
    DMA / ABUS 直接访问 DWC_i2s，APBM 内部 RX/TX FSM 保持 idle

apbm_en = 1:
    APBM 接管 DWC_i2s APB data path 与 DMA handshake path
```

本 HDD 主要描述 `apbm_en = 1` 时 APBM 的核心工作模式。

Bypass 模式下，APBM 不访问 Crossbar，也不执行 RX/TX FSM，而是将外部 ABUS/DMA 侧 APB 与 DMA handshake 直接透传到 DWC_i2s。此时 APBM 等价于一个旁路 mux。

### 2.4 推荐微架构

面向 tapeout 的推荐微架构为：

```text
audio_hub_i2s_apbm
├── rx_fsm
├── tx_fsm
├── apb_arbiter
├── bypass_mux
├── status
└── perf_counter
```

其中：

- RX FSM 负责 I2S RXDATA APB read 与 Crossbar RX stream push。
- TX FSM 负责 Crossbar TX stream pop 与 I2S TXDATA APB write。
- APB Arbiter 负责仲裁 RX/TX 对 DWC_i2s APB master port 的访问。
- Bypass Mux 负责 process mode 与 bypass mode 的数据路径切换。

## 3. 状态机描述

### 3.1 RX FSM

```text
RX_IDLE
    ↓ i2s_dma_rx_req && rx_ready
RX_APB_READ
    ↓ pready
RX_STREAM
    ↓ rx_ready
RX_ACK
    ↓
RX_IDLE
```

### 3.2 TX FSM

```text
TX_IDLE
    ↓ i2s_dma_tx_req
TX_WAIT_DATA
    ↓ tx_valid
TX_APB_WRITE
    ↓ pready
TX_ACK
    ↓
TX_IDLE
```

### 3.3 APB Master 时序

APB read：

```text
SETUP:
    psel    = 1
    penable = 0
    pwrite  = 0
    paddr   = I2S_RXDATA_ADDR

ACCESS:
    psel    = 1
    penable = 1
    wait pready
```

APB write：

```text
SETUP:
    psel    = 1
    penable = 0
    pwrite  = 1
    paddr   = I2S_TXDATA_ADDR
    pwdata  = tx_sample

ACCESS:
    psel    = 1
    penable = 1
    wait pready
```

## 4. 参数列表

| 参数名 | 默认值 | 描述 |
|---|---:|---|
| `APB_ADDR_W` | 32 | APB 地址宽度 |
| `APB_DATA_W` | 32 | APB 数据宽度 |
| `I2S_BASE_ADDR` | `32'h0000_0000` | 当前 DWC_i2s Controller 的 APB base address |
| `I2S_RXDATA_OFF` | `32'h0000_0000` | DWC_i2s RXDATA register offset |
| `I2S_TXDATA_OFF` | `32'h0000_0004` | DWC_i2s TXDATA register offset |
| `RX_FIRST` | 1 | RX/TX 同时请求时，是否优先服务 RX |
| `BYPASS_EN` | 1 | 是否综合 bypass 数据通路，1 表示支持 bypass |

## 5. 端口列表

### 5.1 Clock / Reset / Control

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `clk` | input | 1 | APBM 工作时钟 |
| `rst_n` | input | 1 | 异步低有效复位 |
| `apbm_en` | input | 1 | APBM 接管模式使能，1 表示 APBM 接管 DWC_i2s，0 表示 bypass 直通 |
| `rx_en` | input | 1 | RX path 使能 |
| `tx_en` | input | 1 | TX path 使能 |

### 5.2 DWC_i2s DMA Handshake Interface

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `i2s_dma_rx_req` | input | 1 | 来自 DWC_i2s 的 RX DMA request |
| `i2s_dma_rx_ack` | output | 1 | 返回给 DWC_i2s 的 RX DMA acknowledge |
| `i2s_dma_tx_req` | input | 1 | 来自 DWC_i2s 的 TX DMA request |
| `i2s_dma_tx_ack` | output | 1 | 返回给 DWC_i2s 的 TX DMA acknowledge |

### 5.3 APB Master Interface to DWC_i2s

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `psel` | output | 1 | APB select |
| `penable` | output | 1 | APB enable |
| `pwrite` | output | 1 | APB write enable，1 表示写，0 表示读 |
| `paddr` | output | `APB_ADDR_W` | APB address |
| `pwdata` | output | `APB_DATA_W` | APB write data |
| `prdata` | input | `APB_DATA_W` | APB read data |
| `pready` | input | 1 | APB ready |
| `pslverr` | input | 1 | APB slave error |

### 5.4 RX Stream Interface to Crossbar

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `rx_valid` | output | 1 | APBM 向 Crossbar 发送 RX sample valid |
| `rx_ready` | input | 1 | Crossbar 可接收 RX sample |
| `rx_data` | output | `APB_DATA_W` | RX sample data |

握手规则：

```text
rx_valid && rx_ready = 1 时，rx_data 被 Crossbar 接收。
```

### 5.5 TX Stream Interface from Crossbar

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `tx_valid` | input | 1 | Crossbar 提供 TX sample valid |
| `tx_ready` | output | 1 | APBM 可接收 TX sample |
| `tx_data` | input | `APB_DATA_W` | TX sample data |

握手规则：

```text
tx_valid && tx_ready = 1 时，APBM 接收 tx_data。
```


### 5.6 Bypass APB Interface

Bypass 端口用于 `apbm_en = 0` 时，将外部 ABUS/DMA 的 APB 访问直接送到 DWC_i2s APB slave。

#### Bypass input from ABUS / DMA side

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `byp_psel` | input | 1 | Bypass APB select from ABUS/DMA |
| `byp_penable` | input | 1 | Bypass APB enable from ABUS/DMA |
| `byp_pwrite` | input | 1 | Bypass APB write from ABUS/DMA |
| `byp_paddr` | input | `APB_ADDR_W` | Bypass APB address from ABUS/DMA |
| `byp_pwdata` | input | `APB_DATA_W` | Bypass APB write data from ABUS/DMA |
| `byp_prdata` | output | `APB_DATA_W` | Bypass APB read data returned to ABUS/DMA |
| `byp_pready` | output | 1 | Bypass APB ready returned to ABUS/DMA |
| `byp_pslverr` | output | 1 | Bypass APB slave error returned to ABUS/DMA |

#### Bypass DMA handshake from ABUS / DMA side

| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `byp_dma_rx_req` | output | 1 | Bypass 模式下输出给外部 DMA 的 RX request |
| `byp_dma_rx_ack` | input | 1 | Bypass 模式下来自外部 DMA 的 RX acknowledge |
| `byp_dma_tx_req` | output | 1 | Bypass 模式下输出给外部 DMA 的 TX request |
| `byp_dma_tx_ack` | input | 1 | Bypass 模式下来自外部 DMA 的 TX acknowledge |

#### Bypass mux behavior

当 `apbm_en = 0` 时：

```text
byp_psel    -> psel
byp_penable -> penable
byp_pwrite  -> pwrite
byp_paddr   -> paddr
byp_pwdata  -> pwdata

prdata      -> byp_prdata
pready      -> byp_pready
pslverr     -> byp_pslverr

i2s_dma_rx_req -> byp_dma_rx_req
byp_dma_rx_ack -> i2s_dma_rx_ack

i2s_dma_tx_req -> byp_dma_tx_req
byp_dma_tx_ack -> i2s_dma_tx_ack
```

当 `apbm_en = 1` 时：

```text
APBM RX/TX FSM drives DWC_i2s APB master signals.
Bypass APB response should return idle-safe value:
    byp_prdata  = 0
    byp_pready  = 1
    byp_pslverr = 0

byp_dma_rx_req = 0
byp_dma_tx_req = 0
```

### 5.7 Status Interface


| 端口名 | 方向 | 位宽 | 描述 |
|---|---|---:|---|
| `busy` | output | 1 | APBM 当前不在 IDLE 状态 |
| `err_sticky` | output | 1 | sticky error 标志，检测到 APB `pslverr` 后置位 |

## 6. 端口方向示意

```text
                        +----------------------+
                        | audio_hub_i2s_apbm   |
                        |                      |
DWC_i2s dma_rx_req ---->|                      |----> rx_valid
DWC_i2s dma_tx_req ---->|                      |----> rx_data
DWC_i2s dma_rx_ack <----|                      |<---- rx_ready
DWC_i2s dma_tx_ack <----|                      |
                        |                      |<---- tx_valid
                        |                      |<---- tx_data
DWC_i2s APB slave  <----| APB Master           |----> tx_ready
ABUS/DMA bypass   <---->| Bypass APB/HS Mux    |
                        +----------------------+
```

## 7. 错误处理

### 7.1 APB Slave Error

当检测到：

```verilog
psel && penable && pready && pslverr
```

APBM 将置位：

```text
err_sticky = 1
```

该标志保持到模块复位或软件清除，具体清除方式由顶层 CSR 设计决定。

### 7.2 Crossbar Backpressure

RX 方向：

```text
rx_valid = 1 && rx_ready = 0
```

表示 Crossbar 暂时无法接收数据，APBM 保持 RX sample，不返回 `i2s_dma_rx_ack`。

TX 方向：

```text
tx_ready = 1 && tx_valid = 0
```

表示 Crossbar 暂时没有可用 TX sample，APBM 不发起 I2S TXDATA APB write。

## 8. 设计约束与假设

1. APBM 与 DWC_i2s APB slave 位于同一时钟域。
2. Crossbar 与 APBM 位于同一时钟域。
3. 若跨时钟域，需要在 Crossbar 侧或 APBM 侧插入 async FIFO。
4. 每次 DWC_i2s DMA request 默认服务一个 APB word。
5. 若 DWC_i2s 配置为多 channel 或 TDM 模式，需要扩展 address generation。
6. `i2s_dma_rx_ack` / `i2s_dma_tx_ack` 默认为单周期 pulse。
7. `APB_DATA_W` 默认等于 audio sample container width。
8. Bypass 模式下 APBM 不应同时驱动 APB FSM，DWC_i2s APB 只允许一个 master 来源。

## 9. 后续扩展

| 功能 | 描述 |
|---|---|
| RX/TX dual FSM | RX/TX 独立调度，提高并发能力 |
| APB arbiter | 仲裁 RX/TX FSM 对单一 APB master port 的访问 |
| timeout counter | 检测 APB 或 Crossbar 长时间无响应 |
| performance counter | 统计 RX/TX sample 数、stall cycle、error 次数 |
| TDM channel mapper | 支持多 channel / TDM slot 到 Crossbar stream 的映射 |
| bypass mux | 支持原始 DMA/ABUS 直连 DWC_i2s |
| interrupt source | 将 underflow/overflow/stall/error 上报到 CSR |

## 10. 命名规则

本模块统一使用 `apbm_en` 表示 APBM 接管模式使能。

| 信号名 | 含义 |
|---|---|
| `apbm_en = 0` | Bypass 模式，ABUS/DMA 直接访问 DWC_i2s |
| `apbm_en = 1` | APBM 接管模式，APBM 访问 DWC_i2s 并连接 Crossbar |

不再使用 `process_en` 命名，避免与 DG/Mixer 等 audio processing block 的 enable 信号混淆。
