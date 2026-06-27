`timescale 1ns / 1ps

module sliding_window_7x7_flex #(
    parameter WIDTH = 512,        // Largura da imagem em pixels
    parameter DATA_WIDTH = 8      // 8 bits por pixel (escala de cinza)
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [1:0]              kernel_size, // 00=3x3, 01=5x5, 10=7x7
    input  wire                    pixel_vld,   // Pixel de entrada é válido
    input  wire [DATA_WIDTH-1:0]   pixel_in,    // Dado do pixel atual
    
    output wire                     win_vld,     // Indica se a janela está pronta
    output wire [(49*DATA_WIDTH)-1:0] window_data // Matriz 7x7 achatada (392 bits)
);

    // =========================================================================
    // 1. DECLARAÇÃO DOS FIOS E CONEXÕES DOS LINE BUFFERS
    // =========================================================================
    // Sinais que conectam a saída de um Line Buffer na entrada do próximo
    wire [DATA_WIDTH-1:0] lb_out [0:5];

    // Instanciação dos 6 Line Buffers necessários para o pior caso (7x7)
    // lb0 guarda a linha atual e entrega a Linha -1
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) lb0 (
        .clk(clk), .rst_n(rst_n), .pixel_vld(pixel_vld), .pixel_in(pixel_in), .pixel_out(lb_out[0])
    );
    // lb1 recebe a Linha -1 e entrega a Linha -2
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) lb1 (
        .clk(clk), .rst_n(rst_n), .pixel_vld(pixel_vld), .pixel_in(lb_out[0]), .pixel_out(lb_out[1])
    );
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) lb2 (
        .clk(clk), .rst_n(rst_n), .pixel_vld(pixel_vld), .pixel_in(lb_out[1]), .pixel_out(lb_out[2])
    );
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) lb3 (
        .clk(clk), .rst_n(rst_n), .pixel_vld(pixel_vld), .pixel_in(lb_out[2]), .pixel_out(lb_out[3])
    );
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) lb4 (
        .clk(clk), .rst_n(rst_n), .pixel_vld(pixel_vld), .pixel_in(lb_out[3]), .pixel_out(lb_out[4])
    );
    // lb5 recebe a Linha -5 e entrega a Linha -6
    line_buffer #(.WIDTH(WIDTH), .DATA_WIDTH(DATA_WIDTH)) lb5 (
        .clk(clk), .rst_n(rst_n), .pixel_vld(pixel_vld), .pixel_in(lb_out[4]), .pixel_out(lb_out[5])
    );

    // =========================================================================
    // 2. MATRIZ FÍSICA DE REGISTRADORES 7x7
    // =========================================================================
    reg [DATA_WIDTH-1:0] win [0:6][0:6];
    integer r, c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Zera todos os 49 registradores no reset
            for (r = 0; r < 7; r = r + 1) begin
                for (c = 0; c < 7; c = c + 1) begin
                    win[r][c] <= 0;
                end
            end
        end else if (pixel_vld) begin
            // Deslocamento horizontal em cascata (Shift Register Bidimensional)
            for (r = 0; r < 7; r = r + 1) begin
                win[r][0] <= win[r][1];
                win[r][1] <= win[r][2];
                win[r][2] <= win[r][3];
                win[r][3] <= win[r][4];
                win[r][4] <= win[r][5];
                win[r][5] <= win[r][6];
            end

            // Alimenta a última coluna de cada linha com os dados atrasados corretos
            win[0][6] <= pixel_in;   // Linha 0 (Atual) recebe direto da entrada
            win[1][6] <= lb_out[0];  // Linha 1 recebe o atraso de 1 linha
            win[2][6] <= lb_out[1];  // Linha 2 recebe o atraso de 2 linhas
            win[3][6] <= lb_out[2];  // Linha 3 recebe o atraso de 3 linhas
            win[4][6] <= lb_out[3];  // Linha 4 recebe o atraso de 4 linhas
            win[5][6] <= lb_out[4];  // Linha 5 recebe o atraso de 5 linhas
            win[6][6] <= lb_out[5];  // Linha 6 recebe o atraso de 6 linhas
        end
    end

    // =========================================================================
    // 3. INSTANCIAÇÃO DA FSM DE CONTROLE
    // =========================================================================
    wire [31:0] w_pixel_count; // Conecta o registrador do contador à FSM
    wire        w_count_en;    // Conecta a permissão de contagem da FSM à Janela

    sliding_window_fsm #(
        .WIDTH(WIDTH)
    ) u_sliding_window_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .pixel_vld   (pixel_vld),
        .kernel_size (kernel_size),
        .pixel_count (w_pixel_count),
        .count_en    (w_count_en),
        .win_vld     (win_vld) // Saída da FSM vai direto para a saída do módulo Top
    );

    // Lógica do Contador que reside no Datapath da Janela
    reg [31:0] r_pixel_count;
    assign w_pixel_count = r_pixel_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_pixel_count <= 0;
        end else if (pixel_vld && w_count_en) begin
            if (r_pixel_count < (WIDTH * 8)) // Proteção contra estouro de bits
                r_pixel_count <= r_pixel_count + 1;
        end
    end    
    
    
    // =========================================================================
    // 4. ACHATAMENTO DA MATRIZ PARA O BARRAMENTO DE SAÍDA (FLATTENING)
    // =========================================================================
    // Mapeia a estrutura bidimensional win[r][c] consecutivamente no vetor largo.
    // win[0][0] ocupa os bits mais baixos [7:0], win[6][6] ocupa os mais altos [391:384].
    genvar i, j;
    generate
        for (i = 0; i < 7; i = i + 1) begin : GEN_ROW
            for (j = 0; j < 7; j = j + 1) begin : GEN_COL
                assign window_data[((i*7+j)*DATA_WIDTH) +: DATA_WIDTH] = win[i][j];
            end
        end
    endgenerate

endmodule