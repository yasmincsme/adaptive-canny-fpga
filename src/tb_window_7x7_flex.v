`timescale 1ns / 1ps

module tb_window_7x7_flex;

    // Parâmetros da imagem (512 colunas x 515 linhas)
    parameter WIDTH        = 512;
    parameter HEIGHT       = 515;
    parameter DATA_WIDTH   = 8;
    parameter TOTAL_PIXELS = WIDTH * HEIGHT;

    // Sinais de estímulo (Entradas do DUT)
    reg                    clk;
    reg                    rst_n;
    reg  [1:0]             kernel_size; // 00=3x3, 01=5x5, 10=7x7
    reg                    pixel_vld;
    reg  [DATA_WIDTH-1:0]  pixel_in;

    // Sinais de monitoramento (Saídas do DUT)
    wire                   win_vld;
    wire [(49*DATA_WIDTH)-1:0] window_data; // Barramento completo de 392 bits

    // Matriz virtual interna do Testbench para facilitar a leitura das ondas
    wire [DATA_WIDTH-1:0] win_monitor [0:6][0:6];

    // Memória do Testbench para carregar o arquivo TXT
    reg  [DATA_WIDTH-1:0] imagem_memoria [0:TOTAL_PIXELS-1];
    integer i;

    // =========================================================================
    // INSTANCIAÇÃO DO NOVO DUT FLEXÍVEL
    // =========================================================================
    sliding_window_7x7_flex #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut_flex (
        .clk         (clk),
        .rst_n       (rst_n),
        .kernel_size (kernel_size),
        .pixel_vld   (pixel_vld),
        .pixel_in    (pixel_in),
        .win_vld     (win_vld),
        .window_data (window_data)
    );

    // =========================================================================
    // DESEMPACOTAMENTO CONCEITUAL PARA O SIMVISION
    // =========================================================================
    // Reconecta os pedaços do barramento de 392 bits na matriz win_monitor
    genvar r, c;
    generate
        for (r = 0; r < 7; r = r + 1) begin : CONV_ROW
            for (c = 0; c < 7; c = c + 1) begin : CONV_COL
                assign win_monitor[r][c] = window_data[((r*7+c)*DATA_WIDTH) +: DATA_WIDTH];
            end
        end
    endgenerate

    // Geração do Clock (100 MHz)
    always #5 clk = ~clk;

    // Bloco de Estímulo Principal
    initial begin
        // 1. Inicialização dos Sinais
        clk         = 0;
        rst_n       = 0;
        pixel_vld   = 0;
        pixel_in    = 0;
        
        // >>> CONFIGURAÇÃO DO TESTE: Mude aqui para testar os tamanhos! <<<
        // 2'b00 = Modo 3x3 | 2'b01 = Modo 5x5 | 2'b10 = Modo 7x7
        kernel_size = 2'b00; 

        // 2. Carrega a imagem hexadecimal
        $display("[TB_FLEX] Carregando o arquivo 'imagem_cinza.txt'...");
        $readmemh("imagem_cinza.txt", imagem_memoria);
        $display("[TB_FLEX] Imagem carregada com sucesso.");

        // 3. Aplica e libera o Reset do sistema
        #20;
        rst_n = 1; 
        #20;

        // 4. Injeção de Pixels sequenciais
        $display("[TB_FLEX] Transmitindo pixels no modo kernel_size = %b...", kernel_size);
        
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            @(posedge clk);
            pixel_vld = 1;
            pixel_in  = imagem_memoria[i];
            
            if (win_vld && (i % WIDTH == 0)) begin
                $display("[TB_FLEX] Processando Linha %d...", i / WIDTH);
            end
        end

        // 5. Finalização do Stream
        @(posedge clk);
        pixel_vld = 0;
        pixel_in  = 0;
        
        #200;
        $display("[TB_FLEX] Teste finalizado!");
        $finish;
    end

    // Configuração do dump de ondas para a Cadence
    initial begin
        $shm_open("waves_flex.shm");
        $shm_probe(tb_window_7x7_flex, "ACMTF");
    end

endmodule