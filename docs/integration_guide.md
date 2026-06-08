# Integration Guide

## DWC_i2s side

The hub intentionally separates DWC_i2s adapter logic from DMA endpoint logic.

Expected DWC_i2s-facing abstract interface:

```text
RX:
dwc_rx_valid
dwc_rx_data
dwc_rx_ready

TX:
dwc_tx_valid
dwc_tx_data
dwc_tx_ready
```

For APB-register-only DWC_i2s integration, implement the adapter as an APB master or local bus client that reads DWC_i2s RXDATA and writes DWC_i2s TXDATA according to FIFO status and request signals.

## DMA side

DMA should be programmed to access this hub, not DWC_i2s directly.

```text
RX DMA:
src  = AUDIO_HUB_BASE + 0x030
dst  = memory buffer
src increment = fixed
dst increment = increment

TX DMA:
src  = memory buffer
dst  = AUDIO_HUB_BASE + 0x034
src increment = increment
dst increment = fixed
```

## Recommended SoC integration

- Put DWC_i2s adapter and APB/DMA endpoint in the same clock domain when possible.
- If I2S and APB/DMA clocks differ, replace sync FIFOs with async FIFOs.
- Add CDC constraints and run CDC signoff.
- Assign audio DMA channels higher QoS than bulk low-priority traffic.
