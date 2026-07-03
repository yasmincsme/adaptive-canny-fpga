`timescale 1ns / 1ps

module tb_image_filter;

    // Parâmetros da imagem de teste (ex: uma imagem pequena de 64x64 para simulação rápida)
    parameter IMG_WIDTH  = 64;
    parameter IMG_HEIGHT = 64;
    parameter TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    reg clk;
    reg rst_n;

    // =========================================================================
    // 1. SINAIS DE INTERCONEXÃO
    // =========================================================================
    // Controle do Line Buffer
    reg  [1:0] kernel_sel;
    reg        pixel_vld;
    reg  [7:0] pixel_in;
    wire       win_vld;
    wire [391:0] window_data;

    // Controle do Datapath
    reg        start;
    wire       done;
    wire [5:0] contador_out;
    reg  [7:0] peso_atual;
    wire [7:0] pixel_suavizado;

    // =========================================================================
    // 2. INSTANCIAÇÃO DOS MÓDULOS
    // =========================================================================
    sliding_window_7x7_flex #(
        .WIDTH(IMG_WIDTH),
        .DATA_WIDTH(8)
    ) line_buffer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .kernel_size(kernel_sel),
        .pixel_vld(pixel_vld),
        .pixel_in(pixel_in),
        .win_vld(win_vld),
        .window_data(window_data)
    );

    gauss_smoothing_datapath datapath_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        //.kernel_sel(kernel_sel),
        .done(done),
        .window_flat(window_data),
        .peso_atual(peso_atual),
        .contador_out(contador_out),
        .pixel_suavizado(pixel_suavizado)
    );

    // =========================================================================
    // 3. ROM DE PESOS SIMULADA (Exemplo para 3x3)
    // =========================================================================
    // A FSM vai contar de 0 a 48, mas para 3x3 só preenchemos os 9 primeiros.
    // O resto retorna 0 para realizar o zero-padding dinâmico.
    always @(*) begin
        case(contador_out)
            // Pesos aproximados (UQ0.8) para um kernel Gaussiano 3x3
            6'd0: peso_atual = 8'd16;
            6'd1: peso_atual = 8'd32;
            6'd2: peso_atual = 8'd16;
            6'd3: peso_atual = 8'd32;
            6'd4: peso_atual = 8'd64; // Centro
            6'd5: peso_atual = 8'd32;
            6'd6: peso_atual = 8'd16;
            6'd7: peso_atual = 8'd32;
            6'd8: peso_atual = 8'd16;
            default: peso_atual = 8'd0; // Bordas inativas
        endcase
    end

    // =========================================================================
    // 4. GERAÇÃO DE CLOCK E MEMÓRIAS DE ARQUIVO
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk; // Clock de 100MHz

    reg [7:0] imagem_entrada [0:TOTAL_PIXELS-1];
    integer   arquivo_saida;
    integer   i;

    // =========================================================================
    // 5. MÁQUINA DE ESTADOS DA TESTBENCH (O Handshake Ping-Pong)
    // =========================================================================
    initial begin
        $dumpfile("onda_imagem.vcd");
        $dumpvars(0, tb_image_filter);

        // Carrega a imagem do arquivo de texto (você precisa criar este arquivo)
        $readmemh("imagem_in.hex", imagem_entrada);
        arquivo_saida = $fopen("imagem_out.hex", "w");

        // Condições Iniciais
        rst_n = 0;
        pixel_vld = 0;
        start = 0;
        pixel_in = 0;
        kernel_sel = 2'b00; // Seleciona 3x3
        
        #20 rst_n = 1; // Libera o reset

        $display("Iniciando processamento da imagem...");

        // Loop principal: percorre todos os píxeis da imagem de entrada
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            
            // 1. Envia um píxel para o Line Buffer
            @(posedge clk);
            pixel_in = imagem_entrada[i];
            pixel_vld = 1;

            // 2. Espera a borda do clock para o Line Buffer processar
            @(posedge clk);
            
            // 3. Se a janela validou, fazemos a pausa (Stall)
            if (win_vld) begin
                pixel_vld = 0; // Pausa o envio de novos píxeis
                start = 1;     // Acorda o datapath Gaussiano

                @(posedge clk);
                start = 0;     // Retira o pulso de start

                // 4. Aguarda pacientemente o datapath terminar (FSM iterando)
                wait (done == 1'b1);
                
                // 5. Na subida do clock após o done, o píxel está pronto no registrador
                @(posedge clk);
                $fdisplay(arquivo_saida, "%h", pixel_suavizado);
            end
        end

        $display("Processamento concluído. Verifique o arquivo imagem_out.hex.");
        $fclose(arquivo_saida);
        $finish;
    end

endmodule