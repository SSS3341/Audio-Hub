`include "audio_hub_defs.svh"

module audio_hub_apb_regs #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32
)(
    input  logic              pclk,
    input  logic              presetn,

    input  logic              psel,
    input  logic              penable,
    input  logic              pwrite,
    input  logic [ADDR_W-1:0] paddr,
    input  logic [DATA_W-1:0] pwdata,
    output logic [DATA_W-1:0] prdata,
    output logic              pready,
    output logic              pslverr,

    input  logic [DATA_W-1:0] rxdata_rdata,
    output logic              rxdata_pop,

    output logic [DATA_W-1:0] txdata_wdata,
    output logic              txdata_push,

    input  logic [7:0]        rx_level,
    input  logic [7:0]        tx_level,
    input  logic              rx_full,
    input  logic              rx_empty,
    input  logic              tx_full,
    input  logic              tx_empty,
    input  logic [7:0]        irq_set,

    output logic              hub_en,
    output logic              rx_en,
    output logic              tx_en,
    output logic              soft_rst_pulse,
    output logic [7:0]        rx_wm,
    output logic [7:0]        tx_wm,
    output logic signed [15:0] rx_gain_q,
    output logic signed [15:0] tx_gain0_q,
    output logic signed [15:0] tx_gain1_q,
    output logic              mix_en,
    output logic [7:0]        irq_en
);

    logic [7:0] irq_status;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    wire apb_access = psel & penable;
    wire apb_wr     = apb_access & pwrite;
    wire apb_rd     = apb_access & ~pwrite;

    assign rxdata_pop  = apb_rd && (paddr == `AUDIO_HUB_RXDATA);
    assign txdata_push = apb_wr && (paddr == `AUDIO_HUB_TXDATA);
    assign txdata_wdata = pwdata;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            hub_en     <= 1'b0;
            rx_en      <= 1'b0;
            tx_en      <= 1'b0;
            rx_wm      <= 8'd8;
            tx_wm      <= 8'd8;
            rx_gain_q  <= 16'sh4000; // Q1.15 0.5 if using signed 16-bit; adjust in integration if unsigned 1.0 is needed.
            tx_gain0_q <= 16'sh4000;
            tx_gain1_q <= 16'sh4000;
            mix_en     <= 1'b0;
            irq_en     <= 8'h00;
            irq_status <= 8'h00;
            soft_rst_pulse <= 1'b0;
        end else begin
            soft_rst_pulse <= 1'b0;
            irq_status <= irq_status | irq_set;

            if (apb_wr) begin
                unique case (paddr)
                    `AUDIO_HUB_CTRL: begin
                        hub_en <= pwdata[0];
                        rx_en  <= pwdata[1];
                        tx_en  <= pwdata[2];
                        soft_rst_pulse <= pwdata[4];
                    end
                    `AUDIO_HUB_DMA_CFG: begin
                        rx_wm <= pwdata[7:0];
                        tx_wm <= pwdata[15:8];
                    end
                    `AUDIO_HUB_RX_GAIN:  rx_gain_q  <= pwdata[15:0];
                    `AUDIO_HUB_TX_GAIN0: tx_gain0_q <= pwdata[15:0];
                    `AUDIO_HUB_TX_GAIN1: tx_gain1_q <= pwdata[15:0];
                    `AUDIO_HUB_MIX_CFG:  mix_en <= pwdata[0];
                    `AUDIO_HUB_IRQ_STAT: irq_status <= irq_status & ~pwdata[7:0];
                    `AUDIO_HUB_IRQ_EN:   irq_en <= pwdata[7:0];
                    default: begin end
                endcase
            end
        end
    end

    always_comb begin
        unique case (paddr)
            `AUDIO_HUB_CTRL:     prdata = {{(DATA_W-5){1'b0}}, 1'b0, tx_en, rx_en, hub_en};
            `AUDIO_HUB_DMA_CFG:  prdata = {{(DATA_W-16){1'b0}}, tx_wm, rx_wm};
            `AUDIO_HUB_RX_GAIN:  prdata = {{16{rx_gain_q[15]}}, rx_gain_q};
            `AUDIO_HUB_TX_GAIN0: prdata = {{16{tx_gain0_q[15]}}, tx_gain0_q};
            `AUDIO_HUB_TX_GAIN1: prdata = {{16{tx_gain1_q[15]}}, tx_gain1_q};
            `AUDIO_HUB_MIX_CFG:  prdata = {{(DATA_W-1){1'b0}}, mix_en};
            `AUDIO_HUB_STATUS:   prdata = {8'h0, tx_level, rx_level, 4'h0, tx_full, tx_empty, rx_full, rx_empty};
            `AUDIO_HUB_IRQ_STAT: prdata = {{(DATA_W-8){1'b0}}, irq_status};
            `AUDIO_HUB_IRQ_EN:   prdata = {{(DATA_W-8){1'b0}}, irq_en};
            `AUDIO_HUB_RXDATA:   prdata = rxdata_rdata;
            default:             prdata = '0;
        endcase
    end

endmodule
