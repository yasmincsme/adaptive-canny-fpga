`timescale 1ns / 1ps

// Tabela de Configuração para o Canny APS
//
// ROM de 56 palavras × 34 bits, inicializada a partir de config_table.mem
// gerado pelo script scripts/generate_config_table.py.
//
// Endereçamento (6 bits):
//   addr = {noise_level[3:0], mdp[1:0]}
//   noise_level: 0 = 5%, 1 = 10%, ..., 13 = 70%  (saída do noise_estimator)
//   mdp:         0 = 91%, 1 = 92%, 2 = 93%, 3 = 94%
//
// Formato de cada palavra:
//   [33:32] kernel_sel  — selecciona o kernel Gaussiano
//                         00 = σ=0.9 (5×5), 01 = σ=1.1 (5×5)
//                         10 = σ=1.3 (7×7), 11 = σ=1.5 (7×7)
//   [31:16] th_high     — TH_H em ponto fixo Q0.16
//   [15:0]  th_low      — TH_L em ponto fixo Q0.16

module config_table (
    input  wire        clk,
    input  wire [3:0]  noise_level,   // Do noise_estimator (0–13)
    input  wire [1:0]  mdp,           // Nível MDP (0=91%, 1=92%, 2=93%, 3=94%)

    output wire [1:0]  kernel_sel,    // Selecção do kernel Gaussiano
    output wire [15:0] th_high,       // Limiar superior (TH_H) em Q0.16
    output wire [15:0] th_low         // Limiar inferior (TH_L) em Q0.16
);

    // ========================================================================
    // 1. MEMÓRIA ROM (56 palavras × 34 bits)
    // ========================================================================
    reg [33:0] rom [0:55];

    initial begin
        $readmemh("config_table.mem", rom);
    end

    // ========================================================================
    // 2. CÁLCULO DO ENDEREÇO
    // ========================================================================
    wire [5:0] addr;

    // Saturação: noise_level > 13 é tratado como 13
    wire [3:0] noise_clamped = (noise_level > 4'd13) ? 4'd13 : noise_level;

    assign addr = {noise_clamped, mdp};

    // ========================================================================
    // 3. LEITURA SÍNCRONA
    // ========================================================================
    reg [33:0] rom_data;

    always @(posedge clk) begin
        rom_data <= rom[addr];
    end

    // ========================================================================
    // 4. DECOMPOSIÇÃO DA PALAVRA
    // ========================================================================
    assign kernel_sel = rom_data[33:32];
    assign th_high    = rom_data[31:16];
    assign th_low     = rom_data[15:0];

endmodule
