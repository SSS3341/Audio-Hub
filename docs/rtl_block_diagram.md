# RTL Block Diagram

## Top-level architecture

```mermaid
flowchart LR
    subgraph DWC["Synopsys DWC_i2s"]
        RXFIFO["RX FIFO / RXDATA"]
        TXFIFO["TX FIFO / TXDATA"]
    end

    subgraph HUB["DWC I2S Audio Hub"]
        subgraph APB["APB Slave + Register File"]
            REG["CTRL / GAIN / MIXER / STATUS / IRQ"]
            RXDATA["RXDATA read port"]
            TXDATA["TXDATA write port"]
        end

        subgraph RXPATH["RX Path"]
            RXADP["DWC_i2s RX Adapter"]
            RXGAIN["RX Digital Gain"]
            RXMIXTAP["RX Mixer Tap / Bypass"]
            RXOFIFO["RX Output FIFO"]
        end

        subgraph TXPATH["TX Path"]
            TXIFIFO["TX Input FIFO"]
            TXGAIN0["TX Digital Gain CH0"]
            TXGAIN1["TX Digital Gain CH1 / Aux"]
            MIXER["2-input Saturating Mixer"]
            TXADP["DWC_i2s TX Adapter"]
        end

        DMAREQ["DMA Request Generator"]
    end

    subgraph DMA["DMA Controller"]
        DMARX["RX DMA Channel"]
        DMATX["TX DMA Channel"]
    end

    subgraph MEM["DDR / SRAM"]
        DDRRX["Capture Buffer"]
        DDRTX["Playback Buffer"]
    end

    RXFIFO --> RXADP --> RXGAIN --> RXMIXTAP --> RXOFIFO --> RXDATA --> DMARX --> DDRRX
    DDRTX --> DMATX --> TXDATA --> TXIFIFO --> TXGAIN0 --> MIXER --> TXADP --> TXFIFO
    TXGAIN1 --> MIXER

    REG --> RXGAIN
    REG --> TXGAIN0
    REG --> TXGAIN1
    REG --> MIXER
    RXOFIFO --> DMAREQ
    TXIFIFO --> DMAREQ
    DMAREQ --> DMARX
    DMAREQ --> DMATX
```

## DMA endpoint model

```text
RX DMA source      = AUDIO_HUB_BASE + RXDATA
TX DMA destination = AUDIO_HUB_BASE + TXDATA

RX source increment = fixed
TX destination increment = fixed
```

## Processing order

```text
RX: DWC_i2s -> gain -> optional mixer tap/bypass -> DMA
TX: DMA -> gain -> mixer -> DWC_i2s
```
