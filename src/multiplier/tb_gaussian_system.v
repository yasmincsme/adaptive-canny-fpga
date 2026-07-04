`timescale 1ns / 1ps

module tb_gaussian_system;

    // =========================================================================
    // Parâmetros do Teste
    // =========================================================================
    parameter WIDTH = 512;       // Ajuste para a largura da sua imagem de teste
    parameter HEIGHT = 512;      // Ajuste para a altura da sua imagem de teste
    parameter CLK_PERIOD = 10;   // 100 MHz

    // =========================================================================
    // Sinais Internos
    // =========================================================================
    reg clk;
    reg rst_n;

    // Sinais da Janela Deslizante
    reg  [1:0] kernel_size = 2'b10; // 10 = 7x7
    reg  pixel_vld;
    reg  [7:0] pixel_in;
    wire win_vld;
    wire [391:0] window_data;

    // Sinais do Datapath Gaussiano
    reg  start;
    wire done;
    wire [5:0] contador_out;
    wire [7:0] pixel_suavizado;

    // ROM de Pesos simulada no Testbench
    reg  [7:0] kernel_rom [0:48];
    wire [7:0] peso_atual;

    assign peso_atual = kernel_rom[contador_out];

    // =========================================================================
    // Instanciação dos Módulos (DUT - Device Under Test)
    // =========================================================================
    
    sliding_window_7x7_flex #(
        .WIDTH(WIDTH),
        .DATA_WIDTH(8)
    ) dut_window (
        .clk(clk),
        .rst_n(rst_n),
        .kernel_size(kernel_size),
        .pixel_vld(pixel_vld),
        .pixel_in(pixel_in),
        .win_vld(win_vld),
        .window_data(window_data)
    );

    gauss_smoothing_datapath dut_gauss (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .window_flat(window_data),
        .peso_atual(peso_atual),
        .contador_out(contador_out),
        .pixel_suavizado(pixel_suavizado)
    );

    // =========================================================================
    // Geração de Clock
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Lógica de Estimulo e I/O de Arquivos
    // =========================================================================
    integer file_in, file_out, status;
    integer r, c;
    integer pixels_processados;

    initial begin
        // 1. Inicializar a ROM com pesos Gaussianos reais (Exemplo simplificado)
        // =========================================================================
        // Inicialização da ROM de Pesos (Kernel Gaussiano 7x7)
        // =========================================================================
        kernel_rom[0]  = 8'd0;  kernel_rom[1]  = 8'd0;  kernel_rom[2]  = 8'd1;  kernel_rom[3]  = 8'd1;  kernel_rom[4]  = 8'd1;  kernel_rom[5]  = 8'd0;  kernel_rom[6]  = 8'd0;
        kernel_rom[7]  = 8'd0;  kernel_rom[8]  = 8'd2;  kernel_rom[9]  = 8'd5;  kernel_rom[10] = 8'd7;  kernel_rom[11] = 8'd5;  kernel_rom[12] = 8'd2;  kernel_rom[13] = 8'd0;
        kernel_rom[14] = 8'd1;  kernel_rom[15] = 8'd5;  kernel_rom[16] = 8'd14; kernel_rom[17] = 8'd20; kernel_rom[18] = 8'd14; kernel_rom[19] = 8'd5;  kernel_rom[20] = 8'd1;
        kernel_rom[21] = 8'd1;  kernel_rom[22] = 8'd7;  kernel_rom[23] = 8'd20; kernel_rom[24] = 8'd32; kernel_rom[25] = 8'd20; kernel_rom[26] = 8'd7;  kernel_rom[27] = 8'd1;
        kernel_rom[28] = 8'd1;  kernel_rom[29] = 8'd5;  kernel_rom[30] = 8'd14; kernel_rom[31] = 8'd20; kernel_rom[32] = 8'd14; kernel_rom[33] = 8'd5;  kernel_rom[34] = 8'd1;
        kernel_rom[35] = 8'd0;  kernel_rom[36] = 8'd2;  kernel_rom[37] = 8'd5;  kernel_rom[38] = 8'd7;  kernel_rom[39] = 8'd5;  kernel_rom[40] = 8'd2;  kernel_rom[41] = 8'd0;
        kernel_rom[42] = 8'd0;  kernel_rom[43] = 8'd0;  kernel_rom[44] = 8'd1;  kernel_rom[45] = 8'd1;  kernel_rom[46] = 8'd1;  kernel_rom[47] = 8'd0;  kernel_rom[48] = 8'd0;

        // 2. Abrir arquivos
        file_in = $fopen("image_in.hex", "r");
        if (file_in == 0) begin
            $display("ERRO: Não foi possível abrir image_in.hex");
            $finish;
        end
        file_out = $fopen("image_out.hex", "w");

        // 3. Reset Inicial
        rst_n = 0;
        pixel_vld = 0;
        start = 0;
        pixel_in = 0;
        pixels_processados = 0;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        $display("Iniciando processamento da imagem...");

        // 4. Varredura da Imagem
        for (r = 0; r < HEIGHT; r = r + 1) begin
            for (c = 0; c < WIDTH; c = c + 1) begin
                
                // Ler pixel do arquivo em formato hexadecimal
                status = $fscanf(file_in, "%h\n", pixel_in);
                if (status != 1) $display("Aviso: Fim de arquivo prematuro em [%0d, %0d]", r, c);

                // Inserir pixel no Line Buffer
                pixel_vld = 1;
                #(CLK_PERIOD);
                pixel_vld = 0; // Desativa até o cálculo terminar

                // Checar se a janela construiu uma vizinhança válida
                if (win_vld) begin
                    // Disparar FSM do Gaussiano
                    start = 1;
                    #(CLK_PERIOD);
                    start = 0;

                    // Aguardar processamento multi-ciclo
                    wait(done == 1'b1);
                    #(CLK_PERIOD); // Sincroniza um ciclo após o done

                    // Escrever resultado no arquivo de saída
                    $fwrite(file_out, "%02x\n", pixel_suavizado);
                    pixels_processados = pixels_processados + 1;
                end
            end
        end

        // 5. Finalização
        $display("Processamento concluído. Pixels válidos gerados: %0d", pixels_processados);
        $fclose(file_in);
        $fclose(file_out);
        $finish;
    end

endmodule