//`timescale 1ns / 1ps

module sliding_window_3x3 #(
    parameter WIDTH = 512,
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  pixel_vld,
    input  wire [DATA_WIDTH-1:0] pixel_in,
    
    // Sinais de saída: Os 9 pixels da vizinhança disponíveis ao mesmo tempo
    // Organizados como win[linha][coluna]
    output reg  [DATA_WIDTH-1:0] win00, output reg  [DATA_WIDTH-1:0] win01, output reg  [DATA_WIDTH-1:0] win02,
    output reg  [DATA_WIDTH-1:0] win10, output reg  [DATA_WIDTH-1:0] win11, output reg  [DATA_WIDTH-1:0] win12,
    output reg  [DATA_WIDTH-1:0] win20, output reg  [DATA_WIDTH-1:0] win21, output reg  [DATA_WIDTH-1:0] win22,
    
    // Sinal que indica que a vizinhança na saída é válida para operação matemáica
    output reg                   win_vld
);

    // Fios para conectar as saídas dos Line Buffers
    wire [DATA_WIDTH-1:0] w_line_out_0;
    wire [DATA_WIDTH-1:0] w_line_out_1;

    // Contador de pixels/linhas para saber quando a matriz foi totalmente preenchida
    reg [31:0] pixel_count;
    wire start_convolution;

    // =========================================================================
    // 1. INSTANCIAÇÃO DOS LINE BUFFERS (CASCATA)
    // =========================================================================
    
    // Line Buffer 0: Recebe a linha atual e cospe a linha anterior (atraso de 1 linha)
    line_buffer #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) lb0 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(pixel_vld),
        .pixel_in(pixel_in),
        .pixel_out(w_line_out_0)
    );

    // Line Buffer 1: Recebe a linha anterior e cospe a de duas linhas atrás (atraso de 2 linhas)
    line_buffer #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) lb1 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(pixel_vld),
        .pixel_in(w_line_out_0),
        .pixel_out(w_line_out_1)
    );

    // =========================================================================
    // 2. MATRIZ DE REGISTRADORES (SLIDING WINDOW)
    // =========================================================================
    // Movimentação dos dados da direita para a esquerda a cada clock válido
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            win00 <= 0; win01 <= 0; win02 <= 0;
            win10 <= 0; win11 <= 0; win12 <= 0;
            win20 <= 0; win21 <= 0; win22 <= 0;
        end else if (pixel_vld) begin
            // Linha 0: Recebe o pixel que está entrando no sistema agora
            win00 <= win01;
            win01 <= win02;
            win02 <= pixel_in;

            // Linha 1: Recebe o pixel que está saindo do primeiro Line Buffer (atrasado por 1 linha)
            win10 <= win11;
            win11 <= win12;
            win12 <= w_line_out_0;

            // Linha 2: Recebe o pixel que está saindo do segundo Line Buffer (atrasado por 2 linhas)
            win20 <= win21;
            win21 <= win22;
            win22 <= w_line_out_1;
        end
    end

    // =========================================================================
    // 3. LÓGICA DE CONTROLE DE VALIDADE (BORDA DA IMAGEM)
    // =========================================================================
    // A convolução só deve começar quando tivermos pelo menos 2 linhas inteiras 
    // e mais 3 pixels injetados no circuito (para preencher a matriz 3x3).
    
    assign start_convolution = (pixel_count >= (WIDTH * 2 + 3));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 0;
            win_vld     <= 0;
        end else if (pixel_vld) begin
            if (pixel_count < (WIDTH * 3)) // Evita estouro do contador no teste
                pixel_count <= pixel_count + 1;
                
            win_vld <= start_convolution;
        end else begin
            win_vld <= 0; // Se o pixel de entrada parar, a saída também pausa
        end
    end

endmodule