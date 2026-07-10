`timescale 1ns / 1ps

module tb_system_rgb2gray();

    // ==========================================
    // Parâmetros de Temporização e Geometria
    // ==========================================
    parameter SYS_CLK_PERIOD      = 10;  // 100 MHz (10ns)
    parameter SPI_CLK_HALF_PERIOD = 50;  // 10 MHz SPI Clock (100ns período)
    
    parameter IMG_WIDTH  = 512;
    parameter IMG_HEIGHT = 512;
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 262.144
    parameter NUM_BYTES  = NUM_PIXELS * 3;         // 786.432 bytes (R,G,B por pixel)

    // ==========================================
    // Sinais do Sistema
    // ==========================================
    reg clk_sys;
    reg rst_n;
    
    // Configurações SPI
    reg cpol;
    reg cpha;
    reg dord;
    
    // Sinais Físicos SPI
    reg  sclk_in;
    reg  cs_n_in;
    reg  mosi_in;
    wire miso_out;
    
    // Controle
    reg  start;
    wire pixel_vld;
    
    // Leitura da RAM
    reg  [17:0] read_addr_b;
    wire [7:0]  read_data_b;

    // Arrays de Memória para File I/O
    reg [7:0] image_in_array [0:NUM_BYTES-1];
    integer file_out;
    integer i;

    // ==========================================
    // Instância do Top Module (Device Under Test)
    // ==========================================
    system_rgb2gray_top DUT (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .cpol(cpol),
        .cpha(cpha),
        .dord(dord),
        .sclk_in(sclk_in),
        .cs_n_in(cs_n_in),
        .mosi_in(mosi_in),
        .miso_out(miso_out),
        .start(start),
        .pixel_vld(pixel_vld),
        .read_addr_b(read_addr_b),
        .read_data_b(read_data_b)
    );

    // ==========================================
    // Geração de Clock (100 MHz)
    // ==========================================
    initial begin
        clk_sys = 0;
        forever #(SYS_CLK_PERIOD/2) clk_sys = ~clk_sys;
    end

    // ==========================================
    // Task: Emulador de SPI Master (Modo 0: CPOL=0, CPHA=0)
    // ==========================================
    task spi_send_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            cs_n_in = 0; // Ativa o Slave
            #(SPI_CLK_HALF_PERIOD); // Setup time do CS
            
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                // Define o dado no MOSI (MSB First, pois dord=0)
                mosi_in = data[bit_idx];
                #(SPI_CLK_HALF_PERIOD);
                
                // Borda de subida (Slave amostra)
                sclk_in = 1;
                #(SPI_CLK_HALF_PERIOD);
                
                // Borda de descida (Mestre atualiza próximo bit, se houvesse)
                sclk_in = 0;
            end
            
            #(SPI_CLK_HALF_PERIOD);
            cs_n_in = 1; // Desativa o Slave
            #(SPI_CLK_HALF_PERIOD * 4); // Pequeno atraso entre envios de bytes
        end
    endtask

    // ==========================================
    // Bloco de Estímulo Principal
    // ==========================================
    initial begin
        // 1. Inicialização de Sinais
        rst_n       = 0;
        cpol        = 0;
        cpha        = 0;
        dord        = 0; // 0 = MSB first
        sclk_in     = 0;
        cs_n_in     = 1;
        mosi_in     = 0;
        start       = 0;
        read_addr_b = 0;

        // 2. Carrega a imagem de entrada (Hex)
        // O arquivo deve conter 1 byte por linha (ex: FF \n A2 \n ...)
        $readmemh("imagem_in.hex", image_in_array);
        
        // Abre o arquivo de saída
        file_out = $fopen("imagem_out.hex", "w");
        if (file_out == 0) begin
            $display("ERRO: Não foi possível criar imagem_out.hex");
            $finish;
        end

        // 3. Aplica Reset
        #(SYS_CLK_PERIOD * 10);
        rst_n = 1;
        #(SYS_CLK_PERIOD * 10);

        // 4. Inicia o Frame
        $display("Iniciando transmissao SPI da imagem...");
        start = 1;
        #(SYS_CLK_PERIOD * 2);
        start = 0;

        // 5. Envia toda a imagem via SPI (R, G, B em sequência)
        for (i = 0; i < NUM_BYTES; i = i + 1) begin
            spi_send_byte(image_in_array[i]);
            
            // Monitoramento de progresso (a cada 10 mil bytes) para não parecer travado
            if (i % 10000 == 0) $display("Enviados %0d bytes...", i);
        end
        
        $display("Transmissao SPI concluida. Aguardando estabilizacao...");
        #(SYS_CLK_PERIOD * 100);

        // 6. Extração dos Dados da RAM (Porta B) para Arquivo
        $display("Lendo RAM e salvando no arquivo...");
        for (i = 0; i < NUM_PIXELS; i = i + 1) begin
            read_addr_b = i;
            
            // Aguarda 2 ciclos para a RAM Dual Port atualizar a saída
            #(SYS_CLK_PERIOD * 2); 
            
            // Escreve no arquivo hexadecimal
            $fdisplay(file_out, "%02h", read_data_b);
        end

        $display("Escrita concluida com sucesso. Encerrando simulacao.");
        $fclose(file_out);
        $finish;
    end

endmodule