`timescale 1ns / 1ps


module gradient_datapath (
    input wire clk,
    input wire reset,
   
    // Sinais de Controle (Handshaking)
    input  wire window_valid_in, // Alto quando p0-p8 têm dados reais da imagem
    output reg  pixel_valid_out, // Alto quando magnitude e direction estão prontos
   
    // Entrada: Janela 3x3 de píxeis de 8 bits
    input wire [7:0] p0, p1, p2,
    input wire [7:0] p3, p4, p5,
    input wire [7:0] p6, p7, p8,
   
    // Saídas sincronizadas
    output wire [11:0] magnitude,
    output wire [1:0]  direction
);


    // =========================================================================
    // 1. SINAIS INTERNOS (WIRES) & CONTROLE DE LATÊNCIA
    // =========================================================================
   
    // Controle
    reg valid_stage_1;
    always @(posedge clk) begin
        if (reset) begin
            valid_stage_1   <= 1'b0;
            pixel_valid_out <= 1'b0;
        end else begin
            valid_stage_1   <= window_valid_in;
            pixel_valid_out <= valid_stage_1;
        end
    end


    // Sinais de dados do Datapath
    wire signed [10:0] fx;
    wire signed [10:0] fy;
    wire [10:0] abs_fx;
    wire [10:0] abs_fy;
    wire [11:0] abs_fx_ext;
    wire [11:0] abs_fy_ext;
    wire [11:0] sum_abs;
    wire [11:0] diag_proj;


    assign abs_fx_ext = {1'b0, abs_fx};
    assign abs_fy_ext = {1'b0, abs_fy};
    assign sum_abs    = abs_fx_ext + abs_fy_ext;


    // =========================================================================
    // 2. INSTANCIAMENTO DE TODOS OS ESTÁGIOS
    // =========================================================================


    // Estágio 1: Filtro de Sobel (Possui Registradores PIPO internos)
    sobel_filter inst_sobel (
        .clk(clk),
        .reset(reset),
        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),
        .fx(fx),
        .fy(fy)
    );

    // Estágio 2: Lógica Combinacional (Módulos e Aproximação)
    abs_value #(.WIDTH(11)) inst_abs_fx (
        .num_in(fx),
        .abs_num_out(abs_fx)
    );


    abs_value #(.WIDTH(11)) inst_abs_fy (
        .num_in(fy),
        .abs_num_out(abs_fy)
    );


    mag_approx #(.WIDTH(12)) inst_mag_approx (
        .clk(clk),
        .reset(reset),
        .sum_in(sum_abs),
        .mag_out(diag_proj)
    );


    // Estágio 3: Árvore de Decisão (Possui Registradores PIPO na saída)
    gradient_decision_tree #(.WIDTH(12)) inst_decision_tree (
        .clk(clk),
        .reset(reset),
        .abs_fx(abs_fx_ext),
        .abs_fy(abs_fy_ext),
        .diag_proj(diag_proj),
        .sign_fx(fx[10]),
        .sign_fy(fy[10]),
        .magnitude(magnitude),
        .direction(direction)
    );

endmodule

