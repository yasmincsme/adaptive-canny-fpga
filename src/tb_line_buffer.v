//`timescale 1ns / 1ps

module tb_line_buffer;

    // Parâmetros do teste
    parameter WIDTH = 512;
    parameter HEIGHT = 515;
    parameter DATA_WIDTH = 8;
    parameter TOTAL_PIXELS = WIDTH * HEIGHT;

    // Sinais do Testbench
    reg clk;
    reg rst_n;
    reg pixel_vld;
    reg [DATA_WIDTH-1:0] pixel_in;
    wire [DATA_WIDTH-1:0] pixel_out;

    // Memória do Testbench para carregar a imagem do arquivo de texto
    reg [DATA_WIDTH-1:0] imagem_memoria [0:TOTAL_PIXELS-1];
    
    // Integros para controle do laço de repetição
    integer i;

    // Instanciação do Device Under Test (DUT) - O seu Line Buffer
    line_buffer #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(pixel_vld),
        .pixel_in(pixel_in),
        .pixel_out(pixel_out)
    );

    // Geração do Clock (Período de 10ns -> 100 MHz)
    always #5 clk = ~clk;

    // Bloco de Estímulos Principal
    initial begin
        // 1. Inicialização dos sinais
        clk = 0;
        rst_n = 0;
        pixel_vld = 0;
        pixel_in = 0;

        // 2. Carrega o arquivo hexadecimal gerado pelo Python
        $display("[TB] Carregando o arquivo de imagem...");
        $readmemh("imagem_cinza.txt", imagem_memoria);
        $display("[TB] Imagem carregada com sucesso. Total de pixels: %d", TOTAL_PIXELS);

        // 3. Aplica o Reset do sistema
        #20;
        rst_n = 1; // Libera o reset
        #20;

        // 4. Injeta os pixels no Line Buffer, simula o fluxo pixel por pixel
        $display("[TB] Iniciando o envio de pixels para o Line Buffer...");
        
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            @(posedge clk);
            pixel_vld = 1;
            pixel_in  = imagem_memoria[i];
            
            // Log opcional a cada linha processada para monitorar o console do Xcelium
            if (i % WIDTH == 0 && i > 0) begin
                $display("[TB] Linha %d enviada...", i / WIDTH);
            end
        end

        // 5. Finaliza o envio
        @(posedge clk);
        pixel_vld = 0;
        pixel_in = 0;
        
        // Aguarda alguns clocks extras para ver os últimos pixels se deslocando
        #100;
        $display("[TB] Simulação finalizada com sucesso!");
        $finish;
    end

    // 6. Comandos específicos da Cadence para despejar as ondas no SimVision
    initial begin
        $shm_open("waves.shm");      // Cria o banco de dados de ondas
        $shm_probe(tb_line_buffer, "ACMTF"); // Captura todos os sinais, memórias e ports do TB e sub-módulos
    end

endmodule