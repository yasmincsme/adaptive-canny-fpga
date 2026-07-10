module dual_port_ram(
    input clk,
    input cs,              // Chip Select global

    // Porta A - leitura/escrita
    input we_a,
    input [17:0] addr_a,
    input [7:0] data_in_a,
    output reg [7:0] data_out_a,

    // Porta B - SOMENTE leitura
    input [17:0] addr_b,
    output reg [7:0] data_out_b
);

    // Memória de 512 posições de 8 bits
    reg [7:0] mem [0:262143];

    always @(posedge clk) begin
        if (cs) begin
            // Escrita ou leitura na porta A
            if (!we_a)
                mem[addr_a] <= data_in_a;
            else
                data_out_a <= mem[addr_a];

            // Leitura na porta B
            data_out_b <= mem[addr_b];
        end
    end
endmodule