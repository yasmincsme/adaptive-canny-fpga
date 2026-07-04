//`timescale 1ns / 1ps

module hysteresis_logic (
    // Entrada: Janela 3x3 com 2 bits por píxel (Vinda do buffer de histerese)
    // 2'b11 = Forte, 2'b01 = Fraca, 2'b00 = Fundo
    input  wire [1:0] win00, input  wire [1:0] win01, input  wire [1:0] win02,
    input  wire [1:0] win10, input  wire [1:0] win11, input  wire [1:0] win12,
    input  wire [1:0] win20, input  wire [1:0] win21, input  wire [1:0] win22,
    
    // Sinal de validação da janela
    input  wire       win_vld_in,
    
    // Saída: Píxel final da imagem (8 bits: 0 ou 255)
    output wire [7:0] edge_pixel_out,
    output wire       pixel_vld_out
);

    // =========================================================================
    // 1. DETETOR DE VIZINHANÇA FORTE
    // =========================================================================
    // Verifica se há pelo menos um vizinho Forte (2'b11) ao redor do centro.
    // Tudo isto é resolvido instantaneamente com portas lógicas OR paralelas.
    
    wire has_strong_neighbor;
    
    assign has_strong_neighbor = (win00 == 2'b11) | (win01 == 2'b11) | (win02 == 2'b11) |
                                 (win10 == 2'b11) |                    (win12 == 2'b11) |
                                 (win20 == 2'b11) | (win21 == 2'b11) | (win22 == 2'b11);

    // =========================================================================
    // 2. LÓGICA DE DECISÃO FINAL (MÁSCARA DE SAÍDA)
    // =========================================================================
    // - Se for Forte, sobrevive sempre (255)
    // - Se for Fraca E estiver conetada a um Forte, é promovida (255)
    // - Resto, morre (0)
    
    assign edge_pixel_out = (win11 == 2'b11) ? 8'hFF :                               // É forte!
                            ((win11 == 2'b01) && has_strong_neighbor) ? 8'hFF :      // É fraca, mas conectada!
                            8'h00;                                                   // É ruído ou fundo!

    // =========================================================================
    // 3. PROPAGAÇÃO DO SINAL DE CONTROLE
    // =========================================================================
    // O sinal flui sem atraso de clock
    assign pixel_vld_out = win_vld_in;

endmodule