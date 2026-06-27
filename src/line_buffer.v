//`timescale 1ns / 1ps

module line_buffer #(
    parameter WIDTH = 512,        // Largura da imagem em pixels
    parameter DATA_WIDTH = 8      // Resolução de cor (8 bits para escala de cinza)
)(
    input  wire                  clk,
    input  wire                  rst_n,     // Reset ativo em nível baixo (padrão ASIC)
    input  wire                  pixel_vld, // Indica se o pixel na entrada é válido
    input  wire [DATA_WIDTH-1:0] pixel_in,  // Pixel da linha atual
    output wire [DATA_WIDTH-1:0] pixel_out  // Pixel da linha anterior (atrasado)
);

    // Array de memória que modela o Line Buffer (inferido como SRAM/Regs)
    reg [DATA_WIDTH-1:0] line_mem [0:WIDTH-1];
    
    // Ponteiro circular para endereçamento de leitura e escrita
    reg [$clog2(WIDTH)-1:0] r_w_ptr;
    
    // Registrador interno para segurar a saída e evitar race conditions
    reg [DATA_WIDTH-1:0] pixel_out_reg;

    // Atribuição contínua para a porta de saída
    assign pixel_out = pixel_out_reg;

    // Processo sínclono principal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_w_ptr       <= 0;
            pixel_out_reg <= 0;
            
            // Inicialização da memória apenas para o ambiente de simulação.
            // Isso evita sinais 'X' (indefinidos) nas primeiras leituras no SimVision.
            // O compilador da Cadence ignora este bloco na síntese física (ASIC).
            // synopsys translate_off
            begin : SIM_INIT
                integer i;
                for (i = 0; i < WIDTH; i = i + 1) begin
                    line_mem[i] = 0;
                end
            end
            // synopsys translate_on

        end else if (pixel_vld) begin
            
            // 1. LEITURA: Captura o pixel antigo armazenado nesta posição.
            // Como usamos '<=', o simulador pega o valor "antes" da subida do clock.
            pixel_out_reg <= line_mem[r_w_ptr];
            
            // 2. ESCRITA: Salva o novo pixel que está entrando na mesma posição.
            line_mem[r_w_ptr] <= pixel_in;

            // 3. ATUALIZAÇÃO DO PONTEIRO: Incremento circular em anel (0 até WIDTH-1)
            if (r_w_ptr == WIDTH - 1)
                r_w_ptr <= 0;
            else
                r_w_ptr <= r_w_ptr + 1;
                
        end
    end

endmodule