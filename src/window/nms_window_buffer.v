//`timescale 1ns / 1ps

module nms_window_buffer #(
    parameter WIDTH = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Entradas vindas do gradient_datapath
    input  wire        pixel_vld_in,
    input  wire [11:0] magnitude_in,
    input  wire [1:0]  direction_in,
    
    // Saídas desempacotadas para o módulo NMS
    output wire [11:0] mag00, output wire [11:0] mag01, output wire [11:0] mag02,
    output wire [11:0] mag10, output wire [11:0] mag11, output wire [11:0] mag12,
    output wire [11:0] mag20, output wire [11:0] mag21, output wire [11:0] mag22,
    
    // Direção apenas do pixel central (linha 1, coluna 1)
    output wire [1:0]  dir_center,
    
    // Sinal indicando que a janela 3x3 do NMS é válida
    output wire        win_vld_out
);

    // 1. EMPACOTAMENTO DA ENTRADA (14 bits: [13:12] = direção, [11:0] = magnitude)
    wire [13:0] packed_pixel_in;
    assign packed_pixel_in = {direction_in, magnitude_in};

    // 2. FIOS PARA AS SAÍDAS DA JANELA 3x3 (14 bits cada)
    wire [13:0] w_win00, w_win01, w_win02;
    wire [13:0] w_win10, w_win11, w_win12;
    wire [13:0] w_win20, w_win21, w_win22;

    // 3. INSTANCIAÇÃO DO SEU MÓDULO SLIDING WINDOW
    // Sobrescrevendo o DATA_WIDTH para 14 bits
    sliding_window_3x3 #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(14)
    ) inst_sliding_window (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(pixel_vld_in),
        .pixel_in(packed_pixel_in),
        
        .win00(w_win00), .win01(w_win01), .win02(w_win02),
        .win10(w_win10), .win11(w_win11), .win12(w_win12),
        .win20(w_win20), .win21(w_win21), .win22(w_win22),
        
        .win_vld(win_vld_out)
    );

    // 4. DESEMPACOTAMENTO PARA O NMS
    // Extraindo apenas os 12 bits inferiores para a grade de magnitudes
    assign mag00 = w_win00[11:0];
    assign mag01 = w_win01[11:0];
    assign mag02 = w_win02[11:0];
    
    assign mag10 = w_win10[11:0];
    assign mag11 = w_win11[11:0]; // Pixel Central
    assign mag12 = w_win12[11:0];
    
    assign mag20 = w_win20[11:0];
    assign mag21 = w_win21[11:0];
    assign mag22 = w_win22[11:0];

    // Extraindo a direção do pixel central (bits 13 e 12 do win11)
    assign dir_center = w_win11[13:12];

endmodule