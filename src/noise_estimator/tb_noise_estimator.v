`timescale 1ns / 1ps

// iverilog -g2001 -o sim_noise_estimator.out tb_noise_estimator.v noise_estimator.v noise_estimator_uc.v
module tb_noise_estimator;

    // ========================================================================
    // SINAIS DO DUT
    // ========================================================================
    reg          clk;
    reg          rst_n;
    reg          start;
    reg  [391:0] window_flat;
    reg  [7:0]   threshold;
    wire [3:0]   noise_level;
    wire         done;

    integer error_count;
    integer i;

    // ========================================================================
    // INSTANCIAÇÃO DO DUT
    // ========================================================================
    noise_estimator dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .window_flat (window_flat),
        .threshold   (threshold),
        .noise_level (noise_level),
        .done        (done)
    );

    // ========================================================================
    // GERAÇÃO DO RELÓGIO (Período = 10 ns → 100 MHz)
    // ========================================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ========================================================================
    // TAREFA AUXILIAR: Preencher a janela 7×7 com um valor uniforme
    // ========================================================================
    task fill_window_uniform;
        input [7:0] val;
        integer idx;
        begin
            for (idx = 0; idx < 49; idx = idx + 1) begin
                window_flat[(idx*8) +: 8] = val;
            end
        end
    endtask

    // ========================================================================
    // TAREFA AUXILIAR: Corromper N píxeis da região interior 5×5
    // ========================================================================
    task corrupt_inner_pixels;
        input integer num_corrupt;
        input [7:0]  corrupt_val;

        integer row, col, flat_idx, cnt;
        begin
            cnt = 0;
            for (row = 1; row <= 5 && cnt < num_corrupt; row = row + 1) begin
                for (col = 1; col <= 5 && cnt < num_corrupt; col = col + 1) begin
                    flat_idx = row * 7 + col;
                    window_flat[(flat_idx*8) +: 8] = corrupt_val;
                    cnt = cnt + 1;
                end
            end
        end
    endtask

    // ========================================================================
    // TAREFA AUXILIAR: Disparar o estimador e aguardar 'done'
    // ========================================================================
    task run_estimator;
        begin
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            wait (done == 1'b1);
            @(posedge clk);
            #1;
        end
    endtask

    // ========================================================================
    // TAREFA AUXILIAR: Verificar resultado
    // ========================================================================
    task check_result;
        input [3:0] expected;
        input [8*48-1:0] test_name;
        begin
            if (noise_level !== expected) begin
                $display("[ERRO] %0s — Esperado: %0d, Obtido: %0d", test_name, expected, noise_level);
                error_count = error_count + 1;
            end else begin
                $display("[OK]   %0s — noise_level = %0d", test_name, noise_level);
            end
        end
    endtask

    // ========================================================================
    // SEQUÊNCIA DE TESTES
    // ========================================================================
    initial begin
        $dumpfile("onda_noise_estimator.vcd");
        $dumpvars(0, tb_noise_estimator);

        $display("==================================================");
        $display("A Iniciar Teste do Estimador de Ruido");
        $display("==================================================");

        error_count = 0;
        rst_n       = 1'b0;
        start       = 1'b0;
        threshold   = 8'd30;
        window_flat = 392'd0;

        // Reset
        #20;
        rst_n = 1'b1;
        #10;

        // --------------------------------------------------------
        // TESTE 1: Janela uniforme (sem ruído)
        // abs_diff = 0 para todos os píxeis → 0 detectados
        // Esperado: noise_level = 0 (5%)
        // --------------------------------------------------------
        $display("\n--- Teste 1: Janela uniforme (128) ---");
        fill_window_uniform(8'd128);
        run_estimator;
        check_result(4'd0, "Uniforme, 0 detectados");

        // --------------------------------------------------------
        // TESTE 2: Gradiente suave (sem corrupção)
        // Gradiente linear: média dos vizinhos ≈ centro → 0 detectados
        // Esperado: noise_level = 0 (5%)
        // --------------------------------------------------------
        $display("\n--- Teste 2: Gradiente suave ---");
        for (i = 0; i < 49; i = i + 1) begin
            window_flat[(i*8) +: 8] = 100 + (i / 7) * 3 + (i % 7) * 2;
        end
        run_estimator;
        check_result(4'd0, "Gradiente suave, 0 detectados");

        // --------------------------------------------------------
        // TESTE 3: 5 píxeis corrompidos na fila (valor=255, base=128)
        // 5 corrompidos + 5 vizinhos com abs_diff=31 > 30 = 10 detectados
        // 10/25 = 40% → noise_level = 7
        // --------------------------------------------------------
        $display("\n--- Teste 3: 5 pixeis corrompidos em fila ---");
        fill_window_uniform(8'd128);
        corrupt_inner_pixels(5, 8'd255);
        run_estimator;
        check_result(4'd7, "5 corrompidos, 10 detectados (40%%)");

        // --------------------------------------------------------
        // TESTE 4: 25 interiores = 0, borda = 128
        // Apenas os 16 píxeis adjacentes à borda têm avg > 0
        // → 16 detectados, 16/25 = 64% → noise_level = 12 (65%)
        // --------------------------------------------------------
        $display("\n--- Teste 4: Todos interiores corrompidos ---");
        fill_window_uniform(8'd128);
        corrupt_inner_pixels(25, 8'd0);
        run_estimator;
        check_result(4'd12, "25 corrompidos, 16 detectados (65%%)");

        // --------------------------------------------------------
        // TESTE 5: Limiar alto (threshold=200)
        // abs_diff máximo ≈ 96 < 200 → 0 detectados
        // Esperado: noise_level = 0 (5%)
        // --------------------------------------------------------
        $display("\n--- Teste 5: Limiar alto (threshold=200) ---");
        threshold = 8'd200;
        fill_window_uniform(8'd128);
        corrupt_inner_pixels(5, 8'd255);
        run_estimator;
        check_result(4'd0, "Threshold alto, 0 detectados");

        // --------------------------------------------------------
        // TESTE 6: Padrão xadrez com limiar baixo (threshold=5)
        // Alternância entre 100 e 150 → abs_diff ≈ 25 > 5
        // Esperado: noise_level > 0
        // --------------------------------------------------------
        $display("\n--- Teste 6: Xadrez com limiar baixo ---");
        threshold = 8'd5;
        for (i = 0; i < 49; i = i + 1) begin
            if (((i / 7) + (i % 7)) % 2 == 0)
                window_flat[(i*8) +: 8] = 8'd100;
            else
                window_flat[(i*8) +: 8] = 8'd150;
        end
        run_estimator;
        if (noise_level > 4'd0) begin
            $display("[OK]   Xadrez — noise_level = %0d (> 0 esperado)", noise_level);
        end else begin
            $display("[ERRO] Xadrez — Esperado: > 0, Obtido: %0d", noise_level);
            error_count = error_count + 1;
        end

        // --------------------------------------------------------
        // TESTE 7: Reset durante processamento
        // Após reset, re-processar janela uniforme → noise_level = 0
        // --------------------------------------------------------
        $display("\n--- Teste 7: Reset e re-processamento ---");
        threshold = 8'd30;
        fill_window_uniform(8'd128);
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b0;
        #20;
        rst_n = 1'b1;
        #10;
        fill_window_uniform(8'd128);
        run_estimator;
        check_result(4'd0, "Apos reset, janela uniforme");

        // --------------------------------------------------------
        // TESTE 8: 1 pixel corrompido isolado no centro
        // Pixel (3,3)=255, base=128 → detecta centro + 4 vizinhos = 5
        // 5/25 = 20% → noise_level = 3
        // --------------------------------------------------------
        $display("\n--- Teste 8: 1 pixel corrompido isolado ---");
        threshold = 8'd30;
        fill_window_uniform(8'd128);
        window_flat[(24*8) +: 8] = 8'd255;
        run_estimator;
        check_result(4'd3, "1 corrompido, 5 detectados (20%%)");

        // ========================================================================
        // RELATÓRIO FINAL
        // ========================================================================
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("SUCESSO! 0 erros encontrados em 8 testes.");
        end else begin
            $display("FALHA. Total de erros encontrados: %0d", error_count);
        end
        $display("==================================================");

        $finish;
    end

endmodule
