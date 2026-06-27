module gradient_datapath (
    input wire clk,
    input wire reset,
    
    // Sinais de Controle (Handshaking)
    input  wire window_valid_in, // Alto quando p0-p8 têm dados reais da imagem
    output reg  pixel_valid_out, // Alto quando magnitude e direction estão prontos

    // Entrada: Janela 3x3 de píxeis de 8 bits
    input wire [7:0] p0, p1, p2,
    input wire [7:0] p3, p4, p5,
    input wire [7:0] p6, p7, p8,
    
    // Saídas sincronizadas
    // A magnitude foi expandida para 12 bits para acomodar a soma sem overflow
    output wire [11:0] magnitude,
    output wire [1:0]  direction
);

    // Registrador interno para acompanhar o Estágio 1 (Filtro de Sobel)
    reg valid_stage_1;

    always @(posedge clk) begin
        if (reset) begin
            valid_stage_1   <= 1'b0;
            pixel_valid_out <= 1'b0;
        end else begin
            // O sinal "valid" caminha junto com os dados no pipeline PIPO
            valid_stage_1   <= window_valid_in; 
            pixel_valid_out <= valid_stage_1;
        end
    end
    
    // =========================================================================
    // 1. SINAIS INTERNOS (WIRES)
    // =========================================================================
    
    // Saídas do Filtro de Sobel (11 bits com sinal)
    wire signed [10:0] fx;
    wire signed [10:0] fy;
    
    // Valores absolutos de fx e fy (11 bits sem sinal)
    wire [10:0] abs_fx;
    wire [10:0] abs_fy;
    
    // Extensão de bit para casar com a entrada de 12 bits do somador e da árvore
    wire [11:0] abs_fx_ext;
    wire [11:0] abs_fy_ext;
    
    assign abs_fx_ext = {1'b0, abs_fx};
    assign abs_fy_ext = {1'b0, abs_fy};

    // Sinais para o cálculo da projeção diagonal (12 bits)
    wire [11:0] sum_abs;
    wire [11:0] diag_proj;

    // =========================================================================
    // 2. ESTÁGIO 1: FILTRO DE SOBEL (SEQUENCIAL / PIPO)
    // =========================================================================

    sobel_filter inst_sobel (
        .clk(clk),
        .reset(reset),
        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),
        .fx(fx),
        .fy(fy)
    );

    // =========================================================================
    // 3. ESTÁGIO 2: LÓGICA COMBINACIONAL (MÓDULOS E APROXIMAÇÃO)
    // =========================================================================

    // Extração dos valores absolutos
    abs_value #(.WIDTH(11)) inst_abs_fx (
        .num_in(fx),
        .abs_num_out(abs_fx)
    );

    abs_value #(.WIDTH(11)) inst_abs_fy (
        .num_in(fy),
        .abs_num_out(abs_fy)
    );
    
    // Soma dos eixos ortogonais (|fx| + |fy|)
    assign sum_abs = abs_fx_ext + abs_fy_ext;

    // Aproximação da multiplicação por 1/sqrt(2) (Rede combinacional Shift-Add)
    mag_approx #(.WIDTH(12)) inst_mag_approx (
        .sum_in(sum_abs),
        .mag_out(diag_proj)
    );

    // =========================================================================
    // 4. ESTÁGIO FINAL: ÁRVORE DE DECISÃO (SEQUENCIAL / PIPO)
    // =========================================================================

    // Compara os eixos ortogonais com a diagonal e codifica a direção
    gradient_decision_tree #(.WIDTH(12)) inst_decision_tree (
        .clk(clk),
        .reset(reset),
        .abs_fx(abs_fx_ext),
        .abs_fy(abs_fy_ext),
        .diag_proj(diag_proj),
        .sign_fx(fx[10]), // Passa o MSB (bit de sinal original do gradiente X)
        .sign_fy(fy[10]), // Passa o MSB (bit de sinal original do gradiente Y)
        .magnitude(magnitude),
        .direction(direction)
    );

endmodule