module mag_approx #(
    parameter WIDTH = 12 // Largura de dados (ajustável para o processador)
)(
    input wire clk,
    input wire reset,
    input wire [(WIDTH):0] sum_in,  // Entrada: |Mx| + |My|
    output reg [(WIDTH):0] mag_out  // Saída para o comparador
);

    // Fio intermediário para o resultado combinacional
    wire [(WIDTH):0] shift_add_result;

    // Árvore combinacional explícita de Shift-Add para * 0.7071
    assign shift_add_result = (sum_in >> 1) + 
                              (sum_in >> 3) + 
                              (sum_in >> 4) + 
                              (sum_in >> 6) + 
                              (sum_in >> 8);

    // Registrador PIPO (Parallel-In Parallel-Out) do pipeline
    always @(posedge clk) begin
        if (reset) begin
            mag_out <= 0;
        end else begin
            mag_out <= shift_add_result; // Escrita e leitura paralelas
        end
    end

endmodule