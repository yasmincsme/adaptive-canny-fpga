// Bloco CLA Genuíno de 4 bits (Sem Ripple Carry)
module cla_4bit (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire cin,
    output wire [3:0] sum,
    output wire p_out, 
    output wire g_out
);
    wire [3:0] p, g;
    wire [4:0] c;

    assign p = a ^ b;
    assign g = a & b;

    // Equações expandidas de Lookahead (Atraso constante)
    assign c[0] = cin;
    assign c[1] = g[0] | (p[0] & c[0]);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c[0]);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & c[0]);
    assign c[4] = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);

    assign sum = p ^ c[3:0];

    // Sinais para a Unidade de Lookahead Superior (LCU)
    assign p_out = &p; 
    assign g_out = c[4];
endmodule