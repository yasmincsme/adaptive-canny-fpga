`timescale 1ns / 1ps
// iverilog -g2001 -o sim_wallace.out tb_wallace.v wallace_8x8_unsigned.v cla_adder.v half_adder.v full_adder.v cla_4bits.v
module tb_wallace;

    // Entradas do DUT declaradas como 'reg' para receberem atribuições no bloco initial
    reg [7:0]  A;
    reg [7:0]  B;
    
    // Saída do DUT declarada como 'wire'
    wire [15:0] Prod;
    
    // Variáveis auxiliares para verificação automática
    reg [15:0] expected;
    integer    error_count;
    integer    i, j; // Iteradores devem ser do tipo 'integer' em Verilog-2001

    // Instanciação do multiplicador (Device Under Test)
    wallace_8x8_unsigned dut (
        .A(A),
        .B(B),
        .Prod(Prod)
    );

    initial begin
        // Diretivas para gerar o ficheiro de ondas para o GTKWave
        $dumpfile("onda_wallace.vcd");
        $dumpvars(0, tb_wallace);

        $display("==================================================");
        $display("A Iniciar Teste: Tabuada de B (0 a 9) x A (0 a 255)");
        $display("==================================================");

        error_count = 0;

        // Ciclo externo: B a variar de 0 a 9
        for (j = 0; j <= 9; j = j + 1) begin
            B = j;
            
            // Ciclo interno: A a variar de 0 a 255
            for (i = 0; i <= 255; i = i + 1) begin
                A = i;
                
                // Atraso de 5 ns para permitir a propagação pela árvore combinacional
                #5; 
                
                // Cálculo do valor esperado utilizando o operador nativo do simulador
                expected = A * B;

                // Verificação automática: compara a saída física com a esperada
                if (Prod !== expected) begin
                    $display("[ERRO] A=%3d, B=%3d | Esperado=%5d, Obtido=%5d", A, B, expected, Prod);
                    error_count = error_count + 1;
                end
            end
            
            // Registo de progresso no terminal
            $display("Tabuada do %0d verificada com sucesso.", j);
        end

        // Relatório final
        $display("==================================================");
        if (error_count == 0) begin
            $display("SUCESSO ABSOLUTO! 0 erros encontrados em 2560 testes.");
        end else begin
            $display("FALHA. Total de erros encontrados: %0d", error_count);
        end
        $display("==================================================");

        // Termina a simulação
        $finish;
    end

endmodule