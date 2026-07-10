module rgb2gray (
    input  wire       clk,
    input  wire [7:0] R,
    input  wire [7:0] G,
    input  wire [7:0] B,
    output reg  [7:0] gray
);

    wire [15:0] gray_sum;

    assign gray_sum =
        ((R << 6) + (R << 3) + (R << 2) + R) +
        ((G << 7) + (G << 4) + (G << 2) + (G << 1)) +
        ((B << 4) + (B << 3) + (B << 2) + B);

    always @(posedge clk)
        gray <= gray_sum[15:8];

endmodule