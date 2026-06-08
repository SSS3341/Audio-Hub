module audio_hub_rx_path #(
    parameter int DATA_W = 32,
    parameter int SAMPLE_W = 24,
    parameter int FIFO_DEPTH = 32,
    parameter int FIFO_AW = $clog2(FIFO_DEPTH)
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              flush,
    input  logic              enable,

    input  logic signed [15:0] gain_q,

    input  logic              dwc_rx_valid,
    output logic              dwc_rx_ready,
    input  logic [DATA_W-1:0] dwc_rx_data,

    input  logic              apb_rx_pop,
    output logic [DATA_W-1:0] apb_rx_data,

    output logic [FIFO_AW:0]  level,
    output logic              full,
    output logic              empty,
    output logic              overflow
);

    logic [DATA_W-1:0] gain_data;
    logic fifo_push;
    logic almost_full;

    audio_gain #(.DATA_W(DATA_W), .SAMPLE_W(SAMPLE_W)) u_rx_gain (
        .enable(enable),
        .gain_q(gain_q),
        .sample_word_i(dwc_rx_data),
        .sample_word_o(gain_data)
    );

    assign dwc_rx_ready = enable && !almost_full;
    assign fifo_push = dwc_rx_valid && dwc_rx_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) overflow <= 1'b0;
        else if (flush) overflow <= 1'b0;
        else if (dwc_rx_valid && !dwc_rx_ready) overflow <= 1'b1;
    end

    audio_sync_fifo #(.DATA_W(DATA_W), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .push(fifo_push),
        .push_data(gain_data),
        .full(full),
        .almost_full(almost_full),
        .pop(apb_rx_pop),
        .pop_data(apb_rx_data),
        .empty(empty),
        .level(level)
    );

endmodule
