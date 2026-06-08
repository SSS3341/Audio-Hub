# Tapeout Checklist

## RTL

- [ ] No inferred latches
- [ ] No unreset control flops
- [ ] FIFO overflow/underflow protected
- [ ] Parameter combinations compile
- [ ] APB protocol assertions pass
- [ ] DMA fixed-address burst behavior verified
- [ ] Saturation arithmetic verified for min/max samples
- [ ] Stereo/TDM packing verified for target DWC_i2s mode

## Verification

- [ ] APB register test
- [ ] RX capture directed test
- [ ] TX playback directed test
- [ ] Simultaneous RX/TX stress test
- [ ] FIFO full/empty corner cases
- [ ] Backpressure randomization
- [ ] Gain saturation and bypass tests
- [ ] Mixer overflow saturation tests
- [ ] DMA burst length sweep
- [ ] Reset during active transfer

## Signoff

- [ ] Lint clean or waived
- [ ] CDC clean or waived
- [ ] RDC clean or waived
- [ ] SDC reviewed
- [ ] DFT scan compatibility reviewed
- [ ] UPF/CPF reviewed if power-gated
- [ ] STA clean across modes/corners
