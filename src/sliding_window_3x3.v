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

    / =========================================================================
    // 3. LÓGICA DE CONTROLE DE VALIDADE E BORDAS
    // =========================================================================
    
    // Além do contador global, precisamos saber em qual coluna estamos
    reg [31:0] pixel_count;
    reg [15:0] col_count; // Contador de 0 até WIDTH-1

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 0;
            col_count   <= 0;
            win_vld     <= 0;
        end else if (pixel_vld) begin
            
            // 1. Atualiza o contador de preenchimento do pipeline
            if (pixel_count < (WIDTH * 3))
                pixel_count <= pixel_count + 1;
                
            // 2. Atualiza o contador de coluna (Wrap-around horizontal)
            if (col_count == (WIDTH - 1))
                col_count <= 0;
            else
                col_count <= col_count + 1;

            // 3. Condição de Validade Estrita:
            // - O pipeline inicial de 2 linhas deve estar cheio (pixel_count >= 2*WIDTH + 2)
            // - A janela não pode estar cruzando de uma linha para a outra (col_count >= 2)
            // Nota: O '2' avalia o estado atual instantes ANTES do 3º pixel ser registrado.
            if ((pixel_count >= (WIDTH * 2 + 2)) && (col_count >= 2)) begin
                win_vld <= 1'b1;
            end else begin
                win_vld <= 1'b0; // Força zero nas bordas ou se o pipeline estiver vazio
            end
            
        end else begin
            win_vld <= 1'b0; // Pausa se a entrada de pixels parar
        end
    end

endmodule