# Register Map

All registers are 32-bit APB registers.

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x000 | CTRL | RW | Global enable and soft reset |
| 0x004 | RX_CFG | RW | RX path enable, sample width, format |
| 0x008 | TX_CFG | RW | TX path enable, sample width, format |
| 0x00C | DMA_CFG | RW | RX/TX watermark thresholds |
| 0x010 | RX_GAIN | RW | RX gain Q1.15 |
| 0x014 | TX_GAIN0 | RW | TX main gain Q1.15 |
| 0x018 | TX_GAIN1 | RW | TX aux/mixer gain Q1.15 |
| 0x01C | MIX_CFG | RW | Mixer enable and source select |
| 0x020 | STATUS | RO | FIFO empty/full and enable status |
| 0x024 | IRQ_STATUS | W1C | Sticky underflow/overflow flags |
| 0x028 | IRQ_ENABLE | RW | Interrupt enable mask |
| 0x030 | RXDATA | RO | DMA reads processed RX data; read pops RX FIFO |
| 0x034 | TXDATA | WO | DMA writes TX data; write pushes TX FIFO |

## CTRL

| Bit | Name | Description |
|---:|---|---|
| 0 | HUB_EN | Global enable |
| 1 | RX_EN | RX path enable |
| 2 | TX_EN | TX path enable |
| 4 | SOFT_RST | Self-clearing soft reset request |

## DMA_CFG

| Bits | Name | Description |
|---:|---|---|
| 7:0 | RX_WM | RX DMA request asserted when RX FIFO level >= RX_WM |
| 15:8 | TX_WM | TX DMA request asserted when TX FIFO level <= TX_WM |

## DMA request behavior

```verilog
dma_rx_req = rx_fifo_level >= rx_wm;
dma_tx_req = tx_fifo_level <= tx_wm;
```
