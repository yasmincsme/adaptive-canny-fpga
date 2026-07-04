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
    input [7:0] R,G,B,  // Três canais de 8 bits para um pixel
    output [7:0] gray_avg
);

    // Combinacional: nao ha estado a manter, e um estagio registrado aqui
    // exigiria atrasar em 1 ciclo o pixel_vld que alimenta a janela 7x7
    // subsequente (mesma classe de bug de desalinhamento ja corrigida entre
    // o Gauss e o Sobel no canny_top_module).
    wire [9:0] avr_sum_w;    // A soma precisa de 2 bits a mais devido os três operandos

    // soma dos três canais
    assign avr_sum_w = R+G+B;
    // pixel em escala de cinza (divisão custosa em hardware)
    assign gray_avg = avr_sum_w / 3;

endmodule
