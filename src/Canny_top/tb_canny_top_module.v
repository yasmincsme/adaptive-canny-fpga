`timescale 1ns / 1ps

// Dimensões da imagem de entrada (IMG_WIDTH/IMG_HEIGHT), geradas por
// scripts/png_to_hex.py a partir de uma imagem real. Se este arquivo não
// existir, rode o script primeiro (ele mantém um valor padrão 32x32 até lá).
`include "image_params.vh"

module tb_canny_top_module;

    // =========================================================================
    // PARÂMETROS DA SIMULAÇÃO
    // =========================================================================
    parameter IMG_WIDTH  = `IMG_WIDTH;
    parameter IMG_HEIGHT = `IMG_HEIGHT;
    parameter DATA_WIDTH = 8;
    parameter MAG_WIDTH  = 12;
    
    // O tamanho da imagem de saída será menor devido à perda das bordas.
    // Medido empiricamente (testes de linha/coluna isolada) e confirmado em
    // múltiplos tamanhos de imagem:
    //   Largura: -6  (3 estágios em cascata de janela 3x3 -- Sobel, NMS,
    //                 Histerese -- cada um descarta 2 colunas por linha real)
    //   Altura:  -5  (tempo de preenchimento inicial do pipeline, dominado
    //                 pela janela 7x7 do Gauss; sem perda equivalente no fim,
    //                 pois o flush de píxeis nulos empurra o resto para fora)
    parameter OUT_WIDTH  = IMG_WIDTH  - 6;
    parameter OUT_HEIGHT = IMG_HEIGHT - 5;

    // =========================================================================
    // SINAIS DO DUT
    // =========================================================================
    reg                   clk;
    reg                   rst_n;
    reg  [DATA_WIDTH-1:0] pixel_r_in;
    reg  [DATA_WIDTH-1:0] pixel_g_in;
    reg  [DATA_WIDTH-1:0] pixel_b_in;
    reg                   pixel_vld_in;
    wire                  ready;
    
    reg  [MAG_WIDTH-1:0]  high_thresh;
    reg  [MAG_WIDTH-1:0]  low_thresh;
    wire [7:0]            gauss_peso;
    wire [5:0]            gauss_addr;

    // Seleção Adaptativa de Parâmetros (APS) — desligada nesta testbench para
    // preservar o comportamento original com limiares manuais.
    reg                   adaptive_en;
    reg  [1:0]            mdp;
    reg  [7:0]            noise_threshold;
    wire [1:0]            kernel_sel_out;

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
        .pixel_r_in(pixel_r_in),
        .pixel_g_in(pixel_g_in),
        .pixel_b_in(pixel_b_in),
        .pixel_vld_in(pixel_vld_in),
        .ready(ready),
        .HIGH_THRESH(high_thresh),
        .LOW_THRESH(low_thresh),
        .gauss_peso(gauss_peso),
        .gauss_addr(gauss_addr),
        .adaptive_en(adaptive_en),
        .mdp(mdp),
        .noise_threshold(noise_threshold),
        .kernel_sel_out(kernel_sel_out),
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
    // CARGA DA IMAGEM DE ENTRADA (entrada_canny.hex)
    // =========================================================================
    // Gerado por scripts/png_to_hex.py a partir de uma imagem real (PNG colorido),
    // ou o quadrado sintético 512x512 padrão se o script ainda não foi executado.
    // Cada linha do .hex é um pixel RGB de 24 bits: {R[7:0], G[7:0], B[7:0]}.
    // A conversão para escala de cinza acontece dentro do datapath (rgb_gray_average).
    reg [23:0] image_in [0:(IMG_WIDTH*IMG_HEIGHT)-1];

    initial begin
        $readmemh("entrada_canny.hex", image_in);
        $display("Imagem 'entrada_canny.hex' carregada (%0dx%0d, RGB).", IMG_WIDTH, IMG_HEIGHT);
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
        pixel_r_in = 0;
        pixel_g_in = 0;
        pixel_b_in = 0;
        pixel_vld_in = 0;
        adaptive_en = 1'b0; // Mantém o comportamento original: limiares manuais
        mdp = 2'd0;
        noise_threshold = 8'd30;

        // Limiares levemente relaxados para garantir visibilidade da borda 
        // caso o Gaussiano crie um gradiente muito suave
        high_thresh = 12'd1;
        low_thresh  = 12'd1;
        
        #20 rst_n = 1; 
        
        $display("Iniciando injecao de video (Tamanho: %0dx%0d)...", IMG_WIDTH, IMG_HEIGHT);
        
        // 1. INJETA A IMAGEM REAL
        while (idx < (IMG_WIDTH * IMG_HEIGHT)) begin
            @(posedge clk);
            #1; 
            
            if (ready) begin
                pixel_r_in = image_in[idx][23:16];
                pixel_g_in = image_in[idx][15:8];
                pixel_b_in = image_in[idx][7:0];
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
                pixel_r_in = 8'd0;   // Píxel vazio (preto)
                pixel_g_in = 8'd0;
                pixel_b_in = 8'd0;
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