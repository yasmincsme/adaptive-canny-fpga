`timescale 1ns / 1ps

module mag_approx #(
    parameter WIDTH = 12 // Largura de dados ajustada para o datapath
)(
    input  wire [(WIDTH-1):0] sum_in,   // Entrada: |Mx| + |My|
    output wire [(WIDTH-1):0] diag_out  // Saída combinacional para o comparador
);

    // Árvore combinacional explícita de Shift-Add para * 0.7071
    assign diag_out = (sum_in >> 1) + 
                      (sum_in >> 3) + 
                      (sum_in >> 4) + 
                      (sum_in >> 6) + 
                      (sum_in >> 8);

endmodule