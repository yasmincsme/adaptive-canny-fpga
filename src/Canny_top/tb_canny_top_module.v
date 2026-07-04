`timescale 1ns / 1ps

module tb_canny_top_module;

    // =========================================================================
    // PARÂMETROS DA SIMULAÇÃO
    // =========================================================================
    parameter IMG_WIDTH  = 32;
    parameter IMG_HEIGHT = 32;
    parameter DATA_WIDTH = 8;
    parameter MAG_WIDTH  = 12;
    
    // O tamanho da imagem de saída será menor devido à perda das bordas
    // Perdas: Gauss(7x7)=-6, Gradiente(3x3)=-2, NMS(3x3)=-2, Histerese(3x3)=-2 
    // Total perdido nas bordas = 12 píxeis.
    parameter OUT_WIDTH = IMG_WIDTH - 12;

    // =========================================================================
    // SINAIS DO DUT
    // =========================================================================
    reg                   clk;
    reg                   rst_n;
    reg  [DATA_WIDTH-1:0] pixel_in;
    reg                   pixel_vld_in;
    wire                  ready;
    
    reg  [MAG_WIDTH-1:0]  high_thresh;
    reg  [MAG_WIDTH-1:0]  low_thresh;
    wire [7:0]            gauss_peso;
    wire [5:0]            gauss_addr;
    
    wire [7:0]            final_pixel_out;
    wire                  final_vld_out;

    // =========================================================================
    // INSTANCIAÇÃO DO TOP MODULE
    // =========================================================================
    canny_top_module #(
        .IMG_WIDTH(IMG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAG_WIDTH(MAG_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_in),
        .pixel_vld_in(pixel_vld_in),
        .ready(ready),
        .HIGH_THRESH(high_thresh),
        .LOW_THRESH(low_thresh),
        .gauss_peso(gauss_peso),
        .gauss_addr(gauss_addr),
        .final_pixel_out(final_pixel_out),
        .final_vld_out(final_vld_out)
    );

    // =========================================================================
    // SIMULAÇÃO DA ROM DE PESOS (Kernel 3x3 centralizado em 7x7)
    // Apenas a região central [2:4][2:4] contém valores, o resto é zero.
    // =========================================================================
    reg [7:0] rom_pesos [0:63];
    integer r;
    initial begin
        // Zera todos os endereços para garantir que o "padding" de zeros funcione
        for (r = 0; r < 64; r = r + 1) begin
            rom_pesos[r] = 8'd0; 
        end
        /*
        // O kernel 3x3 padrão (Soma = 16) centralizado na grade 7x7
        // Linha 0-1: 0 (zeros, como esperado)
        
        // Linha 2 (Índices 14 a 20)
        rom_pesos[16] = 1; rom_pesos[17] = 2; rom_pesos[18] = 1;
        
        // Linha 3 (Índices 21 a 27)
        rom_pesos[23] = 2; rom_pesos[24] = 4; rom_pesos[25] = 2;
        
        // Linha 4 (Índices 28 a 34)
        rom_pesos[30] = 1; rom_pesos[31] = 2; rom_pesos[32] = 1;
        
        // Linhas 5-6: 0 (zeros)
        */
        rom_pesos[24] = 8'd255;
    end
    
    assign gauss_peso = rom_pesos[gauss_addr];

    // =========================================================================
    // GERAÇÃO DA IMAGEM DE TESTE (Um quadrado de 16x16 no centro) E EXPORTAÇÃO
    // =========================================================================
    reg [DATA_WIDTH-1:0] image_in [0:(IMG_WIDTH*IMG_HEIGHT)-1];
    integer row, col;
    integer file_in; // Descritor do arquivo de entrada

    initial begin
        // 1. Gera a imagem na memória
        for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
            for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                if (row >= 8 && row < 24 && col >= 8 && col < 24)
                    image_in[row*IMG_WIDTH + col] = 8'd200; // Forma Branca (Alto Contraste)
                else
                    image_in[row*IMG_WIDTH + col] = 8'd0;   // Fundo Preto
            end
        end
        
        // 2. Exporta a imagem gerada para um arquivo .hex (entrada_canny.hex)
        file_in = $fopen("entrada_canny.hex", "w");
        if (file_in) begin
            for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                    $fdisplay(file_in, "%02X", image_in[row*IMG_WIDTH + col]);
                end
            end
            $fclose(file_in);
            $display("Arquivo 'entrada_canny.hex' gerado com sucesso.");
        end else begin
            $display("ERRO: Nao foi possivel criar o arquivo entrada_canny.hex");
        end
    end

    // Geração de Clock
    always #5 clk = ~clk;

    // =========================================================================
    // EXPORTAÇÃO PARA ARQUIVO .HEX E MONITOR VISUAL
    // =========================================================================
    integer file_out;
    integer valid_count = 0;

    initial begin
        file_out = $fopen("saida_canny.hex", "w");
        if (!file_out) begin
            $display("ERRO: Nao foi possivel criar o arquivo saida_canny.hex");
            $finish;
        end
        $display("Arquivo 'saida_canny.hex' aberto para gravacao.");
        $display("=========================================================");
        $display("Renderizacao Visual (Apenas os pixeis centrais validos):");
    end

    always @(posedge clk) begin
        if (final_vld_out) begin
            // Escreve no ficheiro
            $fdisplay(file_out, "%02X", final_pixel_out);
            
            // Desenha no terminal
            if (final_pixel_out == 8'hFF) $write("## ");
            else                          $write(".. ");
            
            valid_count = valid_count + 1;
            
            if (valid_count % OUT_WIDTH == 0)
                $display("");
        end
    end

    // =========================================================================
    // MÁQUINA DE INJEÇÃO DE VÍDEO (Com Suporte a Backpressure e Flush)
    // =========================================================================
    integer idx = 0;
    
    initial begin
        clk = 0;
        rst_n = 0;
        pixel_in = 0;
        pixel_vld_in = 0;
        
        // Limiares levemente relaxados para garantir visibilidade da borda 
        // caso o Gaussiano crie um gradiente muito suave
        high_thresh = 12'd1;
        low_thresh  = 12'd1;
        
        #20 rst_n = 1; 
        
        $display("Iniciando injecao de video (Tamanho: 32x32)...");
        
        // 1. INJETA A IMAGEM REAL
        while (idx < (IMG_WIDTH * IMG_HEIGHT)) begin
            @(posedge clk);
            #1; 
            
            if (ready) begin
                pixel_in = image_in[idx];
                pixel_vld_in = 1'b1;
                idx = idx + 1;
            end else begin
                pixel_vld_in = 1'b0;
            end
        end
        
        $display("Imagem real enviada. Injetando pixeis nulos para esvaziar o pipeline...");
        
        // 2. INJETA PÍXEIS FALSOS (DUMMY) PARA EMPURRAR A IMAGEM ATÉ AO FIM
        idx = 0;
        while (idx < (13 * IMG_WIDTH)) begin
            @(posedge clk);
            #1;
            
            if (ready) begin
                pixel_in = 8'd0;     // Píxel vazio (preto)
                pixel_vld_in = 1'b1; // Mantém o pipeline a andar
                idx = idx + 1;
            end else begin
                pixel_vld_in = 1'b0;
            end
        end

        // Agora sim, podemos desligar o sinal de validade.
        @(posedge clk);
        #1 pixel_vld_in = 1'b0;
        
        // Aguarda que a última matemática termine
        #5000;
        
        $fclose(file_out);
        $display("=========================================================");
        $display("Simulacao Concluida com Sucesso!");
        $display("Pixeis validos exportados: %0d", valid_count);
        $display("Arquivo gerado: saida_canny.hex");
        $finish;
    end

endmodule