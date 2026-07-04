//`timescale 1ns / 1ps

module hysteresis_datapath #(
    parameter IMG_WIDTH   = 512, // Largura da imagem para os Line Buffers
    parameter MAG_WIDTH   = 12   // Largura de bits da magnitude de entrada
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Entradas vindas da etapa NMS (Supressão de Não-Máximos)
    input  wire [MAG_WIDTH-1:0] nms_mag_in,
    input  wire                 nms_vld_in,
    // valores para o threshold
    input wire [MAG_WIDTH-1:0] HIGH_THRESH,
    input wire [MAG_WIDTH-1:0] LOW_THRESH,
    // Saídas finais do Algoritmo de Canny
    output wire [7:0]           final_pixel_out, // 0 (Preto) ou 255 (Branco)
    output wire                 final_vld_out    // Indica se o píxel final é válido
);

    // =========================================================================
    // FIOS DE INTERLIGAÇÃO (PIPELINE)
    // =========================================================================
    
    // Fios entre o Módulo 1 (Threshold) e o Módulo 2 (Buffer)
    wire [1:0] w_edge_type; // 2'b11 (Forte), 2'b01 (Fraca), 2'b00 (Fundo)
    wire       w_thresh_vld;

    // Fios entre o Módulo 2 (Buffer) e o Módulo 3 (Lógica de Histerese)
    wire [1:0] w_win00, w_win01, w_win02;
    wire [1:0] w_win10, w_win11, w_win12;
    wire [1:0] w_win20, w_win21, w_win22;
    wire       w_win_vld;

    // =========================================================================
    // INSTÂNCIA 1: CLASSIFICADOR (Double Thresholding)
    // =========================================================================
    // Transforma os 12 bits de magnitude em apenas 2 bits de classificação.
    double_threshold #(
        .WIDTH(MAG_WIDTH)
    ) inst_double_thresh (
        .HIGH_THRESH(HIGH_THRESH),
        .LOW_THRESH(LOW_THRESH),
        .nms_mag_in(nms_mag_in),
        .nms_vld_in(nms_vld_in),
        .edge_type_out(w_edge_type),
        .vld_out(w_thresh_vld)
    );

    // =========================================================================
    // INSTÂNCIA 2: BUFFER DA HISTERESE (Janela Deslizante de 2 bits)
    // =========================================================================
    // Reutilizamos o Sliding Window, mas agora configurado para apenas 2 bits!
    // Ele cria uma matriz 3x3 das classificações para verificarmos os vizinhos.
    //
    // WIDTH = IMG_WIDTH-4: pelo momento em que o stream chega aqui, os dois
    // estágios anteriores (janela do Sobel e janela do NMS) já descartaram
    // 2+2=4 amostras por linha real. Sem esse ajuste, o contador de coluna
    // desta janela ficaria fora de fase com as linhas reais e a detecção de
    // borda sofreria deriva diagonal progressiva ao longo da imagem.
    sliding_window_3x3 #(
        .WIDTH(IMG_WIDTH-4),
        .DATA_WIDTH(2)       // A MAGIA DA OTIMIZAÇÃO: Apenas 2 bits por píxel!
    ) inst_hysteresis_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(w_thresh_vld),
        .pixel_in(w_edge_type),
        
        .win00(w_win00), .win01(w_win01), .win02(w_win02),
        .win10(w_win10), .win11(w_win11), .win12(w_win12),
        .win20(w_win20), .win21(w_win21), .win22(w_win22),
        
        .win_vld(w_win_vld)
    );

    // =========================================================================
    // INSTÂNCIA 3: LÓGICA DE HISTERESE (Conectividade)
    // =========================================================================
    // Avalia a janela 3x3 e promove as bordas fracas conectadas a bordas fortes.
    hysteresis_logic inst_hysteresis_logic (
        .win00(w_win00), .win01(w_win01), .win02(w_win02),
        .win10(w_win10), .win11(w_win11), .win12(w_win12),
        .win20(w_win20), .win21(w_win21), .win22(w_win22),
        .win_vld_in(w_win_vld),
        
        .edge_pixel_out(final_pixel_out),
        .pixel_vld_out(final_vld_out)
    );

endmodule