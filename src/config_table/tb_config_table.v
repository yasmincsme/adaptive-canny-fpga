`timescale 1ns / 1ps

// iverilog -g2001 -o sim_config_table.out tb_config_table.v config_table.v
module tb_config_table;

    reg         clk;
    reg  [3:0]  noise_level;
    reg  [1:0]  mdp;
    wire [1:0]  kernel_sel;
    wire [15:0] th_high;
    wire [15:0] th_low;

    integer error_count;

    config_table dut (
        .clk         (clk),
        .noise_level (noise_level),
        .mdp         (mdp),
        .kernel_sel  (kernel_sel),
        .th_high     (th_high),
        .th_low      (th_low)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task read_and_display;
        input [3:0] n;
        input [1:0] m;
        begin
            noise_level = n;
            mdp         = m;
            @(posedge clk);
            @(posedge clk);
            #1;
            $display("  N=%2d%% MDP=%0d%% → kernel_sel=%0d  TH_H=0x%04X (%.4f)  TH_L=0x%04X (%.4f)",
                (n + 1) * 5,
                91 + m,
                kernel_sel,
                th_high, th_high / 65536.0,
                th_low,  th_low  / 65536.0);
        end
    endtask

    initial begin
        $dumpfile("onda_config_table.vcd");
        $dumpvars(0, tb_config_table);

        $display("==================================================");
        $display("Teste da Tabela de Configuracao APS");
        $display("==================================================");

        error_count = 0;
        noise_level = 4'd0;
        mdp         = 2'd0;
        #20;

        // --------------------------------------------------------
        // TESTE 1: Verificar a primeira entrada (N=5%, MDP=91%)
        // Da Table 4: σ=0.9, TH_H=0.25
        // kernel_sel=0 (σ=0.9), th_high=0x4000, th_low=0x199A
        // --------------------------------------------------------
        $display("\n--- Teste 1: Entradas de canto ---");
        noise_level = 4'd0;
        mdp         = 2'd0;
        @(posedge clk);
        @(posedge clk);
        #1;

        if (kernel_sel !== 2'd0) begin
            $display("[ERRO] N=5%% MDP=91%%: kernel_sel esperado=0, obtido=%0d", kernel_sel);
            error_count = error_count + 1;
        end else begin
            $display("[OK]   N=5%% MDP=91%%: kernel_sel=0 (sigma=0.9)");
        end

        // --------------------------------------------------------
        // TESTE 2: N=5%, MDP=94% → σ=1.3 → kernel_sel=2
        // --------------------------------------------------------
        noise_level = 4'd0;
        mdp         = 2'd3;
        @(posedge clk);
        @(posedge clk);
        #1;

        if (kernel_sel !== 2'd2) begin
            $display("[ERRO] N=5%% MDP=94%%: kernel_sel esperado=2, obtido=%0d", kernel_sel);
            error_count = error_count + 1;
        end else begin
            $display("[OK]   N=5%% MDP=94%%: kernel_sel=2 (sigma=1.3)");
        end

        // --------------------------------------------------------
        // TESTE 3: N=70%, MDP=94% → σ=1.5 → kernel_sel=3
        // --------------------------------------------------------
        noise_level = 4'd13;
        mdp         = 2'd3;
        @(posedge clk);
        @(posedge clk);
        #1;

        if (kernel_sel !== 2'd3) begin
            $display("[ERRO] N=70%% MDP=94%%: kernel_sel esperado=3, obtido=%0d", kernel_sel);
            error_count = error_count + 1;
        end else begin
            $display("[OK]   N=70%% MDP=94%%: kernel_sel=3 (sigma=1.5)");
        end

        // --------------------------------------------------------
        // TESTE 4: Saturação — noise_level=15 tratado como 13
        // --------------------------------------------------------
        noise_level = 4'd15;
        mdp         = 2'd0;
        @(posedge clk);
        @(posedge clk);
        #1;

        if (kernel_sel !== 2'd3) begin
            $display("[ERRO] Saturacao: kernel_sel esperado=3, obtido=%0d", kernel_sel);
            error_count = error_count + 1;
        end else begin
            $display("[OK]   Saturacao (noise=15→13): kernel_sel=3");
        end

        // --------------------------------------------------------
        // TESTE 5: Varrimento completo — imprimir todas as entradas
        // --------------------------------------------------------
        $display("\n--- Varrimento completo da tabela ---");

        read_and_display(4'd0,  2'd0);
        read_and_display(4'd0,  2'd1);
        read_and_display(4'd0,  2'd2);
        read_and_display(4'd0,  2'd3);
        read_and_display(4'd6,  2'd0);
        read_and_display(4'd6,  2'd3);
        read_and_display(4'd13, 2'd0);
        read_and_display(4'd13, 2'd3);

        // --------------------------------------------------------
        // TESTE 6: TH_L ≈ 0.4 × TH_H
        // --------------------------------------------------------
        $display("\n--- Teste 6: Relacao TH_L = 0.4 * TH_H ---");
        noise_level = 4'd3;
        mdp         = 2'd3;
        @(posedge clk);
        @(posedge clk);
        #1;
        begin : th_check
            reg [31:0] expected_thl;
            expected_thl = (th_high * 4) / 10;
            if (th_low > expected_thl + 2 || th_low + 2 < expected_thl) begin
                $display("[ERRO] TH_L=0x%04X nao corresponde a 0.4*TH_H=0x%04X (esperado ~0x%04X)",
                    th_low, th_high, expected_thl[15:0]);
                error_count = error_count + 1;
            end else begin
                $display("[OK]   TH_L=0x%04X ≈ 0.4 * TH_H=0x%04X", th_low, th_high);
            end
        end

        // ========================================================================
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("SUCESSO! 0 erros encontrados.");
        end else begin
            $display("FALHA. Total de erros: %0d", error_count);
        end
        $display("==================================================");

        $finish;
    end

endmodule
