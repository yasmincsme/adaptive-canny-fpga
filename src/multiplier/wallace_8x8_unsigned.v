module wallace_8x8_unsigned (
    input  [7:0] A,
    input  [7:0] B,
    output [15:0] Prod
);
    // Fase 1: Geração dos Produtos Parciais (Matriz 8x8)
    wire [7:0] p [0:7];
    genvar r, c;
    generate
        for (r = 0; r < 8; r = r + 1) begin : gen_row
            for (c = 0; c < 8; c = c + 1) begin : gen_col
                assign p[r][c] = A[c] & B[r];
            end
        end
    endgenerate

    // ========================================================================
    // REDUÇÃO - ESTÁGIO 1 (Alvo: Máximo 6 bits por coluna)
    // Apenas as colunas centrais 6, 7 e 8 excedem 6 bits na matriz original.
    // ========================================================================
    wire s1_c6_0, c1_c7_0;
    wire s1_c7_0, s1_c7_1, c1_c8_0, c1_c8_1;
    wire s1_c8_0, s1_c8_1, c1_c9_0, c1_c9_1;
    wire s1_c9_0, c1_c10_0;

    half_adder ha1_c6 (p[5][1], p[6][0], s1_c6_0, c1_c7_0);
    
    full_adder fa1_c7_0 (p[5][2], p[6][1], p[7][0], s1_c7_0, c1_c8_0);
    full_adder fa1_c7_1 (p[3][4], p[4][3], c1_c7_0, s1_c7_1, c1_c8_1);
    
    full_adder fa1_c8_0 (p[5][3], p[6][2], p[7][1], s1_c8_0, c1_c9_0);
    full_adder fa1_c8_1 (p[3][5], p[4][4], c1_c8_0, s1_c8_1, c1_c9_1);
    
    full_adder fa1_c9_0 (p[5][4], p[6][3], p[7][2], s1_c9_0, c1_c10_0);

    // ========================================================================
    // REDUÇÃO - ESTÁGIO 2 (Alvo: Máximo 4 bits por coluna)
    // ========================================================================
    wire s2_c4_0, c2_c5_0;
    wire s2_c5_0, s2_c5_1, c2_c6_0, c2_c6_1;
    wire s2_c6_0, s2_c6_1, c2_c7_0, c2_c7_1;
    wire s2_c7_0, s2_c7_1, c2_c8_0, c2_c8_1;
    wire s2_c8_0, s2_c8_1, c2_c9_0, c2_c9_1;
    wire s2_c9_0, s2_c9_1, c2_c10_0, c2_c10_1;
    wire s2_c10_0, s2_c10_1, c2_c11_0, c2_c11_1;
    wire s2_c11_0, c2_c12_0;

    half_adder ha2_c4 (p[3][1], p[4][0], s2_c4_0, c2_c5_0);
    
    half_adder ha2_c5 (p[4][1], p[5][0], s2_c5_0, c2_c6_0);
    full_adder fa2_c5 (p[2][3], p[3][2], c2_c5_0, s2_c5_1, c2_c6_1);
    
    full_adder fa2_c6_0 (p[3][3], p[4][2], s1_c6_0, s2_c6_0, c2_c7_0);
    full_adder fa2_c6_1 (p[2][4], c2_c6_0, c2_c6_1, s2_c6_1, c2_c7_1);

    half_adder ha2_c7 (s1_c7_0, s1_c7_1, s2_c7_0, c2_c8_0);
    full_adder fa2_c7 (p[2][5], c2_c7_0, c2_c7_1, s2_c7_1, c2_c8_1);

    half_adder ha2_c8 (s1_c8_0, s1_c8_1, s2_c8_0, c2_c9_0);
    full_adder fa2_c8 (c1_c8_1, c2_c8_0, c2_c8_1, s2_c8_1, c2_c9_1);

    full_adder fa2_c9_0 (c1_c9_0, c1_c9_1, s1_c9_0, s2_c9_0, c2_c10_0);
    full_adder fa2_c9_1 (p[4][5], c2_c9_0, c2_c9_1, s2_c9_1, c2_c10_1);

    full_adder fa2_c10_0 (p[6][4], p[7][3], c1_c10_0, s2_c10_0, c2_c11_0);
    full_adder fa2_c10_1 (p[5][5], c2_c10_0, c2_c10_1, s2_c10_1, c2_c11_1);

    full_adder fa2_c11 (p[6][5], p[7][4], c2_c11_0, s2_c11_0, c2_c12_0);

    // ========================================================================
    // REDUÇÃO - ESTÁGIO 3 (Alvo: Máximo 3 bits por coluna)
    // ========================================================================
    wire s3_c3_0, c3_c4_0;
    wire s3_c4_0, c3_c5_0;
    wire s3_c5_0, c3_c6_0;
    wire s3_c6_0, c3_c7_0;
    wire s3_c7_0, c3_c8_0;
    wire s3_c8_0, c3_c9_0;
    wire s3_c9_0, c3_c10_0;
    wire s3_c10_0, c3_c11_0;
    wire s3_c11_0, c3_c12_0;
    wire s3_c12_0, c3_c13_0;

    half_adder ha3_c3 (p[2][1], p[3][0], s3_c3_0, c3_c4_0);
    full_adder fa3_c4 (p[2][2], s2_c4_0, c3_c4_0, s3_c4_0, c3_c5_0);
    full_adder fa3_c5 (p[1][4], s2_c5_0, s2_c5_1, s3_c5_0, c3_c6_0); // p[0][5] passa
    full_adder fa3_c6 (p[1][5], s2_c6_0, s2_c6_1, s3_c6_0, c3_c7_0); // p[0][6] passa
    full_adder fa3_c7 (p[1][6], s2_c7_0, s2_c7_1, s3_c7_0, c3_c8_0); // p[0][7] passa
    full_adder fa3_c8 (p[2][6], s2_c8_0, s2_c8_1, s3_c8_0, c3_c9_0); // p[1][7] passa
    full_adder fa3_c9 (p[3][6], s2_c9_0, s2_c9_1, s3_c9_0, c3_c10_0); // p[2][7] passa
    full_adder fa3_c10 (p[4][6], s2_c10_0, s2_c10_1, s3_c10_0, c3_c11_0); // p[3][7] passa
    full_adder fa3_c11 (p[5][6], s2_c11_0, c2_c11_1, s3_c11_0, c3_c12_0); // p[4][7] passa
    full_adder fa3_c12 (p[6][6], p[7][5], c2_c12_0, s3_c12_0, c3_c13_0); // p[5][7] passa

    // ========================================================================
    // REDUÇÃO - ESTÁGIO 4 (Alvo: Exatamente 2 bits por coluna -> A e B do CLA)
    // ========================================================================
    wire [15:0] final_A, final_B;

    // Colunas 0 e 1 já tinham < 3 bits e passam direto desde a matriz
    assign final_A[0] = p[0][0]; assign final_B[0] = 1'b0;
    assign final_A[1] = p[0][1]; assign final_B[1] = p[1][0];

    half_adder ha4_c2 (p[0][2], p[1][1], final_A[2], final_B[3]);
    assign final_B[2] = p[2][0]; // Fio de passagem

    full_adder fa4_c3 (p[0][3], p[1][2], s3_c3_0, final_A[3], final_B[4]);
    full_adder fa4_c4 (p[0][4], p[1][3], s3_c4_0, final_A[4], final_B[5]);
    full_adder fa4_c5 (p[0][5], c3_c5_0, s3_c5_0, final_A[5], final_B[6]);
    full_adder fa4_c6 (p[0][6], c3_c6_0, s3_c6_0, final_A[6], final_B[7]);
    full_adder fa4_c7 (p[0][7], c3_c7_0, s3_c7_0, final_A[7], final_B[8]);
    full_adder fa4_c8 (p[1][7], c3_c8_0, s3_c8_0, final_A[8], final_B[9]);
    full_adder fa4_c9 (p[2][7], c3_c9_0, s3_c9_0, final_A[9], final_B[10]);
    full_adder fa4_c10 (p[3][7], c3_c10_0, s3_c10_0, final_A[10], final_B[11]);
    full_adder fa4_c11 (p[4][7], c3_c11_0, s3_c11_0, final_A[11], final_B[12]);
    full_adder fa4_c12 (p[5][7], c3_c12_0, s3_c12_0, final_A[12], final_B[13]);
    
    full_adder fa4_c13 (p[6][7], p[7][6], c3_c13_0, final_A[13], final_B[14]);
    
    assign final_A[14] = p[7][7];
    assign final_A[15] = 1'b0;
    assign final_B[15] = 1'b0; // Overflow descartado

    // ========================================================================
    // SOMA FINAL (CLA Rápido e Paralelo)
    // ========================================================================
    cla_adder adder_inst (
        .a(final_A),
        .b(final_B),
        .sum(Prod)
    );

endmodule