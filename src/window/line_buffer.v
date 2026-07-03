//`timescale 1ns / 1ps

module line_buffer #(
    parameter WIDTH = 512,        // Largura da imagem em pixels
    parameter DATA_WIDTH = 8      // Resolução de dados
)(
    input  wire                  clk,
    input  wire                  rst_n,     
    input  wire                  pixel_vld, 
    input  wire [DATA_WIDTH-1:0] pixel_in,  
    output wire [DATA_WIDTH-1:0] pixel_out  
);

    // Array de memória (BRAM)
    reg [DATA_WIDTH-1:0] line_mem [0:WIDTH-1];
    
    // Agora temos apenas o ponteiro de escrita
    reg [$clog2(WIDTH)-1:0] w_ptr;
    
    // Registrador interno para a porta de saída
    reg [DATA_WIDTH-1:0] pixel_out_reg;
    assign pixel_out = pixel_out_reg;

    // PONTEIRO DE LEITURA ADIANTADO (Look-ahead)
    // Ele aponta sempre 1 passo à frente do ponteiro de escrita, 
    // compensando o ciclo de clock gasto pelo pixel_out_reg.
    wire [$clog2(WIDTH)-1:0] r_ptr;
    assign r_ptr = (w_ptr == WIDTH - 1) ? 0 : w_ptr + 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr         <= 0;
            pixel_out_reg <= 0;
            
            // synopsys translate_off
            begin : SIM_INIT
                integer i;
                for (i = 0; i < WIDTH; i = i + 1) begin
                    line_mem[i] = 0;
                end
            end
            // synopsys translate_on

        end else if (pixel_vld) begin
            
            // 1. LEITURA: Lê da posição ADIANTADA (r_ptr)
            pixel_out_reg <= line_mem[r_ptr];
            
            // 2. ESCRITA: Escreve na posição ATUAL (w_ptr)
            line_mem[w_ptr] <= pixel_in;

            // 3. ATUALIZAÇÃO DO PONTEIRO: Avança usando a lógica já calculada no r_ptr
            w_ptr <= r_ptr;
                
        end
    end

endmodule