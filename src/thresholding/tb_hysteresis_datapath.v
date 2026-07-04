`timescale 1ns / 1ps

module tb_hysteresis_datapath;

    // Parâmetros do teste
    parameter WIDTH = 8;
    parameter HEIGHT = 8;
    parameter MAG_WIDTH = 12;
    parameter HIGH_THRESH = 100;
    parameter LOW_THRESH = 50;

    // Sinais do DUT
    reg                  clk;
    reg                  rst_n;
    reg  [MAG_WIDTH-1:0] nms_mag_in;
    reg                  nms_vld_in;
    
    wire [7:0]           final_pixel_out;
    wire                 final_vld_out;

    // Instanciação da Unidade Sob Teste (DUT)
    hysteresis_datapath #(
        .IMG_WIDTH(WIDTH),
        .MAG_WIDTH(MAG_WIDTH)
    ) uut (
        .HIGH_THRESH(HIGH_THRESH),
        .LOW_THRESH(LOW_THRESH),
        .clk(clk),
        .rst_n(rst_n),
        .nms_mag_in(nms_mag_in),
        .nms_vld_in(nms_vld_in),
        .final_pixel_out(final_pixel_out),
        .final_vld_out(final_vld_out)
    );

    // Geração de Clock
    always #5 clk = ~clk;

    // Matriz da mini-imagem de entrada (8x8 = 64 píxeis)
    reg [MAG_WIDTH-1:0] image_in [0:(WIDTH*HEIGHT)-1];
    integer i, row, col;

    // =========================================================================
    // RENDERIZADOR DE SAÍDA NO TERMINAL
    // =========================================================================
    // Como a janela é de 3x3, as bordas externas (1 pixel de cada lado) não são 
    // validadas. A imagem de saída terá tamanho (WIDTH-2) x (HEIGHT-2) = 6x6.
    integer valid_count = 0;
    
    always @(posedge clk) begin
        if (final_vld_out) begin
            // Se for 255 (Borda), imprime "##". Se for 0 (Fundo/Ruído), imprime ".."
            if (final_pixel_out == 8'hFF)
                $write("## ");
            else
                $write(".. ");
                
            valid_count = valid_count + 1;
            
            // Quebra de linha automática no terminal para formar a imagem 2D
            if (valid_count % (WIDTH - 2) == 0)
                $display(""); 
        end
    end

    // =========================================================================
    // BLOCO DE ESTÍMULOS
    // =========================================================================
    initial begin
        // 1. INICIALIZAÇÃO DA IMAGEM DE TESTE
        for (i = 0; i < (WIDTH*HEIGHT); i = i + 1) begin
            image_in[i] = 0; // Fundo preto por defeito
        end

        // Desenhar um padrão de teste desafiante:
        // [Linha 2, Coluna 2] -> FORTE (150)
        image_in[2*WIDTH + 2] = 150; 
        
        // Píxeis FRACOS (75) vizinhos imediatos ao FORTE (Devem ser promovidos)
        image_in[2*WIDTH + 3] = 75;  
        image_in[3*WIDTH + 2] = 75;  
        image_in[3*WIDTH + 3] = 75;  
        
        // Píxeis FRACOS (75) um pouco mais afastados (Não tocam no FORTE, devem morrer)
        image_in[2*WIDTH + 4] = 75;  
        image_in[4*WIDTH + 2] = 75;  
        
        // Píxel FRACO isolado (Ruído longe de tudo, deve morrer)
        image_in[6*WIDTH + 6] = 75;  

        // 2. MOSTRAR A IMAGEM DE ENTRADA NO CONSOLE
        $display("=========================================================");
        $display(" IMAGEM DE ENTRADA (Magnitudes Brutas - 8x8)");
        $display("=========================================================");
        for (row = 0; row < HEIGHT; row = row + 1) begin
            for (col = 0; col < WIDTH; col = col + 1) begin
                $write("%3d ", image_in[row*WIDTH + col]);
            end
            $display("");
        end
        $display("\nLegenda Esperada:");
        $display("150 = Borda Forte");
        $display(" 75 = Borda Fraca (Se tocar no 150 vive, senão morre)");
        $display("  0 = Fundo");
        
        $display("\n=========================================================");
        $display(" IMAGEM DE SAIDA PROCESSADA PELA HISTERESE (6x6)");
        $display("=========================================================");
        
        // 3. ESTÍMULOS DE HARDWARE
        clk = 0;
        rst_n = 0;
        nms_mag_in = 0;
        nms_vld_in = 0;
        
        #15 rst_n = 1; // Liberta o reset
        #10;
        
        // Envia a imagem inteira, píxel a píxel, fluxo contínuo (Streaming)
        for (i = 0; i < (WIDTH*HEIGHT); i = i + 1) begin
            @(negedge clk);
            nms_mag_in = image_in[i];
            nms_vld_in = 1'b1;
        end
        
        // Pára o fluxo de dados
        @(negedge clk);
        nms_mag_in = 0;
        nms_vld_in = 0;
        
        // Aguarda os ciclos necessários para os Line Buffers esvaziarem (Latência)
        #100;
        
        $display("=========================================================");
        $display("SIMULACAO CONCLUIDA.");
        $finish;
    end

endmodule