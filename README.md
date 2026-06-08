# DWC I2S Audio Hub

Tapeout-oriented RTL skeleton for inserting audio processing between Synopsys `DWC_i2s` and a Synopsys-style DMA controller.

## Target architecture

The hub becomes the DMA endpoint.

```text
RX:
DWC_i2s RX FIFO -> I2S RX Adapter -> RX Gain -> RX Mixer Tap -> RX FIFO -> APB RXDATA -> DMA -> DDR

TX:
DDR -> DMA -> APB TXDATA -> TX FIFO -> TX Gain -> TX Mixer -> I2S TX Adapter -> DWC_i2s TX FIFO
```

## Main features

- APB slave register interface
- Fixed-address DMA RXDATA/TXDATA endpoint
- Re-generated DMA request signals
- Independent RX/TX gain
- 2-input TX mixer skeleton
- FIFO watermark control
- Sticky interrupt/status flags
- Tapeout-oriented filelist, docs, constraints placeholders

## Important integration note

This repo is a production-style RTL starting point, not a signoff-complete IP. Before tapeout, complete CDC strategy, reset strategy, DFT insertion, formal/lint/CDC/RDC, UVM verification, low-power intent, and timing constraints for your SoC.
