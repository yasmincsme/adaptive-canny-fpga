`timescale 1ns / 1ps

module tb_nms_window_buffer;

    // Parâmetro de teste reduzido
    parameter TEST_WIDTH = 6; 

    // Entradas
    reg clk;
    reg rst_n;
    reg pixel_vld_in;
    reg [11:0] magnitude_in;
    reg [1:0]  direction_in;

    // Saídas
    wire [11:0] mag00, mag01, mag02;
    wire [11:0] mag10, mag11, mag12;
    wire [11:0] mag20, mag21, mag22;
    wire [1:0]  dir_center;
    wire        win_vld_out;

    // Instanciação do módulo sob teste (UUT) com WIDTH = 6
    nms_window_buffer #(
        .WIDTH(TEST_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld_in(pixel_vld_in),
        .magnitude_in(magnitude_in),
        .direction_in(direction_in),
        
        .mag00(mag00), .mag01(mag01), .mag02(mag02),
        .mag10(mag10), .mag11(mag11), .mag12(mag12),
        .mag20(mag20), .mag21(mag21), .mag22(mag22),
        
        .dir_center(dir_center),
        .win_vld_out(win_vld_out)
    );

    // Geração de Clock (Período de 10ns -> 100MHz)
    always #5 clk = ~clk;

    // Variáveis de controle do teste
    integer i;

    // Monitoramento automático da saída
    always @(posedge clk) begin
        if (win_vld_out) begin
            $display("--- Janela Valida no Tempo %0t ---", $time);
            // Imprime a matriz 3x3. Note a organização: 
            // Linha 2 (mais antiga), Linha 1 (meio), Linha 0 (nova)
            $display("[%3d] [%3d] [%3d]", mag20, mag21, mag22);
            $display("[%3d] [%3d] [%3d]  --> Dir Centro: %b", mag10, mag11, mag12, dir_center);
            $display("[%3d] [%3d] [%3d]", mag00, mag01, mag02);
            $display("----------------------------------");
        end
    end

    // Bloco principal de estímulos
    initial begin
        // Inicialização
        $display("Iniciando Simulacao do NMS Window Buffer...");
        clk = 0;
        rst_n = 0;
        pixel_vld_in = 0;
        magnitude_in = 0;
        direction_in = 0;

        // Reset da máquina
        #20;
        rst_n = 1;
        #10;

        // Injeta 4 linhas de imagem (4 * 6 = 24 pixels)
        for (i = 1; i <= (TEST_WIDTH * 4); i = i + 1) begin
            @(negedge clk);
            pixel_vld_in = 1'b1;
            magnitude_in = i;               // Magnitude cresce: 1, 2, 3, 4...
            direction_in = i[1:0];          // Direção varia entre 00, 01, 10, 11
        end

        // Pausa o envio de pixels
        @(negedge clk);
        pixel_vld_in = 0;
        magnitude_in = 0;
        
        #50;
        $display("Simulacao Concluida.");
        $finish;
    end

endmodule