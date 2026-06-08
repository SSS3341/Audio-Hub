module audio_sync_fifo #(
    parameter int DATA_W = 32,
    parameter int DEPTH  = 32,
    parameter int AW     = $clog2(DEPTH)
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              flush,

    input  logic              push,
    input  logic [DATA_W-1:0] push_data,
    output logic              full,
    output logic              almost_full,

    input  logic              pop,
    output logic [DATA_W-1:0] pop_data,
    output logic              empty,
    output logic [AW:0]       level
);

    logic [DATA_W-1:0] mem [0:DEPTH-1];
    logic [AW-1:0] wr_ptr;
    logic [AW-1:0] rd_ptr;

    assign full        = (level == DEPTH[AW:0]);
    assign empty       = (level == '0);
    assign almost_full = (level >= (DEPTH-2));

    assign pop_data = mem[rd_ptr];

    wire do_push = push & ~full;
    wire do_pop  = pop  & ~empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            level  <= '0;
        end else if (flush) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            level  <= '0;
        end else begin
            unique case ({do_push, do_pop})
                2'b10: begin
                    mem[wr_ptr] <= push_data;
                    wr_ptr <= wr_ptr + 1'b1;
                    level  <= level + 1'b1;
                end
                2'b01: begin
                    rd_ptr <= rd_ptr + 1'b1;
                    level  <= level - 1'b1;
                end
                2'b11: begin
                    mem[wr_ptr] <= push_data;
                    wr_ptr <= wr_ptr + 1'b1;
                    rd_ptr <= rd_ptr + 1'b1;
                end
                default: begin
                end
            endcase
        end
    end

endmodule
