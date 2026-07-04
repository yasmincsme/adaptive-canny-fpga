//`timescale 1ns / 1ps

module double_threshold #(
    parameter WIDTH = 12
)(
    // Entrada vinda do módulo NMS
    input  wire [WIDTH-1:0] nms_mag_in,
    input  wire             nms_vld_in,
    // valores para o threshold
    input wire [WIDTH-1:0] HIGH_THRESH,
    input wire [WIDTH-1:0] LOW_THRESH,
    
    // Saída comprimida (2 bits) para o Buffer de Histerese
    output wire [1:0]       edge_type_out,
    output wire             vld_out
);

    // =========================================================================
    // LÓGICA DE DUPLO LIMIAR (CLASSIFICAÇÃO)
    // =========================================================================
    // Utilizamos o operador ternário aninhado para criar os comparadores.
    // O hardware gerado serão dois blocos comparadores em paralelo.
    
    assign edge_type_out = (nms_mag_in >= HIGH_THRESH) ? 2'b11 : // Borda Forte
                           (nms_mag_in >= LOW_THRESH)  ? 2'b01 : // Borda Fraca
                                                         2'b00;  // Fundo (Ruído)

    // =========================================================================
    // PROPAGAÇÃO DO SINAL DE HANDSHAKE
    // =========================================================================
    
    // A validação apenas atravessa o módulo instantaneamente
    assign vld_out = nms_vld_in;

endmodule