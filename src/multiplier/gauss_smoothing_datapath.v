`timescale 1ns / 1ps

module gauss_smoothing_datapath (
    input  wire         clk,
    input  wire         rst_n,
    
    // Sinais de Controlo Global
    input  wire         start,
    //input  wire [1:0]   kernel_sel,   // 00 = 3x3, 01 = 5x5, 10 = 7x7
    output wire         done,
    
    // Interface de Dados
    input  wire [391:0] window_flat,  // Os 49 píxeis achatados do Line Buffer
    input  wire [7:0]   peso_atual,   // Coeficiente vindo da ROM externa
    
    output wire [5:0]   contador_out, // Endereço para a ROM de pesos externa
    output reg  [7:0]   pixel_suavizado // Registrador final de saída (gaussian_reg)
);

    localparam max_pixels = 6'd49;
    // ========================================================================
    // 1. SINAIS INTERNOS E FIOS DE INTERLIGAÇÃO
    // ========================================================================
    wire        clr_acc;
    wire        mac_en;
    wire        write_en;
    wire        limit_reached;
    
    reg  [5:0]  contador;
    reg  [5:0]  max_pixels;
    
    wire [15:0] novo_produto;
    wire [15:0] proximo_sum, proximo_carry;
    reg  [15:0] reg_sum, reg_carry;
    wire [15:0] resultado_final_16b;
    wire [7:0]  pixel_arredondado;

    assign contador_out = contador;

    // ========================================================================
    // 2. DECODIFICADOR DO TAMANHO DA JANELA (Window Size Decoder)
    // ========================================================================
    /*
    always @(*) begin
        case (kernel_sel)
            2'b00: max_pixels = 6'd9;   // 3x3
            2'b01: max_pixels = 6'd25;  // 5x5
            2'b10: max_pixels = 6'd49;  // 7x7
            default: max_pixels = 6'd9; // Segurança
        endcase
    end
    */

    // ========================================================================
    // 3. CONTADOR E COMPARADOR
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            contador <= 6'd0;
        end else if (clr_acc) begin
            contador <= 6'd0;
        end else if (mac_en) begin
            contador <= contador + 1'b1;
        end
    end

    // O sinal é ativado no último ciclo útil da acumulação
    assign limit_reached = (contador == (max_pixels - 1));

    // ========================================================================
    // 4. MÁQUINA DE ESTADOS (gauss_uc)
    // ========================================================================
    gauss_uc fsm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .limit_reached(limit_reached),
        .clr_acc(clr_acc),
        .mac_en(mac_en),
        .write_en(write_en),
        .done(done)
    );

    // ========================================================================
    // 5. DESEMPACOTAMENTO DE PÍXEIS (Unflattening) E MULTIPLEXAÇÃO
    // ========================================================================
    wire [7:0] window_array [0:48];
    wire [7:0] pixel_atual;
    
    genvar i;
    generate
        for (i = 0; i < 49; i = i + 1) begin : unflatten
            assign window_array[i] = window_flat[(i*8) + 7 : (i*8)];
        end
    endgenerate

    // Multiplexador inferido pelo sintetizador para escolher o píxel correto
    assign pixel_atual = window_array[contador];

    // ========================================================================
    // 6. DATAPATH ARITMÉTICO (A Mágica da Área Mínima)
    // ========================================================================
    
    // Multiplicador Combinacional (Apenas 1 instância)
    wallace_8x8_unsigned mult_inst (
        .A(pixel_atual),
        .B(peso_atual),
        .Prod(novo_produto)
    );

    // Acumulador Carry-Save (Módulo Combinacional)
    csa_16bit csa_inst (
        .X(novo_produto),
        .Y(reg_sum),
        .Z(reg_carry),
        .Sum(proximo_sum),
        .Carry(proximo_carry)
    );

    // Atualização Síncrona dos Registradores do Acumulador (csa_acc)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_sum   <= 16'd0;
            reg_carry <= 16'd0;
        end else if (clr_acc) begin
            reg_sum   <= 16'd0;
            reg_carry <= 16'd0;
        end else if (mac_en) begin
            reg_sum   <= proximo_sum;
            reg_carry <= proximo_carry;
        end
    end

    // ========================================================================
    // 7. SOMA FINAL E REGISTRADOR DE SAÍDA (gaussian_reg)
    // ========================================================================
    
    cla_16bit final_adder (
        .a(reg_sum),
        .b(reg_carry),
        .sum(resultado_final_16b)
    );

    // Extração do MSB com arredondamento baseado no bit fracionário mais alto
    assign pixel_arredondado = resultado_final_16b[15:8] + resultado_final_16b[7];

    // Registrador de saída (gaussian_reg) que isola o módulo do resto do sistema
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_suavizado <= 8'd0;
        end else if (write_en) begin
            pixel_suavizado <= pixel_arredondado;
        end
    end

endmodule