`timescale 1ns / 1ps

// Dimensões da imagem de entrada (IMG_WIDTH/IMG_HEIGHT), geradas em
// build/image_params.vh por scripts/png_to_hex.py a partir de uma imagem
// real. Compile com -I build (ver config.txt). Se este arquivo não
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
    // SIMULAÇÃO DA ROM DE PESOS -- KERNEL GAUSSIANO REAL 7x7 (sigma=1.3)
    // =========================================================================
    // ATENÇÃO: até esta correção, esta ROM era um passa-direto de 1 peso só
    // (identity, sem suavização real) -- funcionava sem chamar atenção em
    // imagens sintéticas/recortes suaves, mas em fotos reais com textura fina
    // (cabelo, penas, treliça de fundo) o Sobel via ruído de alta frequência
    // sem filtragem nenhuma, produzindo uma borda muito mais "suja" do que um
    // Canny de referência com blur real no mesmo limiar.
    //
    // Kernel calculado com sigma=1.3 (mesmo valor que a tabela adaptativa
    // seleciona via kernel_sel=2 para noise_level=0), normalizado para somar
    // 255 (peso/256 == fração Q0.8 usada pelo MAC do gauss_smoothing_datapath):
    reg [7:0] rom_pesos [0:63];
    integer r;
    initial begin
        for (r = 0; r < 64; r = r + 1) begin
            rom_pesos[r] = 8'd0;
        end
        rom_pesos[0]=0;  rom_pesos[1]=1;  rom_pesos[2]=1;  rom_pesos[3]=2;  rom_pesos[4]=1;  rom_pesos[5]=1;  rom_pesos[6]=0;
        rom_pesos[7]=1;  rom_pesos[8]=2;  rom_pesos[9]=6;  rom_pesos[10]=7; rom_pesos[11]=6; rom_pesos[12]=2; rom_pesos[13]=1;
        rom_pesos[14]=1; rom_pesos[15]=6; rom_pesos[16]=13;rom_pesos[17]=18;rom_pesos[18]=13;rom_pesos[19]=6; rom_pesos[20]=1;
        rom_pesos[21]=2; rom_pesos[22]=7; rom_pesos[23]=18;rom_pesos[24]=23;rom_pesos[25]=18;rom_pesos[26]=7; rom_pesos[27]=2;
        rom_pesos[28]=1; rom_pesos[29]=6; rom_pesos[30]=13;rom_pesos[31]=18;rom_pesos[32]=13;rom_pesos[33]=6; rom_pesos[34]=1;
        rom_pesos[35]=1; rom_pesos[36]=2; rom_pesos[37]=6; rom_pesos[38]=7; rom_pesos[39]=6; rom_pesos[40]=2; rom_pesos[41]=1;
        rom_pesos[42]=0; rom_pesos[43]=1; rom_pesos[44]=1; rom_pesos[45]=2; rom_pesos[46]=1; rom_pesos[47]=1; rom_pesos[48]=0;
    end

    assign gauss_peso = rom_pesos[gauss_addr];

    // =========================================================================
    // CARGA DA IMAGEM DE ENTRADA (build/entrada_canny.hex)
    // =========================================================================
    // Gerado por scripts/png_to_hex.py a partir de uma imagem real (PNG colorido),
    // ou o quadrado sintético 512x512 padrão se o script ainda não foi executado.
    // Cada linha do .hex é um pixel RGB de 24 bits: {R[7:0], G[7:0], B[7:0]}.
    // A conversão para escala de cinza acontece dentro do datapath (rgb_gray_average).
    // Caminho relativo ao diretório de onde a simulação é invocada (raiz do
    // projeto -- ver config.txt).
    reg [23:0] image_in [0:(IMG_WIDTH*IMG_HEIGHT)-1];

    initial begin
        $readmemh("build/entrada_canny.hex", image_in);
        $display("Imagem 'build/entrada_canny.hex' carregada (%0dx%0d, RGB).", IMG_WIDTH, IMG_HEIGHT);
    end

    // Geração de Clock
    always #5 clk = ~clk;

    // =========================================================================
    // EXPORTAÇÃO PARA ARQUIVO .HEX E MONITOR VISUAL
    // =========================================================================
    integer file_out;
    integer valid_count = 0;

    initial begin
        file_out = $fopen("build/saida_canny.hex", "w");
        if (!file_out) begin
            $display("ERRO: Nao foi possivel criar o arquivo build/saida_canny.hex");
            $finish;
        end
        $display("Arquivo 'build/saida_canny.hex' aberto para gravacao.");
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
        // Usa a tabela de parâmetros pré-calculada (config_table) em vez de
        // limiares manuais: HIGH_THRESH/LOW_THRESH abaixo só valem se
        // adaptive_en for desligado.
        adaptive_en = 1'b1;
        mdp = 2'd3; // 94% -- ponto de operação mais conservador da tabela
        // 30 era sensivel demais: textura real de foto (cabelo, penas, treliça
        // de fundo) era confundida com ruido, fazendo noise_level oscilar
        // janela a janela e o limiar ficar inconsistente pela imagem (validado
        // com um histograma de noise_level ao longo da lena.png completa: com
        // 30, ~6% das janelas relatavam noise_level>0 mesmo sem ruido real;
        // com 60, 100% ficam em noise_level=0, inclusive no trecho mais
        // texturizado da imagem -- a pena do chapeu).
        noise_threshold = 8'd60;

        // Só usados quando adaptive_en=1'b0.
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
        $display("Arquivo gerado: build/saida_canny.hex");
        $finish;
    end

endmodule