`timescale 1ns/1ps

module tb_dwc_i2s_audio_hub_smoke;

    localparam int DATA_W = 32;

    logic pclk;
    logic presetn;

    logic psel, penable, pwrite;
    logic [11:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic pready, pslverr;

    logic dwc_rx_valid, dwc_rx_ready;
    logic [DATA_W-1:0] dwc_rx_data;

    logic dwc_tx_valid, dwc_tx_ready;
    logic [DATA_W-1:0] dwc_tx_data;

    logic dma_rx_req, dma_tx_req, irq;

    dwc_i2s_audio_hub_top u_dut (
        .pclk, .presetn,
        .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
        .dwc_rx_valid, .dwc_rx_ready, .dwc_rx_data,
        .dwc_tx_valid, .dwc_tx_ready, .dwc_tx_data,
        .dma_rx_req, .dma_tx_req, .irq
    );

    initial pclk = 1'b0;
    always #5 pclk = ~pclk;

    task apb_write(input [11:0] addr, input [31:0] data);
        @(posedge pclk);
        psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b1; paddr <= addr; pwdata <= data;
        @(posedge pclk);
        penable <= 1'b1;
        @(posedge pclk);
        psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0;
    endtask

    task apb_read(input [11:0] addr);
        @(posedge pclk);
        psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b0; paddr <= addr;
        @(posedge pclk);
        penable <= 1'b1;
        @(posedge pclk);
        psel <= 1'b0; penable <= 1'b0;
    endtask

    initial begin
        presetn = 1'b0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        dwc_rx_valid = 0; dwc_rx_data = 0;
        dwc_tx_ready = 1;

        repeat (5) @(posedge pclk);
        presetn = 1'b1;

        apb_write(12'h00C, 32'h0004_0004); // TX/RX wm = 4
        apb_write(12'h010, 32'h0000_4000); // rx gain
        apb_write(12'h014, 32'h0000_4000); // tx gain0
        apb_write(12'h000, 32'h0000_0007); // hub/rx/tx enable

        repeat (8) begin
            @(posedge pclk);
            dwc_rx_valid <= 1'b1;
            dwc_rx_data  <= 32'h0000_1000;
        end
        @(posedge pclk);
        dwc_rx_valid <= 1'b0;

        repeat (4) apb_read(12'h030);

        repeat (4) apb_write(12'h034, 32'h0000_0800);

        repeat (20) @(posedge pclk);
        $finish;
    end

endmodule
