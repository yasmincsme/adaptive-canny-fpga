`timescale 1ns / 1ps

module tb_nms_combinational;

    // Parâmetros
    parameter WIDTH = 12;

    // Entradas do Módulo (Registradores para o TB)
    reg clk;
    reg [WIDTH-1:0] m00, m01, m02;
    reg [WIDTH-1:0] m10, m11, m12;
    reg [WIDTH-1:0] m20, m21, m22;
    reg [1:0]       dir;
    reg             valid_in;

    // Saídas do Módulo (Fios)
    wire [WIDTH-1:0] nms_mag_out;
    wire             nms_vld_out;

    // Instanciação da Unidade Sob Teste (UUT)
    nms_combinational #(
        .WIDTH(WIDTH)
    ) uut (
        .mag00(m00), .mag01(m01), .mag02(m02),
        .mag10(m10), .mag11(m11), .mag12(m12),
        .mag20(m20), .mag21(m21), .mag22(m22),
        .dir_center(dir),
        .win_vld_in(valid_in),
        .nms_mag_out(nms_mag_out),
        .nms_vld_out(nms_vld_out)
    );

    // Gerador de Clock (Apenas para sequenciar os testes, o módulo é combinacional)
    always #5 clk = ~clk;

    // =========================================================================
    // TASK PARA APLICAÇÃO DE JANELAS DE TESTE
    // =========================================================================
    task apply_test;
        input [WIDTH-1:0] v00, v01, v02;
        input [WIDTH-1:0] v10, v11, v12;
        input [WIDTH-1:0] v20, v21, v22;
        input [1:0]       v_dir;
        input             v_valid;
        input [80*8:1]    test_name;
        begin
            @(negedge clk); // Aplica na borda de descida
            m00 = v00; m01 = v01; m02 = v02;
            m10 = v10; m11 = v11; m12 = v12;
            m20 = v20; m21 = v21; m22 = v22;
            dir = v_dir;
            valid_in = v_valid;
            
            @(posedge clk); // Espera a borda de subida
            #1; // Pequeno atraso para garantir estabilidade combinacional
            
            $display("--- TESTE: %s ---", test_name);
            $display("[%3d] [%3d] [%3d]", m00, m01, m02);
            $display("[%3d] [%3d] [%3d]  --> Dir( %b ) | NMS_OUT = %3d | VLD = %b", 
                     m10, m11, m12, dir, nms_mag_out, nms_vld_out);
            $display("[%3d] [%3d] [%3d]", m20, m21, m22);
            $display("---------------------------------------------------------");
        end
    endtask

    // =========================================================================
    // BLOCO DE ESTÍMULOS
    // =========================================================================
    initial begin
        // Inicialização
        clk = 0;
        m00=0; m01=0; m02=0; m10=0; m11=0; m12=0; m20=0; m21=0; m22=0;
        dir = 0;
        valid_in = 0;
        
        $display("\nINICIANDO VALIDACAO DO NMS COMBINACIONAL...\n");
        #15;

        // ---------------------------------------------------------------------
        // TESTE 1: Borda Horizontal (Direção 00 - Esquerda/Direita)
        // Centro (100) é maior que vizinhos (50 e 20). Esperado: SOBREVIVE (100)
        apply_test(
              0,   0,   0,
             50, 100,  20,
              0,   0,   0,
             2'b00, 1'b1, "DIRECAO 00: Pico Perfeito (Sobrevive)"
        );

        // ---------------------------------------------------------------------
        // TESTE 2: Borda Horizontal (Direção 00 - Esquerda/Direita)
        // Centro (80) é menor que vizinho da direita (150). Esperado: SUPRIMIDO (0)
        apply_test(
              0,   0,   0,
             50,  80, 150,
              0,   0,   0,
             2'b00, 1'b1, "DIRECAO 00: Encosta de Borda (Suprimido)"
        );

        // ---------------------------------------------------------------------
        // TESTE 3: Borda Vertical (Direção 10 - Cima/Baixo)
        // Teste de PLANALTO. Centro (90) é IGUAL ao vizinho de cima (90).
        // A lógica é (Centro >= Cima) && (Centro > Baixo). 
        // 90 >= 90 (V) e 90 > 40 (V). Esperado: SOBREVIVE (90)
        apply_test(
              0,  90,   0,
              0,  90,   0,
              0,  40,   0,
             2'b10, 1'b1, "DIRECAO 10: Planalto Cima (Sobrevive)"
        );

        // ---------------------------------------------------------------------
        // TESTE 4: Borda Vertical (Direção 10 - Cima/Baixo)
        // Teste de PLANALTO invertido. Centro (90) é IGUAL ao vizinho de baixo (90).
        // A lógica é (Centro >= Cima) && (Centro > Baixo). 
        // 90 >= 40 (V) e 90 > 90 (FALSO!). Esperado: SUPRIMIDO (0)
        apply_test(
              0,  40,   0,
              0,  90,   0,
              0,  90,   0,
             2'b10, 1'b1, "DIRECAO 10: Planalto Baixo (Suprimido)"
        );

        // ---------------------------------------------------------------------
        // TESTE 5: Diagonal Ascendente (Direção 01 - Canto Inf.Esq / Sup.Dir)
        // Centro é o máximo na diagonal /. Esperado: SOBREVIVE (120)
        apply_test(
              0,   0,  60,
              0, 120,   0,
             30,   0,   0,
             2'b01, 1'b1, "DIRECAO 01: Pico Diagonal (Sobrevive)"
        );

        // ---------------------------------------------------------------------
        // TESTE 6: Diagonal Descendente (Direção 11 - Canto Sup.Esq / Inf.Dir)
        // Centro é menor que o Sup.Esq na diagonal \. Esperado: SUPRIMIDO (0)
        apply_test(
            200,   0,   0,
              0,  50,   0,
              0,   0,  20,
             2'b11, 1'b1, "DIRECAO 11: Encosta Diagonal (Suprimido)"
        );

        // ---------------------------------------------------------------------
        // TESTE 7: Teste do Sinal Valid (Handshake)
        // Pico perfeito, mas valid_in está em 0. NMS calcula, mas valid_out = 0.
        apply_test(
              0,   0,   0,
             10, 255,  10,
              0,   0,   0,
             2'b00, 1'b0, "HANDSHAKE: Entrada Invalida (VLD_OUT = 0)"
        );

        #20;
        $display("\nSIMULACAO CONCLUIDA.");
        $finish;
    end

endmodule