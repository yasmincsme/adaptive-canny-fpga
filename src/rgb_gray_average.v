/*
|   rgb_gray_average.v
|   Implementação direta da conversão de imagens
|   RGB para escala de cinza utilizando o método
|   da média
|
|   Autor: AlissonRCSantos
|   Data: Junho 2026
*/

module rgb_gray_average(
    input clk,
    input [7:0] R,G,B,  // Três canais de 8 bits para um pixel
    output [7:0] gray_avg
);

    wire [9:0]  avr_sum_w;    // A soma precisa de 2 bits a mais devido os três operandos
    reg  [15:0] avr_div;      // resultado da divisão

    // soma dos três canais
    assign avr_sum_w = R+G+B;
    // pixel em escala de cinza
    assign gray_avg = avr_div;

    always @(clk) begin
        // divisão custosa em hardware
        avr_div <= avr_sum_w / 3; 
    end

endmodule
