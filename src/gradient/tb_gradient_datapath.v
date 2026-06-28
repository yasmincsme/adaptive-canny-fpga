`timescale 1ns / 1ps

module tb_gradient_datapath;

    // Entradas
    reg clk;
    reg reset;
    reg window_valid_in;
    reg [7:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;

    // Saídas
    wire pixel_valid_out;
    wire [11:0] magnitude;
    wire [1:0] direction;

    // Instanciação do Datapath
    gradient_datapath uut (
        .clk(clk),
        .reset(reset),
        .window_valid_in(window_valid_in),
        .pixel_valid_out(pixel_valid_out),
        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),
        .magnitude(magnitude),
        .direction(direction)
    );

    // Geração de Clock (Período de 10ns -> 100 MHz)
    always #5 clk = ~clk;

    // Tarefa para aplicar uma janela 3x3 e esperar o processamento
    task apply_window;
        input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
        input [8*20:1] test_name; // String para nomear o teste no console
        begin
            @(negedge clk); // Aplica na borda de descida para evitar race conditions
            p0 = v0; p1 = v1; p2 = v2;
            p3 = v3; p4 = v4; p5 = v5;
            p6 = v6; p7 = v7; p8 = v8;
            window_valid_in = 1'b1;
            
            // Aguarda 2 ciclos para o pipeline encher
            @(posedge clk);
            @(posedge clk);
            
            // Lê o resultado pouco antes da próxima borda
            #1; 
            if (pixel_valid_out) begin
                $display("[%s] Mag: %d | Dir: %b", test_name, magnitude, direction);
            end else begin
                $display("[%s] ERRO: pixel_valid_out não subiu após 2 ciclos!", test_name);
            end
            
            // Zera a entrada para o próximo teste
            @(negedge clk);
            window_valid_in = 1'b0;
            p0=0; p1=0; p2=0; p3=0; p4=0; p5=0; p6=0; p7=0; p8=0;
            @(posedge clk);
        end
    endtask

    // Bloco de Estímulos
    initial begin
        // Inicialização
        $display("Iniciando Simulação...");
        clk = 0;
        reset = 1;
        window_valid_in = 0;
        p0=0; p1=0; p2=0; p3=0; p4=0; p5=0; p6=0; p7=0; p8=0;

        // Reset do sistema
        #20;
        reset = 0;
        #10;

        // ---------------------------------------------------------------------
        // TESTE 1: Borda Vertical (Esquerda escura, Direita clara)
        // Sobel X será alto, Sobel Y será zero. Direção esperada: 2'b00 (0 graus)
        // ---------------------------------------------------------------------
        apply_window(
            50,  50, 200,
            50,  50, 200,
            50,  50, 200,
            "Borda Vertical     "
        );

        // ---------------------------------------------------------------------
        // TESTE 2: Borda Horizontal (Topo escuro, Fundo claro)
        // Sobel X será zero, Sobel Y será alto. Direção esperada: 2'b10 (90 graus)
        // ---------------------------------------------------------------------
        apply_window(
            50,  50,  50,
            50,  50,  50,
            200, 200, 200,
            "Borda Horizontal   "
        );

        // ---------------------------------------------------------------------
        // TESTE 3: Região Homogênea (Fundo sólido)
        // Gradientes zerados. Magnitude esperada: 0.
        // ---------------------------------------------------------------------
        apply_window(
            100, 100, 100,
            100, 100, 100,
            100, 100, 100,
            "Regiao Homogenea   "
        );

        // ---------------------------------------------------------------------
        // TESTE 4: Borda Diagonal (Canto sup. esquerdo escuro, inf. direito claro)
        // Sobel X e Y terão sinais iguais. Direção esperada: 2'b01 (45 graus)
        // ---------------------------------------------------------------------
        apply_window(
             10,  10, 200,
             10, 200, 200,
            200, 200, 200,
            "Borda Diagonal 45  "
        );

        // ---------------------------------------------------------------------
        // TESTE 5: Borda Diagonal (Canto sup. direito escuro, inf. esquerdo claro)
        // Sobel X e Y terão sinais diferentes. Direção esperada: 2'b11 (135 graus)
        // ---------------------------------------------------------------------
        apply_window(
            200,  10,  10,
            200, 200,  10,
            200, 200, 200,
            "Borda Diagonal 135 "
        );

        #50;
        $display("Simulação Concluída.");
        $finish;
    end

endmodule