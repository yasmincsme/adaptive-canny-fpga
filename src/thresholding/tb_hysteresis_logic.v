`timescale 1ns / 1ps

module tb_hysteresis_logic;

    // Constantes para legibilidade do código
    localparam STR = 2'b11; // Forte (Strong)
    localparam WEA = 2'b01; // Fraco (Weak)
    localparam BKG = 2'b00; // Fundo (Background)

    // Sinais de Entrada (Registradores)
    reg [1:0] w00, w01, w02;
    reg [1:0] w10, w11, w12;
    reg [1:0] w20, w21, w22;
    reg       vld_in;

    // Sinais de Saída (Fios)
    wire [7:0] edge_out;
    wire       vld_out;

    // Contadores de estatísticas
    integer pass_count;
    integer fail_count;

    // Instanciação da Unidade Sob Teste (DUT)
    hysteresis_logic uut (
        .win00(w00), .win01(w01), .win02(w02),
        .win10(w10), .win11(w11), .win12(w12),
        .win20(w20), .win21(w21), .win22(w22),
        .win_vld_in(vld_in),
        .edge_pixel_out(edge_out),
        .pixel_vld_out(vld_out)
    );

    // =========================================================================
    // TASK DE VERIFICAÇÃO AUTOMÁTICA
    // =========================================================================
    task check_expected;
        // Entradas da matriz 3x3
        input [1:0] i00, i01, i02;
        input [1:0] i10, i11, i12;
        input [1:0] i20, i21, i22;
        input       i_vld;
        // Resultados esperados
        input [7:0] exp_edge;
        input       exp_vld;
        input [80*8:1] test_name; // String para nome do teste
        begin
            // 1. Aplica estímulos
            w00 = i00; w01 = i01; w02 = i02;
            w10 = i10; w11 = i11; w12 = i12;
            w20 = i20; w21 = i21; w22 = i22;
            vld_in = i_vld;
            
            // 2. Aguarda propagação combinacional
            #10;
            
            // 3. Verifica e contabiliza
            if ((edge_out === exp_edge) && (vld_out === exp_vld)) begin
                pass_count = pass_count + 1;
                $display("[PASS] %s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %s", test_name);
                $display("       Esperado: Edge=%h, Vld=%b", exp_edge, exp_vld);
                $display("       Obtido  : Edge=%h, Vld=%b", edge_out, vld_out);
            end
        end
    endtask

    // =========================================================================
    // BLOCO DE ESTÍMULOS (TESTES DIRECIONADOS)
    // =========================================================================
    initial begin
        // Inicialização
        pass_count = 0;
        fail_count = 0;
        
        $display("=========================================================");
        $display("INICIANDO VALIDACAO DA LOGICA DE HISTERESE");
        $display("=========================================================");

        // TESTE 1: Centro Forte (Deve sempre virar FF, ignorando vizinhos)
        check_expected(
            BKG, BKG, BKG,
            BKG, STR, BKG, // Centro = STR
            BKG, BKG, BKG,
            1'b1, 8'hFF, 1'b1, "Centro FORTE isolado (Saida 255)"
        );

        // TESTE 2: Centro Fundo (Deve sempre virar 00, ignorando vizinhos)
        check_expected(
            STR, STR, STR,
            STR, BKG, STR, // Centro = BKG, Vizinhos = Todos Fortes
            STR, STR, STR,
            1'b1, 8'h00, 1'b1, "Centro FUNDO com vizinhos fortes (Saida 0)"
        );

        // TESTE 3: Centro Fraco Isolado (Deve virar 00)
        check_expected(
            WEA, BKG, WEA,
            BKG, WEA, BKG, // Centro = WEA, nenhum forte ao redor
            WEA, BKG, WEA,
            1'b1, 8'h00, 1'b1, "Centro FRACO isolado/sem forte (Saida 0)"
        );

        // TESTES 4 a 11: Centro Fraco conectado (Testando as 8 posições do OR)
        // O centro é fraco e colocamos apenas UM vizinho forte por vez. 
        // Todas estas saídas devem ser promovidas para FF.
        
        check_expected(STR,BKG,BKG, BKG,WEA,BKG, BKG,BKG,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Canto Sup Esq");
        check_expected(BKG,STR,BKG, BKG,WEA,BKG, BKG,BKG,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Topo Centro");
        check_expected(BKG,BKG,STR, BKG,WEA,BKG, BKG,BKG,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Canto Sup Dir");
        
        check_expected(BKG,BKG,BKG, STR,WEA,BKG, BKG,BKG,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Esquerda");
        check_expected(BKG,BKG,BKG, BKG,WEA,STR, BKG,BKG,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Direita");
        
        check_expected(BKG,BKG,BKG, BKG,WEA,BKG, STR,BKG,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Canto Inf Esq");
        check_expected(BKG,BKG,BKG, BKG,WEA,BKG, BKG,STR,BKG, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Base Centro");
        check_expected(BKG,BKG,BKG, BKG,WEA,BKG, BKG,BKG,STR, 1'b1, 8'hFF, 1'b1, "Centro FRACO ligado Canto Inf Dir");

        // TESTE 12: Sinal Valid
        check_expected(
            BKG, BKG, BKG,
            BKG, STR, BKG,
            BKG, BKG, BKG,
            1'b0, 8'hFF, 1'b0, "Teste do Handshake (Vld = 0)" // Saída lógica continua FF, mas Vld é 0
        );

        // =========================================================================
        // RELATÓRIO FINAL
        // =========================================================================
        $display("=========================================================");
        $display("RELATORIO FINAL DE VERIFICACAO:");
        $display("Sucessos (PASS) : %0d", pass_count);
        $display("Falhas   (FAIL) : %0d", fail_count);
        $display("=========================================================");
        
        if (fail_count == 0)
            $display(">>> TESTE CONCLUIDO COM SUCESSO! LOGICA DE HISTERESE VALIDADA. <<<");
        else
            $display(">>> ERROS DETECTADOS! <<<");
            
        $finish;
    end

endmodule