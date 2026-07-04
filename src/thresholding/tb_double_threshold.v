`timescale 1ns / 1ps

module tb_double_threshold;

    // Parâmetros do teste (Espelhando o DUT)
    parameter WIDTH = 12;
    parameter HIGH = 100;
    parameter LOW = 50;

    // Sinais do DUT
    reg [WIDTH-1:0] nms_mag_in;
    reg             nms_vld_in;
    wire [1:0]      edge_type_out;
    wire            vld_out;

    // Contadores de estatísticas de Verificação
    integer pass_count;
    integer fail_count;
    integer i;

    // Instanciação do Módulo (DUT)
    double_threshold #(
        .WIDTH(WIDTH)
    ) uut (
        .HIGH_THRESH(HIGH),
        .LOW_THRESH(LOW),
        .nms_mag_in(nms_mag_in),
        .nms_vld_in(nms_vld_in),
        .edge_type_out(edge_type_out),
        .vld_out(vld_out)
    );

    // =========================================================================
    // TASK DE VERIFICAÇÃO AUTOMÁTICA
    // =========================================================================
    // A task aplica os estímulos, aguarda a propagação lógica e compara 
    // a saída real do módulo com a saída teórica esperada.
    task check_expected;
        input [WIDTH-1:0] test_mag;
        input             test_vld_in;
        input [1:0]       exp_edge;
        input             exp_vld_out;
        begin
            // 1. Aplica os estímulos na entrada do DUT
            nms_mag_in = test_mag;
            nms_vld_in = test_vld_in;
            
            // 2. Aguarda um tempo para a propagação das portas lógicas combinacionais
            #5; 
            
            // 3. Verifica os resultados
            if ((edge_type_out === exp_edge) && (vld_out === exp_vld_out)) begin
                pass_count = pass_count + 1; // Sucesso
            end else begin
                fail_count = fail_count + 1; // Falha
                // Imprime os detalhes apenas das falhas para facilitar o debug
                $display("[FALHA] Mag: %0d | Vld_in: %b | Obtido: Edge=%b, Vld=%b | Esperado: Edge=%b, Vld=%b", 
                          test_mag, test_vld_in, edge_type_out, vld_out, exp_edge, exp_vld_out);
            end
        end
    endtask

    // =========================================================================
    // BLOCO PRINCIPAL DE ESTÍMULOS
    // =========================================================================
    reg [1:0] expected_edge;
    reg       expected_vld;

    initial begin
        // Inicialização limpa do ambiente
        pass_count = 0;
        fail_count = 0;
        nms_mag_in = 0;
        nms_vld_in = 0;
        
        $display("=========================================================");
        $display("INICIANDO TESTE DO CLASSIFICADOR DE LIMIAR (500 VALORES)");
        $display("=========================================================");
        
        // Loop para gerar 500 combinações de teste (Magnitudes de 0 a 499)
        for (i = 0; i < 500; i = i + 1) begin
            
            // A. Calcula a classificação esperada (O Gabarito)
            if (i >= HIGH) 
                expected_edge = 2'b11; // Borda Forte
            else if (i >= LOW) 
                expected_edge = 2'b01; // Borda Fraca
            else 
                expected_edge = 2'b00; // Fundo
                
            // B. Alterna o sinal de valid_in (0, 1, 0, 1...) usando módulo por 2
            expected_vld = (i % 2 == 0) ? 1'b1 : 1'b0;
            
            // C. Aciona a Task para injetar no módulo e checar o resultado
            check_expected(i, expected_vld, expected_edge, expected_vld);
        end
        
        // =========================================================================
        // RELATÓRIO FINAL
        // =========================================================================
        $display("=========================================================");
        $display("RELATORIO FINAL DE VERIFICACAO:");
        $display("Total de Testes : %0d", pass_count + fail_count);
        $display("Sucessos (PASS) : %0d", pass_count);
        $display("Falhas   (FAIL) : %0d", fail_count);
        $display("=========================================================");
        
        if (fail_count == 0)
            $display(">>> TESTE CONCLUIDO COM SUCESSO ABSOLUTO! O MODULO ESTA VALIDADO. <<<");
        else
            $display(">>> ATENCAO: ERROS ENCONTRADOS NA LOGICA DO MODULO! <<<");
            
        $finish;
    end

endmodule