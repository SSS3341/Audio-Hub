module audio_mixer2 #(
    parameter int DATA_W   = 32,
    parameter int SAMPLE_W = 24
)(
    input  logic             enable,
    input  logic [DATA_W-1:0] in0,
    input  logic [DATA_W-1:0] in1,
    output logic [DATA_W-1:0] out
);

    logic signed [SAMPLE_W-1:0] s0;
    logic signed [SAMPLE_W-1:0] s1;
    logic signed [SAMPLE_W:0]   sum;
    logic signed [SAMPLE_W-1:0] sat;

    localparam logic signed [SAMPLE_W-1:0] SAMPLE_MAX = {1'b0, {(SAMPLE_W-1){1'b1}}};
    localparam logic signed [SAMPLE_W-1:0] SAMPLE_MIN = {1'b1, {(SAMPLE_W-1){1'b0}}};

    assign s0  = in0[SAMPLE_W-1:0];
    assign s1  = in1[SAMPLE_W-1:0];
    assign sum = {s0[SAMPLE_W-1], s0} + {s1[SAMPLE_W-1], s1};

    always_comb begin
        if (!enable) begin
            sat = s0;
        end else if (sum > {SAMPLE_MAX[SAMPLE_W-1], SAMPLE_MAX}) begin
            sat = SAMPLE_MAX;
        end else if (sum < {SAMPLE_MIN[SAMPLE_W-1], SAMPLE_MIN}) begin
            sat = SAMPLE_MIN;
        end else begin
            sat = sum[SAMPLE_W-1:0];
        end

        out = {in0[DATA_W-1:SAMPLE_W], sat};
    end

endmodule
