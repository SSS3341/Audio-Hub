# Audio Hub APBM HDD Addendum - Complete Port List

## Recommended Complete Port List

### Clock / Reset

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | I | 1 | APBM clock |
| rst_n | I | 1 | Active-low reset |

### Control Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| apbm_en | I | 1 | 1: APBM mode, 0: bypass mode |
| rx_en | I | 1 | RX path enable |
| tx_en | I | 1 | TX path enable |
| src_msize | I | 5 | RX burst size control |
| soft_flush | I | 1 | Flush APBM internal state |

### DWC_i2s DMA Handshake Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| i2s_dma_rx_req | I | 1 | RX DMA request from DWC_i2s |
| i2s_dma_rx_ack | O | 1 | RX DMA acknowledge to DWC_i2s |
| i2s_dma_tx_req | I | 1 | TX DMA request from DWC_i2s |
| i2s_dma_tx_ack | O | 1 | TX DMA acknowledge to DWC_i2s |

### APB Master Interface Toward DWC_i2s

| Port | Dir | Width |
|------|-----|-------|
| psel | O | 1 |
| penable | O | 1 |
| pwrite | O | 1 |
| paddr | O | APB_ADDR_W |
| pwdata | O | APB_DATA_W |
| prdata | I | APB_DATA_W |
| pready | I | 1 |
| pslverr | I | 1 |

### RX Stream Output Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| rx_valid | O | 1 | RX stream valid |
| rx_ready | I | 1 | Destination ready |
| rx_data | O | APB_DATA_W | RX sample |
| rx_last | O | 1 | Last sample of burst |

### TX Stream Input Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| tx_valid | I | 1 | TX stream valid |
| tx_ready | O | 1 | APBM ready |
| tx_data | I | APB_DATA_W | TX sample |
| tx_last | I | 1 | Reserved for future burst TX |

### Bypass APB Interface

| Port | Dir | Width |
|------|-----|-------|
| byp_psel | I | 1 |
| byp_penable | I | 1 |
| byp_pwrite | I | 1 |
| byp_paddr | I | APB_ADDR_W |
| byp_pwdata | I | APB_DATA_W |
| byp_prdata | O | APB_DATA_W |
| byp_pready | O | 1 |
| byp_pslverr | O | 1 |

### Bypass DMA Interface

| Port | Dir | Width |
|------|-----|-------|
| byp_dma_rx_req | O | 1 |
| byp_dma_rx_ack | I | 1 |
| byp_dma_tx_req | O | 1 |
| byp_dma_tx_ack | I | 1 |

### Status / Debug Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| busy | O | 1 | APBM busy |
| rx_busy | O | 1 | RX FSM busy |
| tx_busy | O | 1 | TX FSM busy |
| err_sticky | O | 1 | Sticky error flag |
| perf_rx_cnt | O | 32 | RX transaction counter |
| perf_tx_cnt | O | 32 | TX transaction counter |
| perf_stall_cnt | O | 32 | Stall counter |
| perf_apb_err_cnt | O | 32 | APB error counter |

## HDD Integration Recommendation

Replace Section 13 of the complete HDD with the tables above. These ports reflect:
- APBM mode and bypass mode
- RX burst support via src_msize
- AXI-stream style interfaces
- Future tapeout debug/performance hooks
