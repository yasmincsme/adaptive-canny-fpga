module gradient_decision_tree #(
    parameter WIDTH = 11 // Largura dos gradientes acumulados (ex: 11 bits)
)(
    input wire clk,
    input wire reset,
    
    // Entradas absolutas e projeção diagonal
    input wire [WIDTH-1:0] abs_fx,    // |Mx|
    input wire [WIDTH-1:0] abs_fy,    // |My|
    input wire [WIDTH-1:0] diag_proj, // 0.7071 * (|Mx| + |My|)
    
    // Bits de sinal originais do filtro de Sobel (MSBs)
    input wire sign_fx,               // fx[WIDTH-1]
    input wire sign_fy,               // fy[WIDTH-1]
    
    // Saídas PIPO sincronizadas
    output reg [WIDTH-1:0] magnitude, // Magnitude final aproximada
    output reg [1:0] direction        // Ângulo codificado
);

    // Codificação das direções para o Canny:
    // 2'b00 -> 0 graus
    // 2'b01 -> 45 graus
    // 2'b10 -> 90 graus
    // 2'b11 -> 135 graus

    // Sinais combinacionais intermediários
    wire [WIDTH-1:0] max_ortho;
    wire [1:0] dir_ortho;
    
    wire [WIDTH-1:0] magnitude_comb;
    reg  [1:0] direction_comb;
    wire sign_xor;

    // -------------------------------------------------------------------------
    // ESTÁGIO 1: Comparação entre os eixos ortogonais (|Mx| e |My|)
    // -------------------------------------------------------------------------
    assign max_ortho = (abs_fx >= abs_fy) ? abs_fx : abs_fy;
    assign dir_ortho = (abs_fx >= abs_fy) ? 2'b00  : 2'b10;

    // -------------------------------------------------------------------------
    // ESTÁGIO 2: Comparação com a Projeção Diagonal (Encontra o Máximo Global)
    // -------------------------------------------------------------------------
    assign magnitude_comb = (max_ortho >= diag_proj) ? max_ortho : diag_proj;

    // -------------------------------------------------------------------------
    // ESTÁGIO 3: Lógica XOR para direções diagonais (45 vs 135 graus)
    // -------------------------------------------------------------------------
    assign sign_xor = sign_fx ^ sign_fy;

    always @(*) begin
        if (max_ortho >= diag_proj) begin
            // Vencedor foi um dos eixos ortogonais (0 ou 90 graus)
            direction_comb = dir_ortho;
        end else begin
            // Vencedor foi a diagonal. Sinais iguais = 45o, Sinais diferentes = 135o
            direction_comb = sign_xor ? 2'b11 : 2'b01;
        end
    end

    // -------------------------------------------------------------------------
    // REGISTRADOR PIPO: Captura paralela e síncrona dos resultados
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            magnitude <= {WIDTH{1'b0}};
            direction <= 2'b00;
        end else begin
            magnitude <= magnitude_comb;
            direction <= direction_comb;
        end
    end

endmodule