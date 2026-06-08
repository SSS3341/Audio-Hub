`include "audio_hub_defs.svh"

module dwc_i2s_audio_hub_top #(
    parameter int APB_ADDR_W = 12,
    parameter int DATA_W     = 32,
    parameter int SAMPLE_W   = 24,
    parameter int FIFO_DEPTH = 32,
    parameter int FIFO_AW    = $clog2(FIFO_DEPTH)
)(
    input  logic                  pclk,
    input  logic                  presetn,

    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [APB_ADDR_W-1:0] paddr,
    input  logic [DATA_W-1:0]     pwdata,
    output logic [DATA_W-1:0]     prdata,
    output logic                  pready,
    output logic                  pslverr,

    // Abstract DWC_i2s RX adapter interface
    input  logic                  dwc_rx_valid,
    output logic                  dwc_rx_ready,
    input  logic [DATA_W-1:0]     dwc_rx_data,

    // Abstract DWC_i2s TX adapter interface
    output logic                  dwc_tx_valid,
    input  logic                  dwc_tx_ready,
    output logic [DATA_W-1:0]     dwc_tx_data,

    // DMA handshake outputs
    output logic                  dma_rx_req,
    output logic                  dma_tx_req,

    output logic                  irq
);

    logic hub_en, rx_en, tx_en, soft_rst_pulse;
    logic [7:0] rx_wm, tx_wm;
    logic signed [15:0] rx_gain_q, tx_gain0_q, tx_gain1_q;
    logic mix_en;
    logic [7:0] irq_en;

    logic apb_rx_pop;
    logic apb_tx_push;
    logic [DATA_W-1:0] rxdata_rdata;
    logic [DATA_W-1:0] txdata_wdata;

    logic [FIFO_AW:0] rx_level_w, tx_level_w;
    logic rx_full, rx_empty, tx_full, tx_empty;
    logic rx_overflow, tx_underflow;

    logic flush;
    assign flush = soft_rst_pulse || !hub_en;

    audio_hub_rx_path #(
        .DATA_W(DATA_W), .SAMPLE_W(SAMPLE_W), .FIFO_DEPTH(FIFO_DEPTH)
    ) u_rx_path (
        .clk(pclk),
        .rst_n(presetn),
        .flush(flush),
        .enable(hub_en && rx_en),
        .gain_q(rx_gain_q),
        .dwc_rx_valid(dwc_rx_valid),
        .dwc_rx_ready(dwc_rx_ready),
        .dwc_rx_data(dwc_rx_data),
        .apb_rx_pop(apb_rx_pop),
        .apb_rx_data(rxdata_rdata),
        .level(rx_level_w),
        .full(rx_full),
        .empty(rx_empty),
        .overflow(rx_overflow)
    );

    audio_hub_tx_path #(
        .DATA_W(DATA_W), .SAMPLE_W(SAMPLE_W), .FIFO_DEPTH(FIFO_DEPTH)
    ) u_tx_path (
        .clk(pclk),
        .rst_n(presetn),
        .flush(flush),
        .enable(hub_en && tx_en),
        .gain0_q(tx_gain0_q),
        .gain1_q(tx_gain1_q),
        .mix_en(mix_en),
        .apb_tx_push(apb_tx_push),
        .apb_tx_data(txdata_wdata),
        .dwc_tx_valid(dwc_tx_valid),
        .dwc_tx_ready(dwc_tx_ready),
        .dwc_tx_data(dwc_tx_data),
        .level(tx_level_w),
        .full(tx_full),
        .empty(tx_empty),
        .underflow(tx_underflow)
    );

    logic [7:0] irq_set;
    assign irq_set = {6'b0, tx_underflow, rx_overflow};

    audio_hub_apb_regs #(
        .ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)
    ) u_apb_regs (
        .pclk(pclk),
        .presetn(presetn),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .rxdata_rdata(rxdata_rdata),
        .rxdata_pop(apb_rx_pop),
        .txdata_wdata(txdata_wdata),
        .txdata_push(apb_tx_push),
        .rx_level(rx_level_w[7:0]),
        .tx_level(tx_level_w[7:0]),
        .rx_full(rx_full),
        .rx_empty(rx_empty),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .irq_set(irq_set),
        .hub_en(hub_en),
        .rx_en(rx_en),
        .tx_en(tx_en),
        .soft_rst_pulse(soft_rst_pulse),
        .rx_wm(rx_wm),
        .tx_wm(tx_wm),
        .rx_gain_q(rx_gain_q),
        .tx_gain0_q(tx_gain0_q),
        .tx_gain1_q(tx_gain1_q),
        .mix_en(mix_en),
        .irq_en(irq_en)
    );

    assign dma_rx_req = hub_en && rx_en && (rx_level_w[7:0] >= rx_wm) && !rx_empty;
    assign dma_tx_req = hub_en && tx_en && (tx_level_w[7:0] <= tx_wm) && !tx_full;
    assign irq = |(irq_set & irq_en);

endmodule
