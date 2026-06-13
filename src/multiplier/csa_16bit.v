`timescale 1ns / 1ps

module csa_16bit (
    input  [15:0] X,
    input  [15:0] Y,
    input  [15:0] Z,
    output [15:0] Sum,
    output [15:0] Carry
);

    // Fio interno para capturar a geração do carry antes do alinhamento
    wire [15:0] c_int;

    // 1. Geração da Soma: Operação XOR estritamente bit a bit
    assign Sum = X ^ Y ^ Z;

    // 2. Geração do Carry: Lógica Majoritária
    // Se pelo menos 2 das 3 entradas num determinado bit forem '1', gera-se um carry.
    assign c_int = (X & Y) | (X & Z) | (Y & Z);

    // 3. O Segredo do CSA: O Deslocamento Espacial
    // O carry gerado na coluna 'i' deve ser somado na coluna 'i+1'.
    // Portanto, deslocamos todo o vetor de carry 1 bit para a esquerda.
    // O bit 0 do Carry recebe sempre '0'.
    // O carry out absoluto (c_int[15]) é descartado com segurança, pois a matemática 
    // da nossa janela Gaussiana garante que o valor máximo estourando não ultrapassa os 16 bits.
    assign Carry = {c_int[14:0], 1'b0};

endmodule