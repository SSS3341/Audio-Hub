module audio_gain #(
    parameter int DATA_W      = 32,
    parameter int SAMPLE_W    = 24,
    parameter int GAIN_W      = 16,
    parameter int GAIN_FRAC_W = 15
)(
    input  logic                         enable,
    input  logic signed [GAIN_W-1:0]      gain_q,
    input  logic [DATA_W-1:0]             sample_word_i,
    output logic [DATA_W-1:0]             sample_word_o
);

    logic signed [SAMPLE_W-1:0] sample_i;
    logic signed [SAMPLE_W+GAIN_W-1:0] mult;
    logic signed [SAMPLE_W+GAIN_W-1:0] scaled;
    logic signed [SAMPLE_W-1:0] sample_o;

    localparam logic signed [SAMPLE_W-1:0] SAMPLE_MAX = {1'b0, {(SAMPLE_W-1){1'b1}}};
    localparam logic signed [SAMPLE_W-1:0] SAMPLE_MIN = {1'b1, {(SAMPLE_W-1){1'b0}}};

    logic signed [SAMPLE_W+GAIN_W-1:0] max_ext;
    logic signed [SAMPLE_W+GAIN_W-1:0] min_ext;

    assign sample_i = sample_word_i[SAMPLE_W-1:0];
    assign mult     = sample_i * gain_q;
    assign scaled   = mult >>> GAIN_FRAC_W;
    assign max_ext  = {{GAIN_W{SAMPLE_MAX[SAMPLE_W-1]}}, SAMPLE_MAX};
    assign min_ext  = {{GAIN_W{SAMPLE_MIN[SAMPLE_W-1]}}, SAMPLE_MIN};

    always_comb begin
        if (!enable) begin
            sample_o = sample_i;
        end else if (scaled > max_ext) begin
            sample_o = SAMPLE_MAX;
        end else if (scaled < min_ext) begin
            sample_o = SAMPLE_MIN;
        end else begin
            sample_o = scaled[SAMPLE_W-1:0];
        end

        sample_word_o = {sample_word_i[DATA_W-1:SAMPLE_W], sample_o};
    end

endmodule
