//`timescale 1ns / 1ps

module tb_window_3x3;

    // Parâmetros da imagem (512 colunas x 515 linhas)
    parameter WIDTH        = 512;
    parameter HEIGHT       = 515;
    parameter DATA_WIDTH   = 8;
    parameter TOTAL_PIXELS = WIDTH * HEIGHT;

    // Sinais de estímulo (Entradas do DUT)
    reg                   clk;
    reg                   rst_n;
    reg                   pixel_vld;
    reg  [DATA_WIDTH-1:0] pixel_in;

    // Sinais de monitoramento (Saídas do DUT)
    wire [DATA_WIDTH-1:0] win00, win01, win02;
    wire [DATA_WIDTH-1:0] win10, win11, win12;
    wire [DATA_WIDTH-1:0] win20, win21, win22;
    wire                  win_vld;

    // Memória do Testbench para armazenar a imagem do arquivo TXT
    reg  [DATA_WIDTH-1:0] imagem_memoria [0:TOTAL_PIXELS-1];
    
    // Variável de controle para o laço de repetição
    integer i;

    // Instanciação do Módulo de Vizinhança (Device Under Test - DUT)
    sliding_window_3x3 #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut_window (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(pixel_vld),
        .pixel_in(pixel_in),
        .win00(win00), .win01(win01), .win02(win02),
        .win10(win10), .win11(win11), .win12(win12),
        .win20(win20), .win21(win21), .win22(win22),
        .win_vld(win_vld)
    );

    // Geração do Clock de 100 MHz (Período de 10ns)
    always #5 clk = ~clk;

    // Bloco de Estímulo Principal
    initial begin
        // 1. Inicialização dos Sinais
        clk       = 0;
        rst_n     = 0;
        pixel_vld = 0;
        pixel_in  = 0;

        // 2. Carrega a imagem gerada pelo script Python
        $display("[TB_WINDOW] Carregando o arquivo 'imagem_cinza.txt'...");
        $readmemh("imagem_cinza.txt", imagem_memoria);
        $display("[TB_WINDOW] Imagem carregada. Total de pixels: %d", TOTAL_PIXELS);

        // 3. Aplica e libera o Reset do sistema
        #20;
        rst_n = 1; 
        #20;

        // 4. Injeção de Pixels sequenciais da imagem
        $display("[TB_WINDOW] Iniciando a transmissão do stream de pixels...");
        
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            @(posedge clk);
            pixel_vld = 1;
            pixel_in  = imagem_memoria[i];
            
            // Monitoramento básico via console quando a janela se torna válida
            if (win_vld && (i % WIDTH == 0)) begin
                $display("[TB_WINDOW] Processando Linha %d...", i / WIDTH);
            end
        end

        // 5. Finalização do Stream
        @(posedge clk);
        pixel_vld = 0;
        pixel_in  = 0;
        
        // Mantém a simulação rodando por mais alguns ciclos para estabilização visual
        #200;
        $display("[TB_WINDOW] Simulação finalizada com sucesso!");
        $finish;
    end

    // =========================================================================
    // COMANDOS CADENCE (XCELIUM / SIMVISION)
    // =========================================================================
    // Cria o banco de dados de formas de onda (.shm) contendo todas as variáveis
    initial begin
        $shm_open("waves_window.shm");
        // O parâmetro "ACMTF" grava Ports, Sinais Internos e Memórias de todo o escopo
        $shm_probe(tb_window_3x3, "ACMTF");
    end

endmodule