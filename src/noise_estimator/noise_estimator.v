`timescale 1ns / 1ps

// Estimador de Ruído para o Canny APS
//
// Baseado na Secção V.A do artigo de Kalbasi & Nikmehr (IEEE Access, 2020):
// calcula a razão entre píxeis corrompidos e o total de píxeis na janela,
// codificando o resultado num número de 4 bits que representa uma das
// 14 intensidades de ruído quantizadas: {5%, 10%, ..., 65%, 70%}.
//
// Método: para cada píxel da região interior 5x5 da janela 7x7,
// compara-se o valor do píxel com a média dos seus 4 vizinhos cardinais.
// Se |píxel - média_vizinhos| > limiar, o píxel é considerado corrompido.
// A contagem final é quantizada no nível de ruído correspondente.

module noise_estimator (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [391:0] window_flat,  // Janela 7x7 achatada (49 píxeis × 8 bits)
    input  wire [7:0]   threshold,    // Limiar para detecção de píxel corrompido
    output reg  [3:0]   noise_level,  // Nível de ruído quantizado (0–13 → 5%–70%)
    output wire         done
);

    // ========================================================================
    // 1. SINAIS INTERNOS
    // ========================================================================
    wire        clr_cnt;
    wire        compare_en;
    wire        write_en;
    wire        all_pixels_done;

    reg  [2:0]  row_cnt;          // Linha na região interior (0–4)
    reg  [2:0]  col_cnt;          // Coluna na região interior (0–4)
    reg  [4:0]  corrupted_cnt;    // Contador de píxeis corrompidos (máx. 25)

    // ========================================================================
    // 2. DESEMPACOTAMENTO DA JANELA 7×7
    // ========================================================================
    wire [7:0] window_array [0:48];

    genvar gi;
    generate
        for (gi = 0; gi < 49; gi = gi + 1) begin : unflatten
            assign window_array[gi] = window_flat[(gi*8) + 7 : (gi*8)];
        end
    endgenerate

    // ========================================================================
    // 3. CÁLCULO DOS ÍNDICES
    // ========================================================================
    // Posição real na grelha 7×7: (actual_row, actual_col) = (row_cnt+1, col_cnt+1)
    // Índice linear: actual_row × 7 + actual_col
    // Multiplicação por 7 via shift-add: x×7 = (x<<3) − x
    wire [5:0] actual_row  = {3'b0, row_cnt} + 6'd1;
    wire [5:0] actual_col  = {3'b0, col_cnt} + 6'd1;
    wire [5:0] center_idx  = (actual_row << 3) - actual_row + actual_col;
    wire [5:0] top_idx     = center_idx - 6'd7;
    wire [5:0] bottom_idx  = center_idx + 6'd7;
    wire [5:0] left_idx    = center_idx - 6'd1;
    wire [5:0] right_idx   = center_idx + 6'd1;

    // ========================================================================
    // 4. SELECÇÃO DOS PÍXEIS (MUX inferido pelo sintetizador)
    // ========================================================================
    wire [7:0] pixel_center = window_array[center_idx];
    wire [7:0] pixel_top    = window_array[top_idx];
    wire [7:0] pixel_bottom = window_array[bottom_idx];
    wire [7:0] pixel_left   = window_array[left_idx];
    wire [7:0] pixel_right  = window_array[right_idx];

    // ========================================================================
    // 5. MÉDIA DOS 4 VIZINHOS CARDINAIS
    // ========================================================================
    // Soma de 4 valores de 8 bits → 10 bits
    // Divisão por 4 implementada como deslocamento de 2 bits (custo zero em HW)
    wire [9:0] neighbor_sum = {2'b0, pixel_top}    + {2'b0, pixel_bottom}
                            + {2'b0, pixel_left}   + {2'b0, pixel_right};
    wire [7:0] neighbor_avg = neighbor_sum[9:2];

    // ========================================================================
    // 6. DIFERENÇA ABSOLUTA E DETECÇÃO DE CORRUPÇÃO
    // ========================================================================
    wire [7:0] abs_diff = (pixel_center >= neighbor_avg)
                        ? (pixel_center - neighbor_avg)
                        : (neighbor_avg - pixel_center);

    wire is_corrupted = (abs_diff > threshold);

    // ========================================================================
    // 7. MÁQUINA DE ESTADOS (noise_estimator_uc)
    // ========================================================================
    noise_estimator_uc fsm_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .all_pixels_done (all_pixels_done),
        .clr_cnt         (clr_cnt),
        .compare_en      (compare_en),
        .write_en        (write_en),
        .done            (done)
    );

    // ========================================================================
    // 8. CONTADORES DE LINHA E COLUNA
    // ========================================================================
    assign all_pixels_done = (row_cnt == 3'd4) && (col_cnt == 3'd4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cnt <= 3'd0;
            col_cnt <= 3'd0;
        end else if (clr_cnt) begin
            row_cnt <= 3'd0;
            col_cnt <= 3'd0;
        end else if (compare_en) begin
            if (col_cnt == 3'd4) begin
                col_cnt <= 3'd0;
                row_cnt <= row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    // ========================================================================
    // 9. CONTADOR DE PÍXEIS CORROMPIDOS
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            corrupted_cnt <= 5'd0;
        else if (clr_cnt)
            corrupted_cnt <= 5'd0;
        else if (compare_en && is_corrupted)
            corrupted_cnt <= corrupted_cnt + 1'b1;
    end

    // ========================================================================
    // 10. QUANTIZAÇÃO: MAPEAMENTO DA CONTAGEM PARA NÍVEL DE RUÍDO
    // ========================================================================
    // 25 píxeis interiores → cada píxel ≈ 4% do total.
    // Fronteiras definidas nos pontos médios entre níveis consecutivos de 5%.
    //
    //  Contagem   Percentagem aprox.   Nível (4 bits)   Intensidade
    //  --------   ------------------   --------------   -----------
    //   0 – 1           0 – 6%           4'd0              5%
    //     2              8%              4'd1             10%
    //   3 – 4          12 – 16%          4'd2             15%
    //     5             20%              4'd3             20%
    //     6             24%              4'd4             25%
    //   7 – 8          28 – 32%          4'd5             30%
    //     9             36%              4'd6             35%
    //    10             40%              4'd7             40%
    //    11             44%              4'd8             45%
    //  12 – 13         48 – 52%          4'd9             50%
    //    14             56%              4'd10            55%
    //    15             60%              4'd11            60%
    //    16             64%              4'd12            65%
    //  17 – 25         68 – 100%         4'd13            70%

    reg [3:0] noise_level_q;

    always @(*) begin
        if      (corrupted_cnt < 5'd2)  noise_level_q = 4'd0;
        else if (corrupted_cnt < 5'd3)  noise_level_q = 4'd1;
        else if (corrupted_cnt < 5'd5)  noise_level_q = 4'd2;
        else if (corrupted_cnt < 5'd6)  noise_level_q = 4'd3;
        else if (corrupted_cnt < 5'd7)  noise_level_q = 4'd4;
        else if (corrupted_cnt < 5'd9)  noise_level_q = 4'd5;
        else if (corrupted_cnt < 5'd10) noise_level_q = 4'd6;
        else if (corrupted_cnt < 5'd11) noise_level_q = 4'd7;
        else if (corrupted_cnt < 5'd12) noise_level_q = 4'd8;
        else if (corrupted_cnt < 5'd14) noise_level_q = 4'd9;
        else if (corrupted_cnt < 5'd15) noise_level_q = 4'd10;
        else if (corrupted_cnt < 5'd16) noise_level_q = 4'd11;
        else if (corrupted_cnt < 5'd17) noise_level_q = 4'd12;
        else                            noise_level_q = 4'd13;
    end

    // ========================================================================
    // 11. REGISTRADOR DE SAÍDA
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            noise_level <= 4'd0;
        else if (write_en)
            noise_level <= noise_level_q;
    end

endmodule
