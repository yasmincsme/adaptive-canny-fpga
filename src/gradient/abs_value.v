module abs_value #(parameter WIDTH = 11) (
    input  signed [WIDTH-1:0] num_in,
    output        [WIDTH-1:0] abs_num_out
);

    // Se o número for negativo (MSB == 1), inverte e soma 1. Caso contrário, mantém.
    assign abs_num_out = (num_in[WIDTH-1]) ? (~num_in + 1'b1) : num_in;

endmodule