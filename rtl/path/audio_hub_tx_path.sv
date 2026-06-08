module audio_hub_tx_path #(
    parameter int DATA_W = 32,
    parameter int SAMPLE_W = 24,
    parameter int FIFO_DEPTH = 32,
    parameter int FIFO_AW = $clog2(FIFO_DEPTH)
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              flush,
    input  logic              enable,

    input  logic signed [15:0] gain0_q,
    input  logic signed [15:0] gain1_q,
    input  logic              mix_en,

    input  logic              apb_tx_push,
    input  logic [DATA_W-1:0] apb_tx_data,

    output logic              dwc_tx_valid,
    input  logic              dwc_tx_ready,
    output logic [DATA_W-1:0] dwc_tx_data,

    output logic [FIFO_AW:0]  level,
    output logic              full,
    output logic              empty,
    output logic              underflow
);

    logic [DATA_W-1:0] fifo_rdata;
    logic [DATA_W-1:0] gain0_data;
    logic [DATA_W-1:0] gain1_data;
    logic [DATA_W-1:0] mix_data;
    logic almost_full;

    wire fifo_push = enable && apb_tx_push && !full;
    wire fifo_pop  = enable && dwc_tx_valid && dwc_tx_ready;

    audio_sync_fifo #(.DATA_W(DATA_W), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .push(fifo_push),
        .push_data(apb_tx_data),
        .full(full),
        .almost_full(almost_full),
        .pop(fifo_pop),
        .pop_data(fifo_rdata),
        .empty(empty),
        .level(level)
    );

    audio_gain #(.DATA_W(DATA_W), .SAMPLE_W(SAMPLE_W)) u_tx_gain0 (
        .enable(enable),
        .gain_q(gain0_q),
        .sample_word_i(fifo_rdata),
        .sample_word_o(gain0_data)
    );

    // Placeholder aux input: currently same stream. Replace with second DMA/FIFO when adding true mixer input.
    audio_gain #(.DATA_W(DATA_W), .SAMPLE_W(SAMPLE_W)) u_tx_gain1 (
        .enable(enable && mix_en),
        .gain_q(gain1_q),
        .sample_word_i(fifo_rdata),
        .sample_word_o(gain1_data)
    );

    audio_mixer2 #(.DATA_W(DATA_W), .SAMPLE_W(SAMPLE_W)) u_mixer2 (
        .enable(mix_en),
        .in0(gain0_data),
        .in1(gain1_data),
        .out(mix_data)
    );

    assign dwc_tx_valid = enable && !empty;
    assign dwc_tx_data  = mix_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) underflow <= 1'b0;
        else if (flush) underflow <= 1'b0;
        else if (enable && dwc_tx_ready && empty) underflow <= 1'b1;
    end

endmodule
