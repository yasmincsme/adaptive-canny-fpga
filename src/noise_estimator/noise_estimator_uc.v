`timescale 1ns / 1ps

// Unidade de Controlo do Estimador de Ruído
// Máquina de Moore com 3 estados: IDLE → COMPARE → WRITE
module noise_estimator_uc (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire all_pixels_done,

    output reg  clr_cnt,
    output reg  compare_en,
    output reg  write_en,
    output reg  done
);

    localparam IDLE    = 2'b00;
    localparam COMPARE = 2'b01;
    localparam WRITE   = 2'b10;

    reg [1:0] state, next_state;

    // 1. Bloco Sequencial: Atualização do Estado
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // 2. Bloco Combinacional: Lógica de Próximo Estado
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    if (start)           next_state = COMPARE;
            COMPARE: if (all_pixels_done) next_state = WRITE;
            WRITE:                        next_state = IDLE;
            default:                      next_state = IDLE;
        endcase
    end

    // 3. Bloco Combinacional: Lógica de Saída (Moore)
    always @(*) begin
        clr_cnt    = 1'b0;
        compare_en = 1'b0;
        write_en   = 1'b0;
        done       = 1'b0;

        case (state)
            IDLE: begin
                clr_cnt = 1'b1;
            end
            COMPARE: begin
                compare_en = 1'b1;
            end
            WRITE: begin
                write_en = 1'b1;
                done     = 1'b1;
            end
        endcase
    end

endmodule
