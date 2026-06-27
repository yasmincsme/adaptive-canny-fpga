module sobel_filter (
    input wire clk,
    input wire reset,
    
    // Entrada PIPO: Janela 3x3 de pixels (8 bits) disponíveis simultaneamente
    input wire [7:0] p0, p1, p2,
    input wire [7:0] p3, p4, p5,
    input wire [7:0] p6, p7, p8,
    
    // Saída PIPO: Gradientes X e Y (11 bits com sinal para evitar overflow)
    output reg signed [10:0] fx,
    output reg signed [10:0] fy
);

    // Sinais combinacionais intermediários (assinados e expandidos para 11 bits)
    wire signed [10:0] fx_comb;
    wire signed [10:0] fy_comb;

    // -------------------------------------------------------------------------
    // CÁLCULO DO GRADIENTE HORIZONTAL (fx)
    // fx = (p2 - p0) + 2*(p5 - p3) + (p8 - p6)
    // A multiplicação por 2 é feita apenas concatenando um '0' no final (<<1)
    // -------------------------------------------------------------------------
    assign fx_comb = $signed({3'b000, p2}) - $signed({3'b000, p0}) +
                     $signed({2'b00,  p5, 1'b0}) - $signed({2'b00,  p3, 1'b0}) +
                     $signed({3'b000, p8}) - $signed({3'b000, p6});

    // -------------------------------------------------------------------------
    // CÁLCULO DO GRADIENTE VERTICAL (fy)
    // fy = (p6 - p0) + 2*(p7 - p1) + (p8 - p2)
    // -------------------------------------------------------------------------
    assign fy_comb = $signed({3'b000, p6}) - $signed({3'b000, p0}) +
                     $signed({2'b00,  p7, 1'b0}) - $signed({2'b00,  p1, 1'b0}) +
                     $signed({3'b000, p8}) - $signed({3'b000, p2});

    // Registradores PIPO de Saída
    always @(posedge clk) begin
        if (reset) begin
            fx <= 11'sd0;
            fy <= 11'sd0;
        end else begin
            fx <= fx_comb;
            fy <= fy_comb;
        end
    end

endmodule