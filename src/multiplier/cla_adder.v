
// Somador CLA de 16 bits
module cla_adder (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [15:0] sum
);
    wire [3:0] p, g, c;
    
    // Unidade de Lookahead Carry (LCU) simplificada para 16 bits
    assign c[0] = 1'b0;
    assign c[1] = g[0] | (p[0] & c[0]);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c[0]);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & c[0]);

    cla_4bit cla0 (.a(a[3:0]),   .b(b[3:0]),   .cin(c[0]), .sum(sum[3:0]),   .p_out(p[0]), .g_out(g[0]));
    cla_4bit cla1 (.a(a[7:4]),   .b(b[7:4]),   .cin(c[1]), .sum(sum[7:4]),   .p_out(p[1]), .g_out(g[1]));
    cla_4bit cla2 (.a(a[11:8]),  .b(b[11:8]),  .cin(c[2]), .sum(sum[11:8]),  .p_out(p[2]), .g_out(g[2]));
    cla_4bit cla3 (.a(a[15:12]), .b(b[15:12]), .cin(c[3]), .sum(sum[15:12]), .p_out(p[3]), .g_out(g[3]));
endmodule